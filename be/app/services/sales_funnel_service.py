import uuid
import io
import zipfile
import time
import traceback
from datetime import date, datetime, timedelta
import pandas as pd
import requests
from sqlalchemy import or_
from models import db, SalesFunnelReport, ReportDetail
from utils.logger import log_event
from utils.token_manager import get_api_key

def fetch_sales_funnel_period(start_date=None, end_date=None, nm_ids=None, delete_old=True):
    """
    Запрашивает отчёт DETAIL_HISTORY_REPORT за период и сохраняет в БД.
    :param start_date: str YYYY-MM-DD или None (тогда сегодня - 30 дней)
    :param end_date: str YYYY-MM-DD или None (тогда сегодня)
    :param nm_ids: список int – артикулы WB. Если None, отчёт по всем товарам.
    :param delete_old: удалять ли старые записи за этот период перед сохранением (по умолч. True)
    :return: количество сохранённых записей
    """
    if end_date is None:
        end_date = date.today()
    if start_date is None:
        start_date = end_date - timedelta(days=30)

    start_str = start_date.isoformat()
    end_str = end_date.isoformat()

    report_id = str(uuid.uuid4())
    payload = {
        "id": report_id,
        "reportType": "DETAIL_HISTORY_REPORT",
        "userReportName": f"Funnel_report_{start_str}_{end_str}",
        "params": {
            "startDate": start_str,
            "endDate": end_str,
            "aggregationLevel": "day",
            "skipDeletedNm": True,
            "timezone": "Europe/Moscow"
        }
    }
    if nm_ids is not None:
        payload["params"]["nmIDs"] = nm_ids
    else:
        payload["params"]["nmIDs"] = []

    headers = {
        "Authorization": f"Bearer {get_api_key()}",
        "Content-Type": "application/json"
    }

    url_create = "https://seller-analytics-api.wildberries.ru/api/v2/nm-report/downloads"
    resp = requests.post(url_create, json=payload, headers=headers)
    if resp.status_code != 200:
        log_event('ERROR', 'fetch_sales_funnel', f'Ошибка создания отчёта: {resp.status_code}', {'text': resp.text})
        return 0
    log_event('INFO', 'fetch_sales_funnel', f'Задание создано: {report_id}')

    max_attempts = 60
    base_delay = 5
    for attempt in range(max_attempts):
        url_status = "https://seller-analytics-api.wildberries.ru/api/v2/nm-report/downloads"
        params = {"filter[downloadIds][]": report_id}
        resp = requests.get(url_status, headers=headers, params=params)
        if resp.status_code == 429:
            delay = min(base_delay * (2 ** attempt), 30)
            log_event('WARNING', 'fetch_sales_funnel', f'Статус 429, пауза {delay} сек')
            time.sleep(delay)
            continue
        if resp.status_code != 200:
            log_event('WARNING', 'fetch_sales_funnel', f'Статус !=200, код {resp.status_code}, повтор')
            time.sleep(base_delay)
            continue

        data = resp.json()
        reports = data.get('data', [])
        if not reports:
            time.sleep(base_delay)
            continue

        status = reports[0].get('status')
        if status == 'SUCCESS':
            log_event('INFO', 'fetch_sales_funnel', f'Отчёт готов (retry {attempt})')
            break
        elif status == 'FAILED':
            log_event('ERROR', 'fetch_sales_funnel', 'Генерация отчёта провалилась')
            return 0
        else:
            log_event('DEBUG', 'fetch_sales_funnel', f'Статус: {status}, ожидание...')
            time.sleep(base_delay)
    else:
        log_event('ERROR', 'fetch_sales_funnel', 'Превышено время ожидания отчёта')
        return 0

    url_download = f"https://seller-analytics-api.wildberries.ru/api/v2/nm-report/downloads/file/{report_id}"
    resp = requests.get(url_download, headers=headers)
    if resp.status_code != 200:
        log_event('ERROR', 'fetch_sales_funnel', 'Ошибка скачивания', {'code': resp.status_code})
        return 0

    try:
        with zipfile.ZipFile(io.BytesIO(resp.content)) as z:
            csv_filename = z.namelist()[0]
            with z.open(csv_filename) as f:
                df = pd.read_csv(f, dtype=str)
    except Exception as e:
        log_event('ERROR', 'fetch_sales_funnel', 'Ошибка распаковки/чтения CSV', {'error': str(e)})
        return 0

    df = df.rename(columns={
        'nmID': 'nm_id',
        'dt': 'date',
        'openCardCount': 'open_count',
        'addToCartCount': 'cart_count',
        'ordersCount': 'order_count',
        'ordersSumRub': 'order_sum',
        'buyoutsCount': 'buyout_count',
        'buyoutsSumRub': 'buyout_sum',
        'buyoutPercent': 'buyout_percent',
        'addToCartConversion': 'add_to_cart_conversion',
        'cartToOrderConversion': 'cart_to_order_conversion',
        'addToWishlist': 'add_to_wishlist_count'
    })
    keep_cols = ['nm_id', 'date', 'open_count', 'cart_count', 'order_count', 'order_sum',
                 'buyout_count', 'buyout_sum', 'buyout_percent', 'add_to_cart_conversion',
                 'cart_to_order_conversion', 'add_to_wishlist_count', 'currency']
    df = df[[c for c in keep_cols if c in df.columns]]

    df['nm_id'] = pd.to_numeric(df['nm_id'], errors='coerce').fillna(0).astype(int)
    df['date'] = pd.to_datetime(df['date']).dt.date
    numeric_cols = ['open_count', 'cart_count', 'order_count', 'order_sum',
                    'buyout_count', 'buyout_sum', 'buyout_percent',
                    'add_to_cart_conversion', 'cart_to_order_conversion', 'add_to_wishlist_count']
    for col in numeric_cols:
        df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0)
    df['currency'] = df.get('currency', 'RUB').fillna('RUB')
    df = df[df['nm_id'] != 0]

    df['title'] = None
    df['vendor_code'] = None
    df['brand_name'] = None

    if delete_old:
        period_start = start_date
        period_end = end_date
        deleted = SalesFunnelReport.query.filter(
            SalesFunnelReport.date.between(period_start, period_end)
        ).delete()
        db.session.commit()
        log_event('INFO', 'fetch_sales_funnel', f'Удалено {deleted} старых записей за период')

    saved = 0
    for _, row in df.iterrows():
        try:
            record = SalesFunnelReport(
                date=row['date'],
                nm_id=row['nm_id'],
                title=row.get('title'),
                vendor_code=row.get('vendor_code'),
                brand_name=row.get('brand_name'),
                open_count=row['open_count'],
                cart_count=row['cart_count'],
                order_count=row['order_count'],
                order_sum=row['order_sum'],
                buyout_count=row['buyout_count'],
                buyout_sum=row['buyout_sum'],
                buyout_percent=row['buyout_percent'],
                add_to_cart_conversion=row['add_to_cart_conversion'],
                cart_to_order_conversion=row['cart_to_order_conversion'],
                add_to_wishlist_count=row['add_to_wishlist_count'],
                currency=row['currency']
            )
            db.session.add(record)
            saved += 1
            if saved % 500 == 0:
                db.session.commit()
        except Exception as e:
            log_event('ERROR', 'fetch_sales_funnel', f'Ошибка вставки строки: {e}', {'row': row.to_dict()})
    db.session.commit()
    log_event('INFO', 'fetch_sales_funnel', f'Сохранено {saved} записей воронки продаж')
    return saved


def scheduled_sales_funnel_update():
    """Плановая задача для обновления воронки продаж (за последние 30 дней)"""
    end = date.today()
    start = end - timedelta(days=30)
    log_event('INFO', 'scheduled_sales_funnel', f'Запуск планового обновления воронки за {start} - {end}')
    fetch_sales_funnel_period(start, end, nm_ids=None, delete_old=True)


def enrich_all_existing_reports():
    """Обогащение всех существующих записей в базе данных (заполнение sa_name и nm_id по srid)"""
    empty_records = ReportDetail.query.filter(
        or_(
            ReportDetail.sa_name.is_(None),
            ReportDetail.sa_name == '',
            ReportDetail.nm_id.is_(None),
            ReportDetail.nm_id == 0
        )
    ).all()
    
    if not empty_records:
        return {"status": "no_empty_records"}
    
    srids = [record.srid for record in empty_records if record.srid]
    srid_to_data = {}
    batch_size = 1000
    
    for i in range(0, len(srids), batch_size):
        batch = srids[i:i + batch_size]
        results = db.session.query(
            ReportDetail.srid,
            ReportDetail.sa_name,
            ReportDetail.nm_id
        ).filter(
            ReportDetail.srid.in_(batch),
            ReportDetail.sa_name.isnot(None),
            ReportDetail.sa_name != '',
            ReportDetail.nm_id.isnot(None),
            ReportDetail.nm_id != 0
        ).all()
        
        for result in results:
            srid_to_data[result.srid] = (result.sa_name, result.nm_id)
    
    updated_count = 0
    for record in empty_records:
        if record.srid and record.srid in srid_to_data:
            sa_name, nm_id = srid_to_data[record.srid]
            if record.sa_name in [None, ''] and sa_name:
                record.sa_name = sa_name
            if record.nm_id in [None, 0] and nm_id:
                record.nm_id = nm_id
            updated_count += 1
    
    db.session.commit()
    
    return {
        "status": "success",
        "total_empty_records": len(empty_records),
        "updated_records": updated_count
    }