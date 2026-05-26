import uuid
import threading
import traceback
from datetime import datetime, timedelta
from io import BytesIO
import pandas as pd
from utils.logger import log_event
from services.order_feed_api import OrderFeedPrivateAPI

class AsyncOrderExportTask:
    def __init__(self, task_id, date_from, date_to, authorize_v3, wb_seller_lk, cookie):
        self.task_id = task_id
        self.date_from = date_from
        self.date_to = date_to
        self.authorize_v3 = authorize_v3
        self.wb_seller_lk = wb_seller_lk
        self.cookie = cookie
        self.status = 'pending'   # pending, done, error
        self.result = None        # если done, то bytes с CSV
        self.error = None
        self.created_at = datetime.utcnow()
        self.worker_thread = None

# Хранилище задач (в памяти)
async_tasks = {}

def get_export_task_dates(task_id):
    """Возвращает (date_from, date_to) для задачи или None"""
    task = async_tasks.get(task_id)
    if not task:
        return None
    return task.date_from, task.date_to

def cleanup_old_tasks():
    """Удаляет задачи старше 1 часа"""
    now = datetime.utcnow()
    to_delete = [tid for tid, task in async_tasks.items() if now - task.created_at > timedelta(hours=1)]
    for tid in to_delete:
        del async_tasks[tid]

def run_async_export(task_id):
    """Фоновая задача для экспорта заказов в CSV с подробным логированием"""
    print(f"[DEBUG] run_async_export started for task {task_id}")
    
    # Внимание: эта функция будет вызываться внутри app.app_context() (см. эндпоинт)
    # Поэтому здесь нет with app.app_context()
    
    log_event('INFO', 'run_async_export', f'Запуск фоновой задачи {task_id}')
    
    task = async_tasks.get(task_id)
    if not task:
        print(f"[ERROR] Task {task_id} not found")
        log_event('ERROR', 'run_async_export', f'Задача {task_id} не найдена в хранилище')
        return
    
    try:
        log_event('INFO', 'run_async_export', f'Параметры задачи {task_id}', {
            'date_from': task.date_from,
            'date_to': task.date_to,
            'authorize_v3': task.authorize_v3[:10] + '...' if task.authorize_v3 else None,
            'wb_seller_lk': task.wb_seller_lk[:10] + '...' if task.wb_seller_lk else None,
            'cookie_exists': bool(task.cookie)
        })
        
        # 1. Создаём клиент для приватного API
        client = OrderFeedPrivateAPI(task.authorize_v3, task.wb_seller_lk, task.cookie)
        log_event('INFO', 'run_async_export', f'Клиент OrderFeedPrivateAPI создан для задачи {task_id}')
        
        # 2. Установка периода
        log_event('INFO', 'run_async_export', f'Установка периода {task.date_from} - {task.date_to}')
        client.set_period(task.date_from, task.date_to)
        
        # 3. Создание отчёта
        report_name = f"OrdersExport_{task.date_from}_{task.date_to}_{int(datetime.now().timestamp())}"
        log_event('INFO', 'run_async_export', f'Создание отчёта с именем {report_name}')
        report_id = client.create_report(report_name, task.date_from, task.date_to)
        log_event('INFO', 'run_async_export', f'Отчёт создан, report_id={report_id}')
        
        # 4. Ожидание готовности
        log_event('INFO', 'run_async_export', f'Ожидание готовности отчёта {report_id}')
        client.wait_for_done(report_id, timeout=300)
        log_event('INFO', 'run_async_export', f'Отчёт {report_id} готов')
        
        # 5. Получение токена
        token = client.get_download_token()
        log_event('INFO', 'run_async_export', f'Токен скачивания получен')
        
        # 6. Скачивание и конвертация в Parquet
        log_event('INFO', 'run_async_export', f'Скачивание и конвертация в Parquet')
        parquet_bytes = client.download_and_convert_to_parquet(report_id, token)
        log_event('INFO', 'run_async_export', f'Parquet получен, размер {len(parquet_bytes)} байт')
        
        # 7. Конвертация Parquet -> CSV
        log_event('INFO', 'run_async_export', f'Конвертация Parquet в CSV')
        df = pd.read_parquet(BytesIO(parquet_bytes))
        csv_buffer = BytesIO()
        df.to_csv(csv_buffer, index=False, encoding='utf-8-sig')
        csv_buffer.seek(0)
        task.result = csv_buffer.getvalue()
        task.status = 'done'
        
        log_event('INFO', 'run_async_export', f'Задача {task_id} успешно завершена, CSV размер {len(task.result)} байт')
        
    except Exception as e:
        task.status = 'error'
        task.error = str(e)
        error_trace = traceback.format_exc()
        print(f"[ERROR] Task {task_id} failed: {e}\n{error_trace}")
        log_event('ERROR', 'run_async_export', f'Ошибка в задаче {task_id}', {
            'error': str(e),
            'traceback': error_trace
        })
    finally:
        task.worker_thread = None
        cleanup_old_tasks()


def create_export_task(date_from, date_to, authorize_v3, wb_seller_lk, cookie):
    """Создаёт задачу экспорта, запускает фоновый поток и возвращает task_id"""
    task_id = str(uuid.uuid4())
    task = AsyncOrderExportTask(task_id, date_from, date_to, authorize_v3, wb_seller_lk, cookie)
    
    thread = threading.Thread(target=run_async_export, args=(task_id,))
    thread.daemon = True
    thread.start()
    task.worker_thread = thread
    
    async_tasks[task_id] = task
    cleanup_old_tasks()
    
    log_event('INFO', 'create_export_task', f'Создана задача {task_id}', {'date_from': date_from, 'date_to': date_to})
    return task_id


def get_export_task_status(task_id):
    """Возвращает статус задачи: pending/done/error и дополнительные данные"""
    task = async_tasks.get(task_id)
    if not task:
        return None
    
    response = {
        "task_id": task_id,
        "status": task.status,
        "created_at": task.created_at.isoformat()
    }
    if task.status == 'error':
        response["error"] = task.error
    elif task.status == 'done':
        response["download_url"] = f"/api/orders/export-csv/download/{task_id}"
    return response


def get_export_task_result(task_id):
    """Возвращает CSV данные (bytes) для готовой задачи, иначе None"""
    task = async_tasks.get(task_id)
    if not task or task.status != 'done' or not task.result:
        return None
    return task.result