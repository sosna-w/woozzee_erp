import os
import traceback
from datetime import date, timedelta
from utils.logger import log_event
from services.order_feed_api import OrderFeedPrivateAPI

def get_private_keys_from_db():
    """Возвращает словарь с authorize_v3, wb_seller_lk, cookie из таблицы PrivateKey"""
    from models import PrivateKey
    pkeys = PrivateKey.get_instance()
    return {
        'authorize_v3': pkeys.authorize_v3,
        'wb_seller_lk': pkeys.wb_seller_lk,
        'cookie': pkeys.cookie
    }

def fetch_and_save_order_feed_21_days():
    """Загружает ленту заказов за последние 21 день и сохраняет в CSV (обновляет раз в час).
       Предполагается, что функция вызывается внутри app.app_context().
    """
    try:
        keys = get_private_keys_from_db()
        if not keys['authorize_v3'] or not keys['wb_seller_lk'] or not keys['cookie']:
            log_event('ERROR', 'fetch_and_save_order_feed_21_days', 'Отсутствуют приватные ключи')
            return

        end_date = date.today() - timedelta(days=1)
        start_date = end_date - timedelta(days=20)
        start_str = start_date.isoformat()
        end_str = end_date.isoformat()

        new_filename = f"order_feed_{start_str}_to_{end_str}.csv"
        folder = os.path.join('uploads', 'orderfeed')
        os.makedirs(folder, exist_ok=True)

        for f in os.listdir(folder):
            if f.startswith('order_feed_') and f.endswith('.csv'):
                os.remove(os.path.join(folder, f))
                log_event('INFO', 'fetch_and_save_order_feed_21_days', f'Удалён старый файл: {f}')

        csv_path = os.path.join(folder, new_filename)
        log_event('INFO', 'fetch_and_save_order_feed_21_days', f'Создание нового файла {new_filename}')

        client = OrderFeedPrivateAPI(
            authorize_v3=keys['authorize_v3'],
            wb_seller_lk=keys['wb_seller_lk'],
            cookie=keys['cookie']
        )

        success = client.fetch_and_save_csv(start_str, end_str, csv_path)
        if success:
            log_event('INFO', 'fetch_and_save_order_feed_21_days', f'Файл сохранён: {csv_path}')
        else:
            log_event('ERROR', 'fetch_and_save_order_feed_21_days', 'Ошибка создания CSV')
    except Exception as e:
        log_event('ERROR', 'fetch_and_save_order_feed_21_days', str(e), {'traceback': traceback.format_exc()})