import time
import requests
import traceback
from datetime import datetime
from models import db, Subject
from utils.logger import log_event
from utils.token_manager import get_api_key
from utils.rate_limiter import RateLimiter, safe_json_response

limiter = RateLimiter()

def fetch_all_subjects():
    start_time = time.time()
    method_name = "fetch_all_subjects"
    
    try:
        log_event('INFO', method_name, 'Начало получения списка предметов')
        
        api_key = get_api_key()
        if not api_key:
            log_event('ERROR', method_name, 'Отсутствует API токен')
            return
        
        url = "https://content-api.wildberries.ru/content/v2/object/all"
        headers = {
            'Authorization': api_key,
            'Content-Type': 'application/json'
        }
        
        # Параметры запроса - русский язык
        params = {
            'locale': 'ru',
            'limit': 1000,  # Максимальное количество за один запрос
            'offset': 0
        }
        
        all_subjects = []
        total_fetched = 0
        
        while True:
            try:
                log_event('DEBUG', method_name, f'Запрос предметов с offset {params["offset"]}')
                
                response = requests.get(url, headers=headers, params=params, timeout=30)
                
                if response.status_code == 200:
                    data = safe_json_response(response, method_name, url)
                    if data is None:
                        log_event('ERROR', method_name, 'Не удалось получить валидный JSON ответ')
                        break
                    
                    if data.get('error'):
                        log_event('ERROR', method_name, 'Ошибка в ответе API',
                                 {'error_text': data.get('errorText'), 'additional_errors': data.get('additionalErrors')})
                        break
                    
                    subjects_batch = data.get('data', [])
                    
                    if not subjects_batch:
                        log_event('INFO', method_name, 'Все предметы получены')
                        break
                    
                    all_subjects.extend(subjects_batch)
                    total_fetched += len(subjects_batch)
                    
                    log_event('INFO', method_name, f'Получена партия предметов',
                             {'batch_size': len(subjects_batch), 'total_fetched': total_fetched})
                    
                    # Если получено меньше чем запрошено, значит это последняя партия
                    if len(subjects_batch) < params['limit']:
                        log_event('INFO', method_name, 'Получена последняя партия предметов')
                        break
                    
                    # Увеличиваем offset для следующей партии
                    params['offset'] += params['limit']
                    
                    # Небольшая пауза для соблюдения лимитов API
                    time.sleep(0.6)  # 600 мс как указано в лимитах
                    
                elif response.status_code == 429:
                    retry_after = int(response.headers.get('Retry-After', 60))
                    log_event('WARNING', method_name, f'Превышен лимит запросов, ждем {retry_after}с')
                    time.sleep(retry_after)
                    continue
                    
                else:
                    log_event('ERROR', method_name, f'Ошибка API при получении предметов',
                             {'status_code': response.status_code, 'response_text': response.text[:500]})
                    break
                    
            except requests.exceptions.Timeout:
                log_event('ERROR', method_name, 'Таймаут запроса при получении предметов')
                break
            except requests.exceptions.RequestException as e:
                log_event('ERROR', method_name, f'Ошибка сети при получении предметов: {e}')
                break
        
        # Сохранение предметов в базу данных
        if all_subjects:
            log_event('INFO', method_name, f'Начало сохранения {len(all_subjects)} предметов в БД')
            db_save_start = time.time()
            
            saved_count = 0
            updated_count = 0
            
            for subject_data in all_subjects:
                try:
                    subject_id = subject_data.get('subjectID')
                    parent_id = subject_data.get('parentID')
                    subject_name = subject_data.get('subjectName')
                    parent_name = subject_data.get('parentName')
                    
                    if not all([subject_id, parent_id, subject_name, parent_name]):
                        log_event('WARNING', method_name, 'Пропуск предмета с неполными данными',
                                 {'subject_data': subject_data})
                        continue
                    
                    # Ищем существующую запись
                    subject = Subject.query.filter_by(subject_id=subject_id).first()
                    
                    if subject:
                        # Обновляем существующую запись
                        subject.parent_id = parent_id
                        subject.subject_name = subject_name
                        subject.parent_name = parent_name
                        subject.updated_at = datetime.utcnow()
                        updated_count += 1
                    else:
                        # Создаем новую запись
                        subject = Subject(
                            subject_id=subject_id,
                            parent_id=parent_id,
                            subject_name=subject_name,
                            parent_name=parent_name
                        )
                        db.session.add(subject)
                        saved_count += 1
                        
                except Exception as e:
                    log_event('ERROR', method_name, f'Ошибка при обработке предмета',
                             {'subject_id': subject_data.get('subjectID'), 'error': str(e)})
                    continue
            
            db.session.commit()
            db_save_duration = (time.time() - db_save_start) * 1000
            
            total_duration = (time.time() - start_time) * 1000
            
            log_event('INFO', method_name, 'Завершение получения предметов',
                     {
                         'total_received': len(all_subjects),
                         'saved': saved_count,
                         'updated': updated_count,
                         'total_duration_ms': total_duration,
                         'db_save_duration_ms': db_save_duration
                     },
                     duration_ms=total_duration,
                     records_processed=len(all_subjects))
            
            print(f"✅ Обновлено предметов: сохранено {saved_count}, обновлено {updated_count}")
        else:
            log_event('WARNING', method_name, 'Не получено ни одного предмета')
            
    except Exception as e:
        error_duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Критическая ошибка при получении предметов',
                 {'error': str(e), 'traceback': traceback.format_exc()},
                 duration_ms=error_duration)
        raise