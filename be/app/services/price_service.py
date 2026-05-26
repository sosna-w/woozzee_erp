import time
import random
import requests
import traceback
from datetime import datetime
from threading import Thread, Event
from io import BytesIO
import pandas as pd
from models import db, ProductPrice, ProductCurrentPrice, CurrentPriceHistory, UnifiedProduct
from utils.logger import log_event
from utils.token_manager import get_api_key

_price_update_stop_event = Event()

def start_price_update_thread():
    """Запускает фоновый поток для постоянного обновления цен через карточный API"""
    thread = Thread(target=update_current_prices_loop, args=(_price_update_stop_event,), daemon=True)
    thread.start()
    log_event('INFO', 'startup', 'Поток обновления цен запущен')


def fetch_product_prices():
    """
    Получает цены всех товаров через API Wildberries
    и сохраняет в таблицу product_prices (накапливая историю).
    Ограничения: 10 запросов / 6 секунд, burst 5.
    """
    start_time = time.time()
    method_name = "fetch_product_prices"

    try:
        log_event('INFO', method_name, 'Начало получения цен товаров')

        api_key = get_api_key()
        if not api_key:
            log_event('ERROR', method_name, 'Отсутствует API токен')
            return

        url = "https://discounts-prices-api.wildberries.ru/api/v2/list/goods/filter"
        headers = {
            'Authorization': api_key,
            'Content-Type': 'application/json'
        }

        limit = 1000
        offset = 0
        all_goods = []
        request_counter = 0
        first_request_time = time.time()

        while True:
            request_counter += 1
            elapsed = time.time() - first_request_time
            if request_counter >= 10 and elapsed < 6:
                sleep_time = 6 - elapsed + 0.1
                time.sleep(sleep_time)
                request_counter = 0
                first_request_time = time.time()

            params = {'limit': limit, 'offset': offset}

            try:
                response = requests.get(url, headers=headers, params=params, timeout=30)

                if response.status_code == 200:
                    data = response.json()
                    if data.get('error'):
                        log_event('ERROR', method_name, 'Ошибка API', {
                            'errorText': data.get('errorText')
                        })
                        break

                    goods_list = data.get('data', {}).get('listGoods', [])
                    if not goods_list:
                        log_event('INFO', method_name, 'Все товары получены', {
                            'total_goods': len(all_goods)
                        })
                        break

                    all_goods.extend(goods_list)
                    offset += limit

                    log_event('DEBUG', method_name, f'Получена партия товаров', {
                        'batch_size': len(goods_list),
                        'total_so_far': len(all_goods),
                        'offset': offset
                    })

                elif response.status_code == 429:
                    retry_after = int(response.headers.get('Retry-After', 5))
                    log_event('WARNING', method_name, f'Превышен лимит (429), ждём {retry_after}с')
                    time.sleep(retry_after)
                    continue

                else:
                    log_event('ERROR', method_name, 'Ошибка API', {
                        'status_code': response.status_code,
                        'response': response.text[:500]
                    })
                    break

            except requests.RequestException as e:
                log_event('ERROR', method_name, 'Ошибка сети', {'error': str(e)})
                break

        if all_goods:
            log_event('INFO', method_name, f'Начало сохранения {len(all_goods)} записей')
            db_save_start = time.time()

            saved_count = 0
            for goods in all_goods:
                nm_id = goods.get('nmID')
                vendor_code = goods.get('vendorCode')
                sizes = goods.get('sizes', [])
                currency = goods.get('currencyIsoCode4217', 'RUB')
                editable_price = goods.get('editableSizePrice', False)
                is_bad = goods.get('isBadTurnover', False)
                discount = goods.get('discount')
                club_discount = goods.get('clubDiscount')

                for size in sizes:
                    price_obj = ProductPrice(
                        nm_id=nm_id,
                        vendor_code=vendor_code,
                        size_id=size.get('sizeID'),
                        price=size.get('price'),
                        discounted_price=size.get('discountedPrice'),
                        club_discounted_price=size.get('clubDiscountedPrice'),
                        discount=discount,
                        club_discount=club_discount,
                        currency=currency,
                        tech_size_name=size.get('techSizeName'),
                        editable_size_price=editable_price,
                        is_bad_turnover=is_bad
                    )
                    db.session.add(price_obj)
                    saved_count += 1

                    if saved_count % 5000 == 0:
                        db.session.commit()
                        log_event('DEBUG', method_name, f'Промежуточный коммит: {saved_count} записей')

            db.session.commit()
            db_save_duration = (time.time() - db_save_start) * 1000
            total_duration = (time.time() - start_time) * 1000
            log_event('INFO', method_name, 'Завершение получения и сохранения цен',
                     {
                         'total_records': saved_count,
                         'duration_ms': total_duration,
                         'db_save_ms': db_save_duration
                     },
                     duration_ms=total_duration,
                     records_processed=saved_count)

            print(f"✅ Добавлено снэпшотов цен: {saved_count} записей")
        else:
            log_event('WARNING', method_name, 'Не получено ни одной записи о ценах')

    except Exception as e:
        error_duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Критическая ошибка при получении цен',
                 {'error': str(e), 'traceback': traceback.format_exc()},
                 duration_ms=error_duration)
        raise


def update_current_prices_loop(stop_event: Event):
    """Бесконечный цикл обновления актуальных цен товаров через карточный API"""
    method_name = "update_current_prices_loop"
    consecutive_errors = 0
    log_event('INFO', method_name, 'Запуск фонового цикла обновления цен')

    CARD_API_URL = "https://card.wb.ru/cards/v4/detail"
    CARD_PARAMS = {
        "appType": 1,
        "curr": "rub",
        "dest": 123585531,
        "spp": 30,
        "hide_vflags": 4294967296,
        "ab_testing": False,
        "lang": "ru"
    }
    MIN_ITEMS_PER_REQUEST = 80
    MAX_ITEMS_PER_REQUEST = 100
    SLEEP_AFTER_ERROR_BASE = 90
    SLEEP_AFTER_ERROR_MAX = 180
    SLEEP_AFTER_SUCCESS_MIN = 1
    SLEEP_AFTER_SUCCESS_MAX = 10

    while not stop_event.is_set():
        with db.session.no_autoflush:  # важно: контекст приложения должен быть передан извне
            # Эта функция будет вызываться внутри app.app_context(), поэтому db доступен
            try:
                # 1. Получаем список всех nm_id из UnifiedProduct
                all_nm_ids = db.session.query(UnifiedProduct.nm_id).all()
                if not all_nm_ids:
                    log_event('WARNING', method_name, 'Нет товаров в UnifiedProduct, ожидание 60 сек')
                    stop_event.wait(60)
                    continue
                all_nm_ids = [row[0] for row in all_nm_ids]

                # 2. Выбираем товары, которые дольше всего не обновлялись
                subq = db.session.query(
                    ProductCurrentPrice.nm_id,
                    ProductCurrentPrice.last_updated
                ).subquery()
                query = db.session.query(UnifiedProduct.nm_id).outerjoin(
                    subq, UnifiedProduct.nm_id == subq.c.nm_id
                ).order_by(
                    db.nullsfirst(subq.c.last_updated.asc())
                )
                limit = random.randint(MIN_ITEMS_PER_REQUEST, MAX_ITEMS_PER_REQUEST)
                nm_ids_to_update = [row[0] for row in query.limit(limit).all()]

                if not nm_ids_to_update:
                    log_event('WARNING', method_name, 'Нет товаров для обновления, пауза 30 сек')
                    stop_event.wait(30)
                    continue

                # 3. Формируем параметры запроса
                params = CARD_PARAMS.copy()
                params['nm'] = nm_ids_to_update

                request_start = time.time()
                try:
                    response = requests.get(CARD_API_URL, params=params, timeout=30)
                    elapsed_ms = (time.time() - request_start) * 1000

                    if response.status_code == 200:
                        data = response.json()
                        products_data = data.get('products', [])
                        updated_count = 0
                        for prod in products_data:
                            nm_id = prod.get('id')
                            if not nm_id:
                                continue
                            sizes = prod.get('sizes', [])
                            price_value = None
                            if sizes and isinstance(sizes[0], dict):
                                price_info = sizes[0].get('price', {})
                                price_value = price_info.get('product')
                            if price_value is None:
                                price_value = sizes[0].get('price', {}).get('basic') if sizes else None
                            if price_value is not None:
                                price_rub = price_value / 100.0
                                existing = ProductCurrentPrice.query.filter_by(nm_id=nm_id).first()
                                if existing:
                                    existing.price = price_rub
                                    existing.last_updated = datetime.utcnow()
                                else:
                                    db.session.add(ProductCurrentPrice(
                                        nm_id=nm_id,
                                        price=price_rub
                                    ))
                                updated_count += 1
                        db.session.commit()
                        consecutive_errors = 0
                        sleep_time = random.uniform(SLEEP_AFTER_SUCCESS_MIN, SLEEP_AFTER_SUCCESS_MAX)
                        stop_event.wait(sleep_time)
                    else:
                        log_event('ERROR', method_name, f'Ошибка HTTP {response.status_code}',
                                  {'response_text': response.text[:500]})
                        consecutive_errors += 1
                        wait_time = min(SLEEP_AFTER_ERROR_BASE * (2 ** (consecutive_errors - 1)),
                                        SLEEP_AFTER_ERROR_MAX)
                        log_event('WARNING', method_name, f'Ошибка #{consecutive_errors}, пауза {wait_time} сек')
                        stop_event.wait(wait_time)

                except requests.exceptions.RequestException as e:
                    log_event('ERROR', method_name, f'Сетевая ошибка: {str(e)}')
                    consecutive_errors += 1
                    wait_time = min(SLEEP_AFTER_ERROR_BASE * (2 ** (consecutive_errors - 1)),
                                    SLEEP_AFTER_ERROR_MAX)
                    stop_event.wait(wait_time)
                except Exception as e:
                    log_event('ERROR', method_name, f'Необработанная ошибка: {str(e)}',
                              {'traceback': traceback.format_exc()})
                    consecutive_errors += 1
                    wait_time = min(SLEEP_AFTER_ERROR_BASE * (2 ** (consecutive_errors - 1)),
                                    SLEEP_AFTER_ERROR_MAX)
                    stop_event.wait(wait_time)

            except Exception as outer_e:
                log_event('ERROR', method_name, f'Критическая ошибка во внешнем цикле: {str(outer_e)}',
                          {'traceback': traceback.format_exc()})
                stop_event.wait(60)


def create_current_price_snapshot():
    """Создание снэпшота текущих цен для покупателя (каждый час)"""
    start_time = time.time()
    method_name = "create_current_price_snapshot"
    try:
        log_event('INFO', method_name, 'Начало создания часового снэпшота цен')

        current_prices = ProductCurrentPrice.query.all()
        if not current_prices:
            log_event('WARNING', method_name, 'Нет данных в ProductCurrentPrice')
            return

        created_count = 0
        error_count = 0

        for item in current_prices:
            try:
                history = CurrentPriceHistory(
                    nm_id=item.nm_id,
                    price=item.price
                )
                db.session.add(history)
                created_count += 1
                if created_count % 1000 == 0:
                    db.session.commit()
            except Exception as e:
                error_count += 1
                log_event('ERROR', method_name, f'Ошибка сохранения для nm_id={item.nm_id}',
                          {'error': str(e)})
                continue

        db.session.commit()
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Снэпшот цен завершён',
                  {'created': created_count, 'errors': error_count, 'duration_ms': duration},
                  duration_ms=duration, records_processed=created_count)
        print(f"✅ Создан часовой снэпшот цен: {created_count} записей, ошибок: {error_count}")
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Критическая ошибка при создании снэпшота цен',
                  {'error': str(e), 'traceback': traceback.format_exc()},
                  duration_ms=duration)
        raise