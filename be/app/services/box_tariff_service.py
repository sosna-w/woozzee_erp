import time
from datetime import datetime
import requests
from utils.logger import log_event
from utils.token_manager import get_api_key
from utils.rate_limiter import RateLimiter, safe_json_response
from models import db, BoxTariff

limiter = RateLimiter()


def fetch_box_tariffs(date=None):
    """Получить тарифы для коробов с API Wildberries"""
    start_time = time.time()
    method_name = "fetch_box_tariffs"
    
    try:
        log_event('INFO', method_name, 'Начало получения тарифов коробов')
        
        api_key = get_api_key()
        if not api_key:
            log_event('ERROR', method_name, 'Отсутствует API токен')
            return
        
        if not date:
            date = datetime.now().strftime('%Y-%m-%d')
        
        url = "https://common-api.wildberries.ru/api/v1/tariffs/box"
        headers = {
            'Authorization': api_key,
            'Content-Type': 'application/json'
        }
        params = {'date': date}
        
        bucket = limiter.get_bucket(url)
        limiter.wait_for_token(bucket)
        
        max_retries = 3
        
        for attempt in range(max_retries):
            try:
                request_start = time.time()
                response = requests.get(url, headers=headers, params=params, timeout=30)
                request_duration = (time.time() - request_start) * 1000
                
                limiter.handle_response(bucket, response)
                
                log_event('DEBUG', method_name, f"Получен ответ (попытка {attempt + 1})",
                         {'status_code': response.status_code, 'duration_ms': request_duration, 'date': date},
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
                    
                    response_data = data.get('response', {}).get('data', {})
                    
                    dt_next_box = response_data.get('dtNextBox')
                    dt_till_max = response_data.get('dtTillMax')
                    warehouse_list = response_data.get('warehouseList', [])
                    
                    if not warehouse_list:
                        log_event('WARNING', method_name, 'Список тарифов пуст')
                        return
                    
                    log_event('INFO', method_name, f"Начало сохранения {len(warehouse_list)} тарифов в БД")
                    db_save_start = time.time()
                    
                    saved_count = 0
                    updated_count = 0
                    
                    for tariff_data in warehouse_list:
                        try:
                            required_fields = ['warehouseName', 'geoName']
                            missing_fields = [field for field in required_fields if field not in tariff_data]
                            if missing_fields:
                                log_event('WARNING', method_name, f'Отсутствуют обязательные поля в данных тарифа',
                                         {'missing_fields': missing_fields})
                                continue
                            
                            existing_tariff = BoxTariff.query.filter_by(
                                date=date,
                                warehouse_name=tariff_data['warehouseName'],
                                geo_name=tariff_data['geoName']
                            ).first()
                            
                            if existing_tariff:
                                existing_tariff.box_delivery_base = tariff_data.get('boxDeliveryBase')
                                existing_tariff.box_delivery_coef_expr = tariff_data.get('boxDeliveryCoefExpr')
                                existing_tariff.box_delivery_liter = tariff_data.get('boxDeliveryLiter')
                                existing_tariff.box_delivery_marketplace_base = tariff_data.get('boxDeliveryMarketplaceBase')
                                existing_tariff.box_delivery_marketplace_coef_expr = tariff_data.get('boxDeliveryMarketplaceCoefExpr')
                                existing_tariff.box_delivery_marketplace_liter = tariff_data.get('boxDeliveryMarketplaceLiter')
                                existing_tariff.box_storage_base = tariff_data.get('boxStorageBase')
                                existing_tariff.box_storage_coef_expr = tariff_data.get('boxStorageCoefExpr')
                                existing_tariff.box_storage_liter = tariff_data.get('boxStorageLiter')
                                existing_tariff.dt_next_box = dt_next_box
                                existing_tariff.dt_till_max = dt_till_max
                                existing_tariff.updated_at = datetime.utcnow()
                                updated_count += 1
                            else:
                                tariff = BoxTariff(
                                    date=date,
                                    warehouse_name=tariff_data['warehouseName'],
                                    geo_name=tariff_data['geoName'],
                                    box_delivery_base=tariff_data.get('boxDeliveryBase'),
                                    box_delivery_coef_expr=tariff_data.get('boxDeliveryCoefExpr'),
                                    box_delivery_liter=tariff_data.get('boxDeliveryLiter'),
                                    box_delivery_marketplace_base=tariff_data.get('boxDeliveryMarketplaceBase'),
                                    box_delivery_marketplace_coef_expr=tariff_data.get('boxDeliveryMarketplaceCoefExpr'),
                                    box_delivery_marketplace_liter=tariff_data.get('boxDeliveryMarketplaceLiter'),
                                    box_storage_base=tariff_data.get('boxStorageBase'),
                                    box_storage_coef_expr=tariff_data.get('boxStorageCoefExpr'),
                                    box_storage_liter=tariff_data.get('boxStorageLiter'),
                                    dt_next_box=dt_next_box,
                                    dt_till_max=dt_till_max
                                )
                                db.session.add(tariff)
                                saved_count += 1
                            
                        except Exception as e:
                            log_event('ERROR', method_name, f"Ошибка при обработке тарифа",
                                     {'warehouse_name': tariff_data.get('warehouseName'), 'error': str(e)})
                            continue
                    
                    db.session.commit()
                    db_save_duration = (time.time() - db_save_start) * 1000
                    
                    total_duration = (time.time() - start_time) * 1000
                    performance_info = {
                        'date': date,
                        'total_tariffs': len(warehouse_list),
                        'saved': saved_count,
                        'updated': updated_count,
                        'total_duration_ms': total_duration,
                        'db_save_duration_ms': db_save_duration
                    }
                    
                    log_event('INFO', method_name, "Завершение получения тарифов коробов",
                             performance_info,
                             duration_ms=total_duration, records_processed=len(warehouse_list))
                    
                    print(f"Обновлено тарифов коробов: сохранено {saved_count}, обновлено {updated_count}")
                    break
                    
                elif response.status_code == 429:
                    retry_after = int(response.headers.get('Retry-After', 60))
                    log_event('WARNING', method_name, f"Превышен лимит запросов, ждем {retry_after}с")
                    time.sleep(retry_after)
                    continue
                    
                elif response.status_code == 400:
                    log_event('ERROR', method_name, "Неправильный запрос тарифов коробов",
                             {'status_code': response.status_code, 'response_text': response.text[:500]},
                             request_url=url, response_status=response.status_code)
                    return
                    
                elif response.status_code == 401:
                    log_event('ERROR', method_name, "Не авторизован для получения тарифов коробов",
                             {'status_code': response.status_code, 'response_text': response.text[:500]},
                             request_url=url, response_status=response.status_code)
                    return
                    
                else:
                    log_event('ERROR', method_name, f"Ошибка API при получении тарифов коробов",
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
        log_event('ERROR', method_name, "Критическая ошибка при получении тарифов коробов",
                 {'error': str(e), 'traceback': traceback.format_exc()},
                 duration_ms=error_duration)
        raise


def hourly_update_box_tariffs():
    """Ежечасное обновление тарифов коробов"""
    start_time = time.time()
    method_name = "hourly_update_box_tariffs"
    
    try:
        log_event('INFO', method_name, 'Начало ежечасного обновления тарифов коробов')
        
        current_date = datetime.now().strftime('%Y-%m-%d')
        
        today_tariffs = BoxTariff.query.filter_by(date=current_date).first()
        
        if today_tariffs:
            last_update = today_tariffs.updated_at
            if last_update:
                hours_since_update = (datetime.utcnow() - last_update).total_seconds() / 3600
                if hours_since_update < 1:
                    log_event('INFO', method_name, f'Тарифы уже обновлялись сегодня {hours_since_update:.1f} часов назад, пропускаем')
                    return
        
        fetch_box_tariffs(current_date)
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Ежечасное обновление тарифов коробов завершено',
                 duration_ms=duration)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при ежечасном обновлении тарифов коробов',
                 {'error': str(e)},
                 duration_ms=duration)