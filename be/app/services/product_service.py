import time
import json
import requests
from datetime import datetime
from sqlalchemy import text, func
from utils.logger import log_event
from utils.rate_limiter import RateLimiter, safe_json_response
from utils.token_manager import get_api_key
from models import db, Product, Stock, Warehouse, FBSStock, UnifiedProduct, WarehouseConfig

limiter = RateLimiter()


def fetch_all_products():
    start_time = time.time()
    method_name = "fetch_all_products"
    
    # АВТОМАТИЧЕСКОЕ ДОБАВЛЕНИЕ СТОЛБЦА BARCODE ПРИ НЕОБХОДИМОСТИ
    try:
        inspector = db.inspect(db.engine)
        columns = [col['name'] for col in inspector.get_columns('product')]
        if 'barcode' not in columns:
            log_event('INFO', method_name, 'Добавляем столбец barcode в таблицу product')
            db.session.execute(text('ALTER TABLE product ADD COLUMN barcode VARCHAR(30)'))
            db.session.commit()
            log_event('INFO', method_name, 'Столбец barcode успешно добавлен в таблицу product')
        else:
            log_event('DEBUG', method_name, 'Столбец barcode уже существует в таблице product')
    except Exception as e:
        log_event('WARNING', method_name, f'Не удалось добавить столбец barcode: {e}')
        # Продолжаем работу, так как это не критическая ошибка
    
    try:
        log_event('INFO', method_name, 'Начало получения товаров')
        
        api_key = get_api_key()
        if not api_key:
            log_event('ERROR', method_name, 'Отсутствует API токен')
            return
        
        url = "https://content-api.wildberries.ru/content/v2/get/cards/list"
        headers = {'Authorization': api_key}
        cursor = None
        all_products = []
        total_batches = 0
        max_retries = 3
        
        # Получаем все существующие nmID из базы для сравнения
        existing_nm_ids = set()
        try:
            existing_products = Product.query.with_entities(Product.nmID).all()
            existing_nm_ids = {product[0] for product in existing_products}
            log_event('INFO', method_name, f'Найдено {len(existing_nm_ids)} товаров в базе данных')
        except Exception as e:
            log_event('ERROR', method_name, 'Ошибка при получении существующих товаров из базы', {'error': str(e)})
        
        while True:
            batch_start = time.time()
            total_batches += 1
            
            payload = {
                "settings": {
                    "cursor": {
                        "limit": 100
                    },
                    "filter": {
                        "withPhoto": -1
                    }
                }
            }
            
            if cursor and 'updatedAt' in cursor and 'nmID' in cursor:
                payload["settings"]["cursor"]["updatedAt"] = cursor['updatedAt']
                payload["settings"]["cursor"]["nmID"] = cursor['nmID']
            
            log_event('DEBUG', method_name, f"Подготовка запроса batch #{total_batches}",
                     {'cursor': cursor, 'has_cursor': cursor is not None})
            
            bucket = limiter.get_bucket(url)
            limiter.wait_for_token(bucket)
            
            for attempt in range(max_retries):
                try:
                    request_start = time.time()
                    response = requests.post(url, json=payload, headers=headers, timeout=30)
                    request_duration = (time.time() - request_start) * 1000
                    
                    limiter.handle_response(bucket, response)
                    
                    log_event('DEBUG', method_name, f"Получен ответ batch #{total_batches} (попытка {attempt + 1})",
                             {'status_code': response.status_code, 'duration_ms': request_duration},
                             duration_ms=request_duration, request_url=url, response_status=response.status_code)
                    
                    if response.status_code == 200:
                        data = safe_json_response(response, method_name, url)
                        if data is None:
                            if attempt < max_retries - 1:
                                wait_time = 2 ** attempt
                                log_event('INFO', method_name, f"Повтор запроса через {wait_time}с")
                                time.sleep(wait_time)
                                continue
                            else:
                                log_event('ERROR', method_name, "Не удалось получить валидный JSON после всех попыток")
                                return
                        
                        batch_products = data.get('cards', [])
                        if not isinstance(batch_products, list):
                            log_event('ERROR', method_name, "Некорректный формат cards в ответе",
                                     {'cards_type': type(batch_products)})
                            break
                            
                        all_products.extend(batch_products)
                        
                        log_event('INFO', method_name, f"Обработан batch #{total_batches}",
                                 {'products_in_batch': len(batch_products), 'total_products': len(all_products)},
                                 records_processed=len(batch_products))
                        
                        if data.get('cursor') and isinstance(data.get('cursor'), dict) and batch_products:
                            cursor = data['cursor']
                            log_event('DEBUG', method_name, f"Получен курсор для следующего batch",
                                     {'cursor': cursor})
                        else:
                            log_event('INFO', method_name, "Все товары получены, курсор пуст")
                            break
                        break
                        
                    elif response.status_code == 429:
                        retry_after = int(response.headers.get('Retry-After', 60))
                        log_event('WARNING', method_name, f"Превышен лимит запросов, ждем {retry_after}с")
                        time.sleep(retry_after)
                        continue
                        
                    else:
                        log_event('ERROR', method_name, f"Ошибка API при получении товаров",
                                 {'status_code': response.status_code, 'response_text': response.text[:500]},
                                 request_url=url, response_status=response.status_code)
                        if response.status_code >= 500 and attempt < max_retries - 1:
                            wait_time = 2 ** attempt
                            log_event('INFO', method_name, f"Повтор при ошибке сервера через {wait_time}с")
                            time.sleep(wait_time)
                            continue
                        return
                        
                except requests.exceptions.Timeout:
                    log_event('ERROR', method_name, f"Таймаут запроса (попытка {attempt + 1})")
                    if attempt < max_retries - 1:
                        time.sleep(2 ** attempt)
                        continue
                    return
                except requests.exceptions.RequestException as e:
                    log_event('ERROR', method_name, f"Ошибка сети: {e} (попытка {attempt + 1})")
                    if attempt < max_retries - 1:
                        time.sleep(2 ** attempt)
                        continue
                    return
            
            batch_duration = (time.time() - batch_start) * 1000
            log_event('DEBUG', method_name, f"Batch #{total_batches} завершен",
                     {'duration_ms': batch_duration}, duration_ms=batch_duration)
            
            if total_batches > 1000:
                log_event('ERROR', method_name, "Превышено максимальное количество batch-запросов")
                break
            
            if not cursor or not batch_products:
                break
        
        log_event('INFO', method_name, f"Начало сохранения {len(all_products)} товаров в БД")
        db_save_start = time.time()
        products_created = 0
        products_updated = 0
        
        # Собираем nmID из полученных товаров для синхронизации
        received_nm_ids = set()
        
        for i, product_data in enumerate(all_products):
            try:
                if 'nmID' not in product_data:
                    log_event('WARNING', method_name, "Пропуск товара без nmID",
                             {'product_data_keys': list(product_data.keys())})
                    continue
                
                nm_id = product_data['nmID']
                received_nm_ids.add(nm_id)
                product = Product.query.filter_by(nmID=nm_id).first()
                is_new = not product
                
                if is_new:
                    product = Product(nmID=nm_id)
                    products_created += 1
                else:
                    products_updated += 1
                
                product.imtID = product_data.get('imtID')
                product.nmUUID = product_data.get('nmUUID')
                product.subjectID = product_data.get('subjectID')
                product.subjectName = product_data.get('subjectName')
                product.vendorCode = product_data.get('vendorCode')
                product.brand = product_data.get('brand')
                product.title = product_data.get('title')
                product.description = product_data.get('description')
                product.needKiz = product_data.get('needKiz', False)
                
                photos_data = product_data.get('photos', [])
                if isinstance(photos_data, list):
                    photo_urls = []
                    for photo in photos_data:
                        if isinstance(photo, dict):
                            photo_info = {}
                            for key in ['big', 'c246x328', 'c516x688', 'square', 'tm']:
                                if key in photo:
                                    photo_info[key] = photo[key]
                            photo_urls.append(photo_info)
                    product.photos = json.dumps(photo_urls, ensure_ascii=False) if photo_urls else '[]'
                else:
                    product.photos = '[]'
                
                product.video = product_data.get('video')
                
                wholesale = product_data.get('wholesale', {})
                if isinstance(wholesale, dict):
                    product.wholesale_enabled = wholesale.get('enabled', False)
                    product.wholesale_quantum = wholesale.get('quantum')
                else:
                    product.wholesale_enabled = False
                    product.wholesale_quantum = None
                
                dimensions = product_data.get('dimensions', {})
                if isinstance(dimensions, dict):
                    product.dimensions_length = dimensions.get('length')
                    product.dimensions_width = dimensions.get('width')
                    product.dimensions_height = dimensions.get('height')
                    product.dimensions_weightBrutto = dimensions.get('weightBrutto')
                    product.dimensions_isValid = dimensions.get('isValid')
                else:
                    product.dimensions_length = None
                    product.dimensions_width = None
                    product.dimensions_height = None
                    product.dimensions_weightBrutto = None
                    product.dimensions_isValid = None
                
                characteristics = product_data.get('characteristics', [])
                if isinstance(characteristics, list):
                    product.characteristics = json.dumps(characteristics, ensure_ascii=False)
                else:
                    product.characteristics = '[]'
                
                # ИЗВЛЕЧЕНИЕ БАРКОДА ИЗ SIZES.SKUS
                barcodes = []
                sizes_data = product_data.get('sizes', [])
                if isinstance(sizes_data, list):
                    processed_sizes = []
                    for size in sizes_data:
                        if isinstance(size, dict):
                            size_info = {
                                'chrtID': size.get('chrtID'),
                                'techSize': size.get('techSize'),
                                'wbSize': size.get('wbSize'),
                                'skus': size.get('skus', [])
                            }
                            processed_sizes.append(size_info)
                            
                            # Извлекаем баркоды из skus
                            skus = size.get('skus', [])
                            if isinstance(skus, list):
                                barcodes.extend(skus)
                    
                    product.sizes = json.dumps(processed_sizes, ensure_ascii=False) if processed_sizes else '[]'
                    
                    # Сохраняем первый баркод как основной
                    if barcodes:
                        product.barcode = barcodes[0]
                    else:
                        product.barcode = None
                        log_event('WARNING', method_name, f"Баркоды не найдены для товара {nm_id}")
                else:
                    product.sizes = '[]'
                    product.barcode = None
                
                tags_data = product_data.get('tags', [])
                if isinstance(tags_data, list):
                    processed_tags = []
                    for tag in tags_data:
                        if isinstance(tag, dict):
                            tag_info = {
                                'id': tag.get('id'),
                                'name': tag.get('name'),
                                'color': tag.get('color')
                            }
                            processed_tags.append(tag_info)
                    product.tags = json.dumps(processed_tags, ensure_ascii=False) if processed_tags else '[]'
                else:
                    product.tags = '[]'
                
                created_at = product_data.get('createdAt')
                if created_at:
                    try:
                        product.created_at = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                    except (ValueError, AttributeError) as e:
                        log_event('WARNING', method_name, f"Неверный формат даты создания: {created_at}",
                                 {'error': str(e)})
                        product.created_at = None
                
                updated_at = product_data.get('updatedAt')
                if updated_at:
                    try:
                        product.updated_at = datetime.fromisoformat(updated_at.replace('Z', '+00:00'))
                    except (ValueError, AttributeError) as e:
                        log_event('WARNING', method_name, f"Неверный формат даты обновления: {updated_at}",
                                 {'error': str(e)})
                        product.updated_at = None
                
                db.session.add(product)
                
                if (i + 1) % 50 == 0:
                    try:
                        db.session.commit()
                        log_event('DEBUG', method_name, f"Промежуточный коммит товаров",
                                 {'processed': i + 1, 'total': len(all_products)})
                    except Exception as e:
                        db.session.rollback()
                        log_event('ERROR', method_name, f"Ошибка при промежуточном коммите",
                                 {'processed': i + 1, 'error': str(e)})
                    
            except Exception as e:
                log_event('ERROR', method_name, f"Ошибка при обработке товара",
                         {'nm_id': product_data.get('nmID'), 'error': str(e), 'traceback': traceback.format_exc()},
                         nm_id=product_data.get('nmID'))
                continue
        
        # СИНХРОНИЗАЦИЯ: УДАЛЕНИЕ ТОВАРОВ, КОТОРЫХ НЕТ В АКТУАЛЬНОМ СПИСКЕ
        products_deleted = 0
        try:
            products_to_delete = Product.query.filter(~Product.nmID.in_(received_nm_ids)).all()
            if products_to_delete:
                products_deleted = len(products_to_delete)
                log_event('INFO', method_name, f'Найдено товаров для удаления: {products_deleted}',
                         {'nm_ids_to_delete': [p.nmID for p in products_to_delete]})
                for product_to_delete in products_to_delete:
                    db.session.delete(product_to_delete)
                log_event('INFO', method_name, f'Удалено товаров: {products_deleted}')
            else:
                log_event('INFO', method_name, 'Нет товаров для удаления - база синхронизирована')
        except Exception as e:
            log_event('ERROR', method_name, 'Ошибка при синхронизации товаров',
                     {'error': str(e), 'traceback': traceback.format_exc()})
        
        try:
            db.session.commit()
        except Exception as e:
            db.session.rollback()
            log_event('ERROR', method_name, "Ошибка при финальном коммите",
                     {'error': str(e)})
            raise
        
        db_save_duration = (time.time() - db_save_start) * 1000
        total_duration = (time.time() - start_time) * 1000
        performance_info = {
            'total_products': len(all_products),
            'products_created': products_created,
            'products_updated': products_updated,
            'products_deleted': products_deleted,
            'total_batches': total_batches,
            'total_duration_ms': total_duration,
            'db_save_duration_ms': db_save_duration
        }
        log_event('INFO', method_name, "Завершение получения товаров",
                 performance_info, duration_ms=total_duration, records_processed=len(all_products))
        print(f"Обновлено {len(all_products)} товаров, создано: {products_created}, обновлено: {products_updated}, удалено: {products_deleted}")
        
    except Exception as e:
        error_duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, "Критическая ошибка при получении товаров",
                 {'error': str(e), 'traceback': traceback.format_exc()}, duration_ms=error_duration)
        raise


def fetch_all_stocks():
    start_time = time.time()
    method_name = "fetch_all_stocks"
    
    try:
        log_event('INFO', method_name, 'Начало получения остатков')
        api_key = get_api_key()
        if not api_key:
            log_event('ERROR', method_name, 'Отсутствует API токен')
            return
        
        url = "https://statistics-api.wildberries.ru/api/v1/supplier/stocks"
        headers = {'Authorization': api_key}
        date_from = "2019-06-20"
        all_stocks = []
        total_batches = 0
        max_retries = 3
        
        log_event('DEBUG', method_name, 'Конфигурация запроса', 
                 {'url': url, 'date_from': date_from, 'max_retries': max_retries})
        
        while True:
            batch_start = time.time()
            total_batches += 1
            params = {'dateFrom': date_from}
            log_event('DEBUG', method_name, f'Подготовка batch #{total_batches}',
                     {'date_from': date_from, 'params': params})
            
            bucket = limiter.get_bucket(url)
            limiter.wait_for_token(bucket)
            
            for attempt in range(max_retries):
                try:
                    request_start = time.time()
                    log_event('DEBUG', method_name, f'Отправка запроса batch #{total_batches} (попытка {attempt + 1})')
                    response = requests.get(url, headers=headers, params=params, timeout=30)
                    request_duration = (time.time() - request_start) * 1000
                    limiter.handle_response(bucket, response)
                    
                    log_event('DEBUG', method_name, f'Получен ответ batch #{total_batches} (попытка {attempt + 1})',
                             {'status_code': response.status_code, 'duration_ms': request_duration, 'content_length': len(response.text)},
                             duration_ms=request_duration, request_url=url, response_status=response.status_code)
                    
                    if response.status_code == 200:
                        stocks_batch = safe_json_response(response, method_name, url)
                        if stocks_batch is None:
                            log_event('WARNING', method_name, f'Невалидный JSON в batch #{total_batches}')
                            if attempt < max_retries - 1:
                                wait_time = 2 ** attempt
                                log_event('INFO', method_name, f'Повтор запроса через {wait_time}с')
                                time.sleep(wait_time)
                                continue
                            else:
                                log_event('ERROR', method_name, "Не удалось получить валидный JSON после всех попыток")
                                return
                        
                        if not stocks_batch:
                            log_event('INFO', method_name, "Все остатки получены, пустой ответ - завершение")
                            break
                            
                        all_stocks.extend(stocks_batch)
                        last_date = stocks_batch[-1]['lastChangeDate']
                        date_from = last_date.replace('T', ' ').split('.')[0]
                        
                        log_event('INFO', method_name, f'Обработан batch #{total_batches}',
                                 {'stocks_in_batch': len(stocks_batch), 'total_stocks': len(all_stocks),
                                  'last_date': last_date, 'next_date_from': date_from},
                                 records_processed=len(stocks_batch))
                        break
                        
                    elif response.status_code == 429:
                        retry_after = int(response.headers.get('X-Ratelimit-Retry', 60))
                        log_event('WARNING', method_name, f'Превышен лимит запросов, ждем {retry_after}с')
                        time.sleep(retry_after)
                        continue
                        
                    else:
                        log_event('ERROR', method_name, f'Ошибка API при получении остатков',
                                 {'status_code': response.status_code, 'response_text': response.text[:500]},
                                 request_url=url, response_status=response.status_code)
                        if response.status_code >= 500 and attempt < max_retries - 1:
                            wait_time = 2 ** attempt
                            log_event('INFO', method_name, f'Повтор при ошибке сервера через {wait_time}с')
                            time.sleep(wait_time)
                            continue
                        return
                        
                except requests.exceptions.Timeout:
                    log_event('ERROR', method_name, f'Таймаут запроса (попытка {attempt + 1})')
                    if attempt < max_retries - 1:
                        time.sleep(2 ** attempt)
                        continue
                    return
                except requests.exceptions.RequestException as e:
                    log_event('ERROR', method_name, f'Ошибка сети: {e} (попытка {attempt + 1})')
                    if attempt < max_retries - 1:
                        time.sleep(2 ** attempt)
                        continue
                    return
            
            batch_duration = (time.time() - batch_start) * 1000
            log_event('DEBUG', method_name, f'Batch #{total_batches} завершен',
                     {'duration_ms': batch_duration, 'total_stocks_so_far': len(all_stocks)}, 
                     duration_ms=batch_duration)
            
            if total_batches > 1000:
                log_event('ERROR', method_name, "Превышено максимальное количество batch-запросов")
                break
            
            if not stocks_batch:
                log_event('INFO', method_name, "Все данные получены, завершение цикла")
                break
        
        log_event('INFO', method_name, 'Удаление старых данных остатков')
        delete_start = time.time()
        try:
            deleted_count = db.session.query(Stock).delete()
            db.session.commit()
            delete_duration = (time.time() - delete_start) * 1000
            log_event('INFO', method_name, f'Удалено старых записей: {deleted_count}',
                     {'deleted_count': deleted_count, 'duration_ms': delete_duration})
        except Exception as e:
            db.session.rollback()
            delete_duration = (time.time() - delete_start) * 1000
            log_event('ERROR', method_name, 'Ошибка при удалении старых данных остатков',
                     {'error': str(e)}, duration_ms=delete_duration)
            return
        
        log_event('INFO', method_name, f'Начало сохранения: {len(all_stocks)} остатков в БД')
        db_save_start = time.time()
        
        success_count = 0
        error_count = 0
        validation_errors = 0
        
        try:
            db.session.execute(text('SELECT 1'))
            log_event('DEBUG', method_name, 'Соединение с БД установлено')
        except Exception as e:
            log_event('ERROR', method_name, 'Ошибка соединения с БД', {'error': str(e)})
            return
        
        batch_size = 500
        transaction_success = False
        
        try:
            for i, stock_data in enumerate(all_stocks):
                try:
                    if not isinstance(stock_data, dict):
                        log_event('WARNING', method_name, f'Неверный формат данных на позиции {i}',
                                 {'type': type(stock_data), 'data': str(stock_data)[:200]})
                        validation_errors += 1
                        continue
                    
                    required_fields = ['nmId', 'lastChangeDate', 'warehouseName']
                    missing_fields = [field for field in required_fields if field not in stock_data]
                    if missing_fields:
                        log_event('WARNING', method_name, f'Отсутствуют обязательные поля на позиции {i}',
                                 {'missing_fields': missing_fields, 'nm_id': stock_data.get('nmId')})
                        validation_errors += 1
                        continue
                    
                    try:
                        last_change_date = datetime.fromisoformat(stock_data['lastChangeDate'].replace('Z', '+00:00'))
                    except (ValueError, AttributeError) as e:
                        log_event('WARNING', method_name, f'Ошибка преобразования даты на позиции {i}',
                                 {'nm_id': stock_data.get('nmId'), 'date_string': stock_data.get('lastChangeDate'), 'error': str(e)})
                        validation_errors += 1
                        continue
                    
                    stock = Stock(
                        lastChangeDate=last_change_date,
                        warehouseName=stock_data['warehouseName'],
                        supplierArticle=stock_data.get('supplierArticle', ''),
                        nmId=stock_data['nmId'],
                        barcode=stock_data.get('barcode', ''),
                        quantity=stock_data.get('quantity', 0),
                        inWayToClient=stock_data.get('inWayToClient', 0),
                        inWayFromClient=stock_data.get('inWayFromClient', 0),
                        quantityFull=stock_data.get('quantityFull', 0),
                        category=stock_data.get('category', ''),
                        subject=stock_data.get('subject', ''),
                        brand=stock_data.get('brand', ''),
                        techSize=stock_data.get('techSize', ''),
                        Price=stock_data.get('Price', 0.0),
                        Discount=stock_data.get('Discount', 0.0),
                        isSupply=stock_data.get('isSupply', False),
                        isRealization=stock_data.get('isRealization', False),
                        SCCode=stock_data.get('SCCode', '')
                    )
                    db.session.add(stock)
                    success_count += 1
                    
                    if (i + 1) % batch_size == 0:
                        progress_percent = (i + 1) / len(all_stocks) * 100
                        log_event('INFO', method_name, f'Прогресс сохранения: {i + 1}/{len(all_stocks)} ({progress_percent:.1f}%)',
                                 {'success_count': success_count, 'error_count': error_count, 'validation_errors': validation_errors})
                        try:
                            db.session.commit()
                            log_event('DEBUG', method_name, f'Промежуточный коммит после {i + 1} записей')
                        except Exception as e:
                            db.session.rollback()
                            log_event('ERROR', method_name, f'Ошибка промежуточного коммита на записи {i + 1}',
                                     {'error': str(e), 'traceback': traceback.format_exc()})
                            error_count += (len(all_stocks) - i)
                            raise
                    
                except Exception as e:
                    error_count += 1
                    log_event('ERROR', method_name, f'Ошибка при обработке остатка на позиции {i}',
                             {'nm_id': stock_data.get('nmId'), 'error': str(e), 'data_sample': {k: v for k, v in list(stock_data.items())[:3]}},
                             nm_id=stock_data.get('nmId'))
            
            log_event('INFO', method_name, 'Попытка финального коммита в БД',
                     {'success_count': success_count, 'error_count': error_count, 'validation_errors': validation_errors})
            db.session.commit()
            transaction_success = True
            log_event('INFO', method_name, 'Финальный коммит успешно выполнен')
            
        except Exception as e:
            db.session.rollback()
            log_event('ERROR', method_name, 'Ошибка транзакции - выполнен откат',
                     {'error': str(e), 'traceback': traceback.format_exc()})
            transaction_success = False
        
        db_save_duration = (time.time() - db_save_start) * 1000
        total_duration = (time.time() - start_time) * 1000
        performance_info = {
            'total_received': len(all_stocks),
            'successfully_saved': success_count,
            'errors': error_count,
            'validation_errors': validation_errors,
            'transaction_success': transaction_success,
            'success_rate': (success_count / len(all_stocks)) * 100 if all_stocks else 0,
            'total_batches': total_batches,
            'total_duration_ms': total_duration,
            'db_save_duration_ms': db_save_duration,
            'delete_duration_ms': delete_duration,
            'avg_batch_duration_ms': total_duration / total_batches if total_batches > 0 else 0,
            'stocks_per_second': len(all_stocks) / (total_duration / 1000) if total_duration > 0 else 0
        }
        log_event('INFO', method_name, "Завершение получения остатков",
                 performance_info, duration_ms=total_duration, records_processed=success_count)
        
        try:
            actual_count = Stock.query.count()
            log_event('INFO', method_name, 'Проверка состояния БД после операции',
                     {'expected_count': success_count, 'actual_count_in_db': actual_count, 'discrepancy': success_count - actual_count})
        except Exception as e:
            log_event('ERROR', method_name, 'Ошибка при проверке состояния БД',
                     {'error': str(e)})
        
        print(f"Статистика остатков: получено {len(all_stocks)}, сохранено {success_count}, ошибок {error_count}, транзакция: {'УСПЕХ' if transaction_success else 'СБОЙ'}")
        
    except Exception as e:
        error_duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, "Критическая ошибка при получении остатков",
                 {'error': str(e), 'traceback': traceback.format_exc()}, duration_ms=error_duration)
        raise


def fetch_warehouses():
    start_time = time.time()
    method_name = "fetch_warehouses"
    
    try:
        log_event('INFO', method_name, 'Начало получения списка складов')
        api_key = get_api_key()
        if not api_key:
            log_event('ERROR', method_name, 'Отсутствует API токен')
            return
        
        url = "https://marketplace-api.wildberries.ru/api/v3/warehouses"
        headers = {'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'}
        bucket = limiter.get_bucket(url)
        limiter.wait_for_token(bucket)
        max_retries = 3
        
        for attempt in range(max_retries):
            try:
                request_start = time.time()
                response = requests.get(url, headers=headers, timeout=30)
                request_duration = (time.time() - request_start) * 1000
                limiter.handle_response(bucket, response)
                log_event('DEBUG', method_name, f"Получен ответ (попытка {attempt + 1})",
                         {'status_code': response.status_code, 'duration_ms': request_duration},
                         duration_ms=request_duration, request_url=url, response_status=response.status_code)
                
                if response.status_code == 200:
                    warehouses_data = safe_json_response(response, method_name, url)
                    if warehouses_data is None:
                        if attempt < max_retries - 1:
                            wait_time = 2 ** attempt
                            log_event('INFO', method_name, f"Повтор запроса через {wait_time}с")
                            time.sleep(wait_time)
                            continue
                        else:
                            log_event('ERROR', method_name, "Не удалось получить валидный JSON после всех попыток")
                            return
                    
                    log_event('INFO', method_name, f"Начало сохранения {len(warehouses_data)} складов в БД")
                    db_save_start = time.time()
                    saved_count = 0
                    updated_count = 0
                    
                    for warehouse_data in warehouses_data:
                        try:
                            warehouse = Warehouse.query.filter_by(warehouse_id=warehouse_data['id']).first()
                            if warehouse:
                                warehouse.name = warehouse_data['name']
                                warehouse.office_id = warehouse_data['officeId']
                                warehouse.cargo_type = warehouse_data.get('cargoType')
                                warehouse.delivery_type = warehouse_data.get('deliveryType')
                                warehouse.is_deleting = warehouse_data.get('isDeleting', False)
                                warehouse.is_processing = warehouse_data.get('isProcessing', False)
                                warehouse.updated_at = datetime.utcnow()
                                updated_count += 1
                            else:
                                warehouse = Warehouse(
                                    name=warehouse_data['name'],
                                    office_id=warehouse_data['officeId'],
                                    warehouse_id=warehouse_data['id'],
                                    cargo_type=warehouse_data.get('cargoType'),
                                    delivery_type=warehouse_data.get('deliveryType'),
                                    is_deleting=warehouse_data.get('isDeleting', False),
                                    is_processing=warehouse_data.get('isProcessing', False)
                                )
                                db.session.add(warehouse)
                                saved_count += 1
                        except Exception as e:
                            log_event('ERROR', method_name, f"Ошибка при обработке склада {warehouse_data.get('id')}",
                                     {'warehouse_id': warehouse_data.get('id'), 'error': str(e)})
                            continue
                    
                    db.session.commit()
                    db_save_duration = (time.time() - db_save_start) * 1000
                    total_duration = (time.time() - start_time) * 1000
                    performance_info = {
                        'total_warehouses': len(warehouses_data),
                        'saved': saved_count,
                        'updated': updated_count,
                        'total_duration_ms': total_duration,
                        'db_save_duration_ms': db_save_duration
                    }
                    log_event('INFO', method_name, "Завершение получения складов", performance_info,
                             duration_ms=total_duration, records_processed=len(warehouses_data))
                    print(f"Обновлено складов: сохранено {saved_count}, обновлено {updated_count}")
                    break
                    
                elif response.status_code == 429:
                    retry_after = int(response.headers.get('Retry-After', 60))
                    log_event('WARNING', method_name, f"Превышен лимит запросов, ждем {retry_after}с")
                    time.sleep(retry_after)
                    continue
                    
                else:
                    log_event('ERROR', method_name, f"Ошибка API при получении складов",
                             {'status_code': response.status_code, 'response_text': response.text[:500]},
                             request_url=url, response_status=response.status_code)
                    if response.status_code >= 500 and attempt < max_retries - 1:
                        wait_time = 2 ** attempt
                        log_event('INFO', method_name, f"Повтор при ошибке сервера через {wait_time}с")
                        time.sleep(wait_time)
                        continue
                    return
                    
            except requests.exceptions.Timeout:
                log_event('ERROR', method_name, f"Таймаут запроса (попытка {attempt + 1})")
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)
                    continue
                return
            except requests.exceptions.RequestException as e:
                log_event('ERROR', method_name, f"Ошибка сети: {e} (попытка {attempt + 1})")
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)
                    continue
                return
        
    except Exception as e:
        error_duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, "Критическая ошибка при получении складов",
                 {'error': str(e), 'traceback': traceback.format_exc()}, duration_ms=error_duration)
        raise


def fetch_fbs_stocks():
    start_time = time.time()
    method_name = "fetch_fbs_stocks"
    
    try:
        log_event('INFO', method_name, 'Начало получения остатков FBS')
        api_key = get_api_key()
        if not api_key:
            log_event('ERROR', method_name, 'Отсутствует API токен')
            return
        
        warehouse_config = WarehouseConfig.query.first()
        if not warehouse_config:
            log_event('ERROR', method_name, 'Конфигурация складов не найдена')
            return
        
        individual_configs = json.loads(warehouse_config.individual_config) if warehouse_config.individual_config else {}
        active_warehouse = None
        warehouses = Warehouse.query.all()
        for warehouse in warehouses:
            warehouse_key = str(warehouse.warehouse_id)
            config = individual_configs.get(warehouse_key, {})
            if config.get('is_activate', True):
                active_warehouse = warehouse
                break
        
        if not active_warehouse:
            log_event('WARNING', method_name, 'Нет активированных складов')
            return
        
        unified_products = UnifiedProduct.query.filter(UnifiedProduct.barcode.isnot(None)).all()
        barcodes = [product.barcode for product in unified_products if product.barcode]
        if not barcodes:
            log_event('WARNING', method_name, 'Нет товаров с баркодами для запроса FBS')
            return
        
        batch_size = 1000
        all_fbs_stocks = []
        for i in range(0, len(barcodes), batch_size):
            batch_barcodes = barcodes[i:i + batch_size]
            url = f"https://marketplace-api.wildberries.ru/api/v3/stocks/{active_warehouse.warehouse_id}"
            headers = {'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'}
            payload = {"skus": batch_barcodes}
            bucket = limiter.get_bucket(url)
            limiter.wait_for_token(bucket)
            
            try:
                response = requests.post(url, json=payload, headers=headers, timeout=30)
                if response.status_code == 200:
                    stocks_data = response.json().get('stocks', [])
                    all_fbs_stocks.extend(stocks_data)
                    log_event('INFO', method_name, f'Получен батч FBS остатков',
                             {'batch': i // batch_size + 1, 'stocks_count': len(stocks_data)})
                else:
                    log_event('ERROR', method_name, f'Ошибка API при получении FBS остатков',
                             {'status_code': response.status_code, 'warehouse_id': active_warehouse.warehouse_id})
            except Exception as e:
                log_event('ERROR', method_name, f'Ошибка при запросе FBS остатков',
                         {'warehouse_id': active_warehouse.warehouse_id, 'error': str(e)})
        
        saved_count = 0
        for stock_data in all_fbs_stocks:
            try:
                product = UnifiedProduct.query.filter_by(barcode=stock_data['sku']).first()
                if not product:
                    continue
                fbs_stock = FBSStock.query.filter_by(
                    nm_id=product.nm_id,
                    warehouse_id=active_warehouse.warehouse_id
                ).first()
                if fbs_stock:
                    fbs_stock.quantity = stock_data['amount']
                    fbs_stock.updated_at = datetime.utcnow()
                else:
                    fbs_stock = FBSStock(
                        nm_id=product.nm_id,
                        warehouse_id=active_warehouse.warehouse_id,
                        barcode=stock_data['sku'],
                        quantity=stock_data['amount']
                    )
                    db.session.add(fbs_stock)
                saved_count += 1
            except Exception as e:
                log_event('ERROR', method_name, f'Ошибка сохранения FBS остатка',
                         {'barcode': stock_data.get('sku'), 'error': str(e)})
                continue
        
        db.session.commit()
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Завершение получения остатков FBS',
                 {'warehouse_id': active_warehouse.warehouse_id, 'total_stocks': len(all_fbs_stocks),
                  'saved_count': saved_count, 'duration_ms': duration},
                 duration_ms=duration, records_processed=len(all_fbs_stocks))
        print(f"Обновлено FBS остатков: {saved_count}")
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Критическая ошибка при получении FBS остатков',
                 {'error': str(e), 'traceback': traceback.format_exc()}, duration_ms=duration)
        raise


def _update_stocks_via_api(api_key, warehouse_id, products, method_name):
    updated_count = 0
    batch_size = 1000
    headers = {'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'}
    
    for i in range(0, len(products), batch_size):
        batch = products[i:i + batch_size]
        url = f"https://marketplace-api.wildberries.ru/api/v3/stocks/{warehouse_id}"
        payload = {"stocks": [{"chrtId": item['chrt_id'], "amount": item['amount']} for item in batch]}
        bucket = limiter.get_bucket(url)
        limiter.wait_for_token(bucket)
        
        try:
            response = requests.put(url, json=payload, headers=headers, timeout=30)
            if response.status_code == 204:
                updated_count += len(batch)
                log_event('INFO', method_name, f'Успешно обновлен батч {i//batch_size + 1}',
                         {'warehouse_id': warehouse_id, 'batch_size': len(batch)})
            elif response.status_code == 409:
                log_event('WARNING', method_name, f'Ошибка 409 при обновлении батча',
                         {'warehouse_id': warehouse_id, 'response': response.text})
            else:
                log_event('ERROR', method_name, f'Ошибка API при обновлении остатков',
                         {'warehouse_id': warehouse_id, 'status_code': response.status_code, 'response': response.text})
        except requests.exceptions.RequestException as e:
            log_event('ERROR', method_name, f'Ошибка сети при обновлении остатков',
                     {'warehouse_id': warehouse_id, 'error': str(e)})
        except Exception as e:
            log_event('ERROR', method_name, f'Неожиданная ошибка при обновлении остатков',
                     {'warehouse_id': warehouse_id, 'error': str(e)})
    
    return updated_count