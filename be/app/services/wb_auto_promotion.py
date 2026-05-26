import time
import json
import requests
import pandas as pd
from io import BytesIO
from utils.logger import log_event

class WBAutoPromotionManager:
    """Класс для получения информации об автоакциях через приватный API Wildberries"""
    
    def __init__(self, authorize_v3=None, wb_seller_lk=None, cookie=None, root_version=None):
        self.authorize_v3 = authorize_v3
        self.wb_seller_lk = wb_seller_lk
        self.cookie = cookie
        self.root_version = root_version or "v1.86.1"
        self.base_url = "https://discounts-prices.wildberries.ru"

        self.headers = {
            "authorizev3": self.authorize_v3 or "",
            "wb-seller-lk": self.wb_seller_lk or "",
            "cookie": self.cookie or "",
            "root-version": self.root_version,
            "content-type": "application/json",
            "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36",
            "accept": "*/*",
            "origin": "https://seller.wildberries.ru",
            "referer": "https://seller.wildberries.ru/"
        }
        
        # Rate limiter для API
        self.request_count = 0
        self.first_request_time = time.time()
    
    def set_auth(self, authorize_v3, wb_seller_lk, cookie=None, root_version=None):
        self.authorize_v3 = authorize_v3
        self.wb_seller_lk = wb_seller_lk
        if cookie is not None:
            self.cookie = cookie
        if root_version:
            self.root_version = root_version
        self.headers["authorizev3"] = authorize_v3
        self.headers["wb-seller-lk"] = wb_seller_lk
        self.headers["cookie"] = self.cookie or ""
        self.headers["root-version"] = self.root_version
        
        log_event('INFO', 'WBAutoPromotionManager', 'Авторизация для автоакций установлена')

    def _make_request(self, method, endpoint, params=None, data=None):
        self.request_count += 1
        elapsed = time.time() - self.first_request_time
        if self.request_count >= 10 and elapsed < 6:
            sleep_time = 6 - elapsed + 0.1
            time.sleep(sleep_time)
            self.request_count = 0
            self.first_request_time = time.time()

        url = f"{self.base_url}{endpoint}"

        # Подготовка данных для логирования (маскируем чувствительные заголовки)
        safe_headers = self.headers.copy()
        if 'AuthorizeV3' in safe_headers:
            safe_headers['AuthorizeV3'] = safe_headers['AuthorizeV3'][:20] + '...' if safe_headers['AuthorizeV3'] else ''
        if 'Wb-Seller-Lk' in safe_headers:
            safe_headers['Wb-Seller-Lk'] = safe_headers['Wb-Seller-Lk'][:20] + '...' if safe_headers['Wb-Seller-Lk'] else ''
        if 'Cookie' in safe_headers:
            safe_headers['Cookie'] = safe_headers['Cookie'][:30] + '...' if safe_headers['Cookie'] else ''

        log_event('DEBUG', 'WBAutoPromotionManager', 'Отправка запроса',
                {
                    'url': url,
                    'method': method,
                    'headers': safe_headers,
                    'params': params,
                    'data': data,
                })

        try:
            response = requests.request(
                method=method,
                url=url,
                headers=self.headers,
                params=params,
                json=data,
                timeout=60
            )

            log_event('DEBUG', 'WBAutoPromotionManager', 'Получен ответ',
                    {
                        'status_code': response.status_code,
                        'headers': dict(response.headers),
                        'content_preview': response.text[:500] if response.text else '',
                        'content_type': response.headers.get('Content-Type'),
                    })

            if response.status_code == 200:
                if method == "GET" and endpoint.rstrip('/').endswith('/excel'):
                    return response.content
                else:
                    try:
                        return response.json()
                    except:
                        return response.text
            elif response.status_code == 401:
                log_event('ERROR', 'WBAutoPromotionManager',
                        'Ошибка авторизации 401',
                        {
                            'url': url,
                            'headers_sent': safe_headers,
                            'response_headers': dict(response.headers),
                            'response_body': response.text[:500]
                        })
                return None
            elif response.status_code == 429:
                retry_after = response.headers.get('Retry-After', 5)
                log_event('WARNING', 'WBAutoPromotionManager',
                        'Превышен лимит запросов к API автоакций',
                        {'retry_after': retry_after})
                time.sleep(int(retry_after))
                return self._make_request(method, endpoint, params, data)
            else:
                log_event('ERROR', 'WBAutoPromotionManager',
                        'Ошибка при запросе к API автоакций',
                        {'status_code': response.status_code, 'response_text': response.text[:500]})
                return None

        except requests.RequestException as e:
            log_event('ERROR', 'WBAutoPromotionManager', 'Ошибка соединения с API автоакций',
                    {'error': str(e)})
            return None

    def test_access(self):
        if not self.authorize_v3 or not self.wb_seller_lk:
            log_event('ERROR', 'WBAutoPromotionManager', 'Не установлена авторизация для автоакций')
            return False

        log_event('INFO', 'WBAutoPromotionManager', 'Тестирование доступа к API автоакций')
        response = self.get_promotion_details(2225)  # ID акции, которая точно существует
        if response:
            period_id = response.get("periodID") or (response.get("data", {}).get("periodID"))
            if period_id:
                log_event('INFO', 'WBAutoPromotionManager', 'API автоакций доступен')
                return True
        log_event('ERROR', 'WBAutoPromotionManager', 'API автоакций недоступен')
        return False
    
    def get_promotion_details(self, promotion_id):
        log_event('INFO', 'WBAutoPromotionManager',
                f'Получение информации об автоакции ID={promotion_id}')

        endpoint = "/ns/calendar-api/dp-calendar/suppliers/api/v1/promo/action"
        params = {"promoActionID": promotion_id}

        response = self._make_request("GET", endpoint, params)

        if response and isinstance(response, dict):
            period_id = response.get("periodID") or response.get("data", {}).get("periodID")
            if period_id:
                log_event('INFO', 'WBAutoPromotionManager',
                        f'Получен periodID={period_id} для акции {promotion_id}')
                return response
            else:
                log_event('ERROR', 'WBAutoPromotionManager',
                        'В ответе не найден periodID',
                        {'response_keys': list(response.keys())})
                return None
        else:
            log_event('ERROR', 'WBAutoPromotionManager',
                    'Не удалось получить информацию об акции')
            return None

    def create_report_task(self, period_id):
        data = {"periodID": period_id}
        log_event('INFO', 'WBAutoPromotionManager',
                f'Создание задачи на отчет для periodID={period_id}')

        endpoint = "/ns/calendar-api/dp-calendar/suppliers/api/v1/excel/create"

        response = self._make_request("POST", endpoint, data=data)

        log_event('DEBUG', 'WBAutoPromotionManager',
                f'Ответ API на создание задачи: {response}')

        if response is None:
            log_event('ERROR', 'WBAutoPromotionManager',
                    'Ответ от API отсутствует')
            return False

        if isinstance(response, dict):
            if response.get('error') == True:
                error_text = response.get('errorText', 'Неизвестная ошибка')
                log_event('ERROR', 'WBAutoPromotionManager',
                        f'Ошибка при создании задачи: {response}',
                        details={'period_id': period_id, 'error_text': error_text})
                return False
            else:
                log_event('INFO', 'WBAutoPromotionManager',
                        f'Задача на отчет создана для periodID={period_id}')
                return True
        else:
            log_event('ERROR', 'WBAutoPromotionManager',
                    f'Неожиданный тип ответа: {type(response)}')
            return False

    def get_excel_report(self, period_id, is_recovery=False):
        params = {"periodID": period_id, "isRecovery": str(is_recovery).lower()}
        log_event('INFO', 'WBAutoPromotionManager',
                f'Загрузка отчета для periodID={period_id}')

        endpoint = "/ns/calendar-api/dp-calendar/suppliers/api/v1/excel"

        response = self._make_request("GET", endpoint, params=params)

        if response is None or len(response) == 0:
            log_event('ERROR', 'WBAutoPromotionManager',
                    f'Пустой ответ от сервера для periodID={period_id}')
            return None
        
        try:
            if isinstance(response, bytes):
                json_data = json.loads(response.decode('utf-8'))
            elif isinstance(response, str):
                json_data = json.loads(response)
            else:
                json_data = response
            
            log_event('DEBUG', 'WBAutoPromotionManager', 
                    f'Ответ JSON для periodID={period_id}: {json.dumps(json_data, ensure_ascii=False)[:500]}')
            
            if isinstance(json_data, dict) and json_data.get('error', False):
                error_text = json_data.get('errorText', 'Неизвестная ошибка')
                temporary_error_phrases = ['не готов', 'формируется', 'в обработке', 'not ready', 'processing', 'pending']
                if any(phrase in error_text.lower() for phrase in temporary_error_phrases):
                    log_event('WARNING', 'WBAutoPromotionManager', 
                            f'Отчет ещё не готов для periodID={period_id}: {error_text}',
                            details={'period_id': period_id, 'error_text': error_text})
                    return None
                else:
                    log_event('ERROR', 'WBAutoPromotionManager', 
                            f'Ошибка при получении отчета для periodID={period_id}: {error_text}',
                            details={'period_id': period_id, 'full_response': json_data})
                    return None
            
            if isinstance(json_data, dict) and 'data' in json_data and 'file' in json_data['data']:
                file_data = json_data['data']['file']
                if file_data:
                    import base64
                    file_bytes = base64.b64decode(file_data)
                    log_event('INFO', 'WBAutoPromotionManager', 
                            f'Excel отчет получен из base64, размер: {len(file_bytes)} байт')
                    return file_bytes
                else:
                    log_event('ERROR', 'WBAutoPromotionManager', 
                            f'Пустой файл в ответе для periodID={period_id}')
                    return None
            
            log_event('ERROR', 'WBAutoPromotionManager', 
                    f'Неожиданная структура JSON для periodID={period_id}: {json_data}')
            return None
            
        except json.JSONDecodeError:
            log_event('DEBUG', 'WBAutoPromotionManager', 
                    f'Ответ не JSON, пробуем как Excel файл для periodID={period_id}')
            
            if isinstance(response, bytes):
                if len(response) > 4:
                    excel_signatures = [
                        b'\x50\x4B\x03\x04',  # ZIP (XLSX)
                        b'\xD0\xCF\x11\xE0',  # OLE2 (XLS)
                    ]
                    signature = response[:4]
                    if signature in excel_signatures:
                        log_event('INFO', 'WBAutoPromotionManager', 
                                f'Excel отчет получен напрямую, размер: {len(response)} байт')
                        return response
                    else:
                        try:
                            text_error = response.decode('utf-8')
                            log_event('ERROR', 'WBAutoPromotionManager', 
                                    f'Ответ в виде текста: {text_error[:500]}')
                        except:
                            pass
                        log_event('ERROR', 'WBAutoPromotionManager', 
                                f'Неизвестный формат файла: {signature.hex()}')
                        return None
                else:
                    log_event('ERROR', 'WBAutoPromotionManager', 
                            f'Ответ слишком короткий: {len(response)} байт')
                    return None
            else:
                log_event('ERROR', 'WBAutoPromotionManager', 
                        f'Неизвестный тип ответа: {type(response)}')
                return None
    
    def extract_articles_and_discounts(self, excel_data):
        try:
            excel_io = BytesIO(excel_data)
            try:
                df = pd.read_excel(excel_io, engine='openpyxl')
            except:
                excel_io.seek(0)
                df = pd.read_excel(excel_io, engine='xlrd')
            
            log_event('INFO', 'WBAutoPromotionManager', 
                     f'Excel файл прочитан, строк: {len(df)}, столбцов: {len(df.columns)}')
            
            art_col = None
            discount_col = None
            
            possible_art_names = ["Артикул WB"]
            possible_discount_names = ["Загружаемая скидка для участия в акции"]
            
            for col in df.columns:
                col_str = str(col)
                if not art_col:
                    for art_name in possible_art_names:
                        if art_name.lower() in col_str.lower():
                            art_col = col
                            break
                if not discount_col:
                    for discount_name in possible_discount_names:
                        if discount_name.lower() in col_str.lower():
                            discount_col = col
                            break
            
            if not art_col:
                for col in df.columns:
                    if 'артикул' in str(col).lower():
                        art_col = col
                        break
            
            if not discount_col:
                for col in df.columns:
                    if 'скидк' in str(col).lower():
                        discount_col = col
                        break
            
            if not art_col or not discount_col:
                for col in df.columns:
                    if art_col and discount_col:
                        break
                    col_type = str(df[col].dtype)
                    if not art_col and (col_type.startswith('int') or col_type.startswith('str')):
                        art_col = col
                    elif not discount_col and (col_type.startswith('int') or col_type.startswith('float')):
                        discount_col = col
            
            log_event('INFO', 'WBAutoPromotionManager', 
                     f'Найденные столбцы: артикул={art_col}, скидка={discount_col}')
            
            if not art_col or not discount_col:
                log_event('ERROR', 'WBAutoPromotionManager', 
                         'Не удалось найти нужные столбцы в Excel файле')
                return []
            
            results = []
            for _, row in df.iterrows():
                try:
                    article = row[art_col]
                    discount = row[discount_col]
                    if pd.isna(article) or pd.isna(discount):
                        continue
                    article_str = str(int(article)) if pd.notna(article) and not isinstance(article, str) else str(article)
                    if pd.notna(discount):
                        if isinstance(discount, (int, float)):
                            discount_num = float(discount)
                        else:
                            try:
                                discount_num = float(str(discount).replace(',', '.').replace('%', '').strip())
                            except:
                                continue
                    else:
                        continue
                    results.append({
                        'wb_article': article_str,
                        'discount': discount_num
                    })
                except Exception as e:
                    log_event('WARNING', 'WBAutoPromotionManager', 
                             f'Ошибка обработки строки: {str(e)}')
                    continue
            
            log_event('INFO', 'WBAutoPromotionManager', 
                     f'Извлечено {len(results)} записей из Excel файла')
            return results
            
        except Exception as e:
            log_event('ERROR', 'WBAutoPromotionManager', 
                     f'Ошибка при обработке Excel файла: {str(e)}')
            return []

    def process_promotion(self, promotion_id):
        start_time = time.time()
        try:
            log_event('INFO', 'WBAutoPromotionManager', 
                    f'Начало обработки автоакции ID={promotion_id}')
            
            promo_details = self.get_promotion_details(promotion_id)
            if not promo_details:
                log_event('ERROR', 'WBAutoPromotionManager', 
                        f'Не удалось получить информацию об автоакции ID={promotion_id}')
                return []
            
            period_id = None
            if "periodID" in promo_details:
                period_id = promo_details.get("periodID")
            elif "data" in promo_details and isinstance(promo_details["data"], dict):
                period_id = promo_details["data"].get("periodID")
            else:
                for key, value in promo_details.items():
                    if "period" in key.lower() and isinstance(value, (int, str)):
                        period_id = value
                        break
            
            if not period_id:
                log_event('ERROR', 'WBAutoPromotionManager', 
                        f'Не удалось найти periodID для автоакции ID={promotion_id}')
                return []
            
            log_event('INFO', 'WBAutoPromotionManager', 
                    f'Найден periodID: {period_id} для автоакции ID={promotion_id}')
            
            if not self.create_report_task(period_id):
                log_event('ERROR', 'WBAutoPromotionManager', 
                        f'Не удалось создать задачу на отчет для periodID={period_id}')
                return []
            
            max_attempts = 5
            attempt = 0
            excel_data = None
            while attempt < max_attempts:
                attempt += 1
                log_event('INFO', 'WBAutoPromotionManager', 
                        f'Попытка {attempt} получения отчета для periodID={period_id}')
                wait_time = 3 * attempt
                time.sleep(wait_time)
                excel_data = self.get_excel_report(period_id, is_recovery=(attempt > 1))
                if excel_data:
                    log_event('INFO', 'WBAutoPromotionManager', 
                            f'Отчет получен на попытке {attempt}')
                    break
                else:
                    log_event('WARNING', 'WBAutoPromotionManager', 
                            f'Отчет не готов, повтор через {wait_time}с')
            
            if not excel_data:
                log_event('ERROR', 'WBAutoPromotionManager', 
                        f'Не удалось получить Excel отчет для periodID={period_id} после {max_attempts} попыток')
                return []
            
            results = self.extract_articles_and_discounts(excel_data)
            duration = (time.time() - start_time) * 1000
            log_event('INFO', 'WBAutoPromotionManager', 
                    f'Обработка автоакции ID={promotion_id} завершена',
                    {'duration_ms': duration, 'results_count': len(results)})
            return results
            
        except Exception as e:
            duration = (time.time() - start_time) * 1000
            log_event('ERROR', 'WBAutoPromotionManager', 
                    f'Ошибка при обработке автоакции ID={promotion_id}',
                    {'error': str(e), 'duration_ms': duration})
            return []

    def process_multiple_promotions(self, promotion_ids):
        results = {}
        log_event('INFO', 'WBAutoPromotionManager', 
                 f'Начало обработки {len(promotion_ids)} автоакций')
        for promotion_id in promotion_ids:
            try:
                promotion_results = self.process_promotion(promotion_id)
                results[str(promotion_id)] = promotion_results
                log_event('INFO', 'WBAutoPromotionManager', 
                         f'Автоакция ID={promotion_id} обработана',
                         {'results_count': len(promotion_results)})
            except Exception as e:
                log_event('ERROR', 'WBAutoPromotionManager', 
                         f'Ошибка при обработке автоакции ID={promotion_id}',
                         {'error': str(e)})
                results[str(promotion_id)] = []
        log_event('INFO', 'WBAutoPromotionManager', 
                 f'Обработка {len(promotion_ids)} автоакций завершена')
        return results