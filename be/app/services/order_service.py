import time
import threading
from datetime import datetime, timedelta
import requests
from utils.logger import log_event
from utils.token_manager import get_api_key
from models import db, Order


def save_orders_to_db_batch(orders_batch):
    """Безопасное сохранение пачки заказов в БД"""
    start_time = time.time()
    method_name = "save_orders_to_db_batch"
    
    try:
        if not orders_batch:
            return 0
        
        saved_count = 0
        updated_count = 0
        batch_size = len(orders_batch)
        
        log_event('INFO', method_name, f"Сохранение пачки из {batch_size} заказов")
        
        # Сохраняем пачками по 100 записей
        chunk_size = 100
        for i in range(0, batch_size, chunk_size):
            chunk = orders_batch[i:i + chunk_size]
            
            try:
                for order_data in chunk:
                    try:
                        # Проверяем обязательные поля
                        if 'odid' not in order_data or 'nmId' not in order_data:
                            continue
                        
                        # Преобразуем строки дат в datetime
                        try:
                            date_parsed = datetime.fromisoformat(order_data['date'].replace('Z', '+00:00'))
                        except:
                            date_parsed = datetime.strptime(order_data['date'], '%Y-%m-%dT%H:%M:%S')
                        
                        try:
                            last_change_date_parsed = datetime.fromisoformat(order_data['lastChangeDate'].replace('Z', '+00:00'))
                        except:
                            last_change_date_parsed = datetime.strptime(order_data['lastChangeDate'], '%Y-%m-%dT%H:%M:%S')
                        
                        # Ищем существующий заказ по odid
                        order = Order.query.filter_by(odid=order_data['odid']).first()
                        
                        if order:
                            # Обновляем существующий заказ
                            order.date = date_parsed
                            order.lastChangeDate = last_change_date_parsed
                            order.supplierArticle = order_data.get('supplierArticle', '')
                            order.techSize = order_data.get('techSize', '')
                            order.barcode = order_data.get('barcode', '')
                            order.quantity = order_data.get('quantity', 1)
                            order.totalPrice = order_data.get('totalPrice', 0)
                            order.discountPercent = order_data.get('discountPercent', 0)
                            order.warehouseName = order_data.get('warehouseName', '')
                            order.oblast = order_data.get('oblast', '')
                            order.incomeID = order_data.get('incomeID', 0)
                            order.nmId = order_data.get('nmId', 0)
                            order.subject = order_data.get('subject', '')
                            order.category = order_data.get('category', '')
                            order.brand = order_data.get('brand', '')
                            order.isCancel = order_data.get('isCancel', False)
                            order.gNumber = order_data.get('gNumber', '')
                            order.sticker = order_data.get('sticker', '')
                            order.srid = order_data.get('srid', '')
                            order.updated_at = datetime.utcnow()
                            updated_count += 1
                        else:
                            # Создаем новый заказ
                            order = Order(
                                date=date_parsed,
                                lastChangeDate=last_change_date_parsed,
                                supplierArticle=order_data.get('supplierArticle', ''),
                                techSize=order_data.get('techSize', ''),
                                barcode=order_data.get('barcode', ''),
                                quantity=order_data.get('quantity', 1),
                                totalPrice=order_data.get('totalPrice', 0),
                                discountPercent=order_data.get('discountPercent', 0),
                                warehouseName=order_data.get('warehouseName', ''),
                                oblast=order_data.get('oblast', ''),
                                incomeID=order_data.get('incomeID', 0),
                                odid=order_data['odid'],
                                nmId=order_data.get('nmId', 0),
                                subject=order_data.get('subject', ''),
                                category=order_data.get('category', ''),
                                brand=order_data.get('brand', ''),
                                isCancel=order_data.get('isCancel', False),
                                gNumber=order_data.get('gNumber', ''),
                                sticker=order_data.get('sticker', ''),
                                srid=order_data.get('srid', '')
                            )
                            db.session.add(order)
                            saved_count += 1
                            
                    except Exception as e:
                        log_event('ERROR', method_name, f"Ошибка при обработке заказа",
                                 {'odid': order_data.get('odid'), 'error': str(e)})
                        continue
                
                # Фиксируем каждую пачку отдельно
                db.session.commit()
                
            except Exception as e:
                db.session.rollback()
                log_event('ERROR', method_name, f"Ошибка при сохранении пачки",
                         {'chunk_index': i, 'error': str(e)})
                continue
        
        total_saved = saved_count + updated_count
        duration = (time.time() - start_time) * 1000
        
        log_event('INFO', method_name, 'Завершение сохранения пачки заказов',
                 {
                     'batch_size': batch_size,
                     'saved': saved_count,
                     'updated': updated_count,
                     'total_saved': total_saved,
                     'duration_ms': duration
                 },
                 duration_ms=duration,
                 records_processed=total_saved)
        
        return total_saved
        
    except Exception as e:
        db.session.rollback()
        error_duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при сохранении пачки заказов в БД',
                 {'error': str(e), 'traceback': traceback.format_exc()},
                 duration_ms=error_duration)
        return 0


def fetch_orders(date_from=None, date_to=None, first_request=False, order_ids=None, save_immediately=True):
    """Получение заказов с немедленным сохранением в БД"""
    start_time = time.time()
    method_name = "fetch_orders"
    
    try:
        log_event('INFO', method_name, 'Начало получения заказов с безопасным сохранением')
        
        api_key = get_api_key()
        if not api_key:
            log_event('ERROR', method_name, 'Отсутствует API токен')
            return 0
        
        # Определяем период запроса
        if first_request:
            # Первый запрос: заказы за последние 29 дней
            date_from = datetime.now() - timedelta(days=29)
            date_to = datetime.now()
        else:
            # Последующие запросы: заказы за последние 1 день (для обновления)
            date_from = datetime.now() - timedelta(days=1)
            date_to = datetime.now()
        
        # Преобразуем даты в Unix timestamp (секунды)
        date_from_ts = int(date_from.timestamp())
        date_to_ts = int(date_to.timestamp())
        
        url = "https://marketplace-api.wildberries.ru/api/v3/orders"
        headers = {
            'Authorization': api_key,
            'Content-Type': 'application/json'
        }
        
        total_saved = 0
        next_token = 0
        max_retries = 3
        limit = 1000
        
        while True:
            params = {
                'limit': limit,
                'next': next_token,
                'dateFrom': date_from_ts,
                'dateTo': date_to_ts
            }
            
            for attempt in range(max_retries):
                try:
                    response = requests.get(url, headers=headers, params=params, timeout=60)
                    
                    if response.status_code == 200:
                        data = response.json()
                        orders_batch = data.get('orders', [])
                        next_token = data.get('next')
                        
                        if orders_batch:
                            # Преобразуем и сразу сохраняем пачку заказов
                            transformed_orders = []
                            for order in orders_batch:
                                try:
                                    created_at = datetime.fromisoformat(order['createdAt'].replace('Z', '+00:00'))
                                    barcode = order['skus'][0] if order['skus'] else ''
                                    
                                    transformed_order = {
                                        'date': created_at.isoformat(),
                                        'lastChangeDate': created_at.isoformat(),
                                        'supplierArticle': order.get('article', ''),
                                        'techSize': '',
                                        'barcode': barcode,
                                        'quantity': 1,
                                        'totalPrice': order.get('convertedPrice', 0) / 100,
                                        'discountPercent': 0,
                                        'warehouseName': '',
                                        'oblast': '',
                                        'incomeID': 0,
                                        'odid': order['id'],
                                        'nmId': order['nmId'],
                                        'subject': '',
                                        'category': '',
                                        'brand': '',
                                        'isCancel': False,
                                        'gNumber': '',
                                        'sticker': '',
                                        'srid': order['rid']
                                    }
                                    transformed_orders.append(transformed_order)
                                except Exception as e:
                                    log_event('ERROR', method_name, f"Ошибка преобразования заказа",
                                             {'order_id': order.get('id'), 'error': str(e)})
                                    continue
                            
                            # НЕМЕДЛЕННОЕ СОХРАНЕНИЕ ПАЧКИ
                            if save_immediately and transformed_orders:
                                batch_saved = save_orders_to_db_batch(transformed_orders)
                                total_saved += batch_saved
                                log_event('INFO', method_name, f"Сохранено пачка заказов",
                                         {'batch_size': len(transformed_orders), 'saved': batch_saved, 
                                          'total_saved': total_saved, 'next_token': next_token})
                            else:
                                log_event('INFO', method_name, f"Получена пачка заказов",
                                         {'batch_size': len(transformed_orders), 'next_token': next_token})
                        
                        # Если next_token равен None или 0, прекращаем пагинацию
                        if not next_token:
                            log_event('INFO', method_name, "Все заказы получены")
                            break
                        
                        # Пауза между запросами
                        time.sleep(0.2)
                        break
                        
                    elif response.status_code == 429:
                        retry_after = int(response.headers.get('X-Ratelimit-Retry', 5))
                        log_event('WARNING', method_name, f"Превышен лимит запросов, ждем {retry_after}с")
                        time.sleep(retry_after)
                        continue
                        
                    else:
                        log_event('ERROR', method_name, f"Ошибка API",
                                 {'status_code': response.status_code, 'response_text': response.text[:500]})
                        if attempt < max_retries - 1:
                            time.sleep(2 ** attempt)
                            continue
                        break
                        
                except requests.exceptions.Timeout:
                    log_event('ERROR', method_name, f"Таймаут запроса (попытка {attempt + 1})")
                    if attempt < max_retries - 1:
                        time.sleep(2 ** attempt)
                        continue
                    break
                except Exception as e:
                    log_event('ERROR', method_name, f"Ошибка (попытка {attempt + 1})",
                             {'error': str(e)})
                    if attempt < max_retries - 1:
                        time.sleep(2 ** attempt)
                        continue
                    break
            
            if not next_token:
                break
        
        total_duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Завершение получения заказов',
                 {'total_saved': total_saved, 'duration_ms': total_duration},
                 duration_ms=total_duration, records_processed=total_saved)
        
        return total_saved
        
    except Exception as e:
        error_duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Критическая ошибка',
                 {'error': str(e)},
                 duration_ms=error_duration)
        return 0


def update_orders_job():
    """Задача для планировщика: обновление заказов (безопасная версия)"""
    try:
        # Используем first_request=False для запроса за последние 10 минут
        orders_count = fetch_orders(first_request=False)
        
        if orders_count > 0:
            log_event('INFO', 'update_orders_job', 'Автообновление заказов завершено',
                     {'orders_received': orders_count})
        else:
            log_event('INFO', 'update_orders_job', 'Нет новых заказов для обновления')
            
    except Exception as e:
        log_event('ERROR', 'update_orders_job', 'Ошибка при обновлении заказов по расписанию',
                 {'error': str(e)})