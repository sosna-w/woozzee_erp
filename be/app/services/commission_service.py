import time
import requests
from utils.logger import log_event
from utils.token_manager import get_api_key
from utils.rate_limiter import RateLimiter, safe_json_response
from models import db, Commission

limiter = RateLimiter()


def fetch_commissions():
    start_time = time.time()
    method_name = "fetch_commissions"
    
    try:
        log_event('INFO', method_name, 'Начало получения комиссий')
        
        api_key = get_api_key()
        if not api_key:
            log_event('ERROR', method_name, 'Отсутствует API токен')
            return
        
        url = "https://common-api.wildberries.ru/api/v1/tariffs/commission"
        headers = {
            'Authorization': api_key,
            'Content-Type': 'application/json'
        }
        params = {'locale': 'ru'}
        
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
                    
                    commissions_data = data.get('report', [])
                    
                    if not isinstance(commissions_data, list):
                        log_event('ERROR', method_name, "Некорректный формат данных комиссий",
                                 {'data_type': type(commissions_data)})
                        return
                    
                    log_event('INFO', method_name, f"Начало сохранения {len(commissions_data)} комиссий в БД")
                    db_save_start = time.time()
                    
                    saved_count = 0
                    updated_count = 0
                    
                    for commission_data in commissions_data:
                        try:
                            required_fields = ['subjectID', 'parentID', 'subjectName', 'parentName']
                            missing_fields = [field for field in required_fields if field not in commission_data]
                            if missing_fields:
                                log_event('WARNING', method_name, f'Отсутствуют обязательные поля в данных комиссии',
                                         {'missing_fields': missing_fields})
                                continue
                            
                            commission = Commission.query.filter_by(
                                subjectID=commission_data['subjectID'],
                                parentID=commission_data['parentID']
                            ).first()
                            
                            if commission:
                                commission.kgvpBooking = commission_data.get('kgvpBooking', 0)
                                commission.kgvpMarketplace = commission_data.get('kgvpMarketplace', 0)
                                commission.kgvpPickup = commission_data.get('kgvpPickup', 0)
                                commission.kgvpSupplier = commission_data.get('kgvpSupplier', 0)
                                commission.kgvpSupplierExpress = commission_data.get('kgvpSupplierExpress', 0)
                                commission.paidStorageKgvp = commission_data.get('paidStorageKgvp', 0)
                                commission.parentName = commission_data['parentName']
                                commission.subjectName = commission_data['subjectName']
                                commission.updated_at = datetime.utcnow()
                                updated_count += 1
                            else:
                                commission = Commission(
                                    kgvpBooking=commission_data.get('kgvpBooking', 0),
                                    kgvpMarketplace=commission_data.get('kgvpMarketplace', 0),
                                    kgvpPickup=commission_data.get('kgvpPickup', 0),
                                    kgvpSupplier=commission_data.get('kgvpSupplier', 0),
                                    kgvpSupplierExpress=commission_data.get('kgvpSupplierExpress', 0),
                                    paidStorageKgvp=commission_data.get('paidStorageKgvp', 0),
                                    parentID=commission_data['parentID'],
                                    parentName=commission_data['parentName'],
                                    subjectID=commission_data['subjectID'],
                                    subjectName=commission_data['subjectName']
                                )
                                db.session.add(commission)
                                saved_count += 1
                            
                        except Exception as e:
                            log_event('ERROR', method_name, f"Ошибка при обработке комиссии",
                                     {'subjectID': commission_data.get('subjectID'), 'error': str(e)})
                            continue
                    
                    db.session.commit()
                    db_save_duration = (time.time() - db_save_start) * 1000
                    
                    total_duration = (time.time() - start_time) * 1000
                    performance_info = {
                        'total_commissions': len(commissions_data),
                        'saved': saved_count,
                        'updated': updated_count,
                        'total_duration_ms': total_duration,
                        'db_save_duration_ms': db_save_duration
                    }
                    
                    log_event('INFO', method_name, "Завершение получения комиссий",
                             performance_info,
                             duration_ms=total_duration, records_processed=len(commissions_data))
                    
                    print(f"Обновлено комиссий: сохранено {saved_count}, обновлено {updated_count}")
                    break
                    
                elif response.status_code == 429:
                    retry_after = int(response.headers.get('Retry-After', 60))
                    log_event('WARNING', method_name, f"Превышен лимит запросов, ждем {retry_after}с")
                    time.sleep(retry_after)
                    continue
                    
                else:
                    log_event('ERROR', method_name, f"Ошибка API при получении комиссий",
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
        log_event('ERROR', method_name, "Критическая ошибка при получении комиссий",
                 {'error': str(e), 'traceback': traceback.format_exc()},
                 duration_ms=error_duration)
        raise