import time
import requests
from datetime import date, datetime
from utils.logger import log_event
from utils.token_manager import get_api_key
from models import db, WarehouseRemains
from utils.rate_limiter import RateLimiter

class WarehouseRemainsClient:
    """Клиент для работы с API остатков на складах WB"""
    def __init__(self):
        self.base_url = "https://seller-analytics-api.wildberries.ru/api/v1/warehouse_remains"
        self.limiter = RateLimiter()

    def create_report(self, api_key, params=None):
        """Создание задания на отчёт"""
        if params is None:
            params = {
                'groupByNm': True,
                'groupBySa': True,
                'groupByBarcode': True,
                'groupBySize': True,
                'groupByBrand': False,
                'groupBySubject': False,
                'locale': 'ru',
                'filterPics': 0,
                'filterVolume': 0
            }
        headers = {'Authorization': api_key}
        bucket = self.limiter.get_bucket(self.base_url)
        self.limiter.wait_for_token(bucket)

        response = requests.get(self.base_url, headers=headers, params=params, timeout=30)
        self.limiter.handle_response(bucket, response)
        if response.status_code == 200:
            data = response.json()
            task_id = data.get('data', {}).get('taskId')
            log_event('INFO', 'WarehouseRemainsClient.create_report', f'Задание создано: {task_id}')
            return task_id
        else:
            log_event('ERROR', 'WarehouseRemainsClient.create_report', f'Ошибка {response.status_code}: {response.text}')
            return None

    def check_status(self, api_key, task_id):
        """Проверка статуса задания"""
        url = f"{self.base_url}/tasks/{task_id}/status"
        headers = {'Authorization': api_key}
        time.sleep(5)  # простейший rate limit
        response = requests.get(url, headers=headers, timeout=30)
        if response.status_code == 200:
            data = response.json()
            return data.get('data', {}).get('status')
        else:
            log_event('ERROR', 'WarehouseRemainsClient.check_status', f'Ошибка {response.status_code}: {response.text}')
            return None

    def download_report(self, api_key, task_id):
        """Скачивание отчёта"""
        url = f"{self.base_url}/tasks/{task_id}/download"
        headers = {'Authorization': api_key}
        bucket = self.limiter.get_bucket(url)
        self.limiter.wait_for_token(bucket)
        response = requests.get(url, headers=headers, timeout=60)
        self.limiter.handle_response(bucket, response)
        if response.status_code == 200:
            return response.json()
        else:
            log_event('ERROR', 'WarehouseRemainsClient.download_report', f'Ошибка {response.status_code}: {response.text}')
            return None


def fetch_warehouse_remains():
    """Основная функция: создание отчёта, ожидание, обработка и сохранение в БД"""
    start_time = time.time()
    method_name = "fetch_warehouse_remains"
    try:
        log_event('INFO', method_name, 'Начало обновления остатков по складам')
        api_key = get_api_key()
        if not api_key:
            log_event('ERROR', method_name, 'Отсутствует API токен')
            return

        client = WarehouseRemainsClient()
        task_id = client.create_report(api_key)
        if not task_id:
            return

        max_attempts = 60
        for attempt in range(max_attempts):
            status = client.check_status(api_key, task_id)
            if status == 'done':
                log_event('INFO', method_name, f'Отчёт готов, попытка {attempt+1}')
                break
            elif status in ('canceled', 'purged'):
                log_event('ERROR', method_name, f'Отчёт отменён или удалён: {status}')
                return
            else:
                log_event('DEBUG', method_name, f'Статус: {status}, ожидание 5 секунд')
                time.sleep(5)
        else:
            log_event('ERROR', method_name, 'Превышено время ожидания отчёта')
            return

        report_data = client.download_report(api_key, task_id)
        if not report_data or not isinstance(report_data, list):
            log_event('ERROR', method_name, 'Не удалось получить данные отчёта')
            return

        today = date.today()
        records_to_insert = []
        for item in report_data:
            warehouses = item.get('warehouses', [])
            for wh in warehouses:
                records_to_insert.append({
                    'brand': item.get('brand'),
                    'subject_name': item.get('subjectName'),
                    'vendor_code': item.get('vendorCode'),
                    'nm_id': item.get('nmId'),
                    'barcode': item.get('barcode'),
                    'tech_size': item.get('techSize'),
                    'volume': item.get('volume'),
                    'warehouse_name': wh.get('warehouseName'),
                    'quantity': wh.get('quantity', 0),
                    'report_date': today
                })

        if not records_to_insert:
            log_event('WARNING', method_name, 'Нет данных для сохранения')
            return

        deleted = db.session.query(WarehouseRemains).filter(WarehouseRemains.report_date == today).delete()
        log_event('INFO', method_name, f'Удалено старых записей за {today}: {deleted}')

        batch_size = 500
        for i in range(0, len(records_to_insert), batch_size):
            batch = records_to_insert[i:i+batch_size]
            db.session.execute(WarehouseRemains.__table__.insert(), batch)
            db.session.commit()
            log_event('DEBUG', method_name, f'Вставлено {len(batch)} записей')

        total_processed = len(records_to_insert)
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Обновление завершено, сохранено {total_processed} записей',
                  duration_ms=duration, records_processed=total_processed)
        print(f"✅ Обновлены остатки по складам: {total_processed} строк")

    except Exception as e:
        db.session.rollback()
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Критическая ошибка', {'error': str(e), 'traceback': traceback.format_exc()},
                  duration_ms=duration)
        raise