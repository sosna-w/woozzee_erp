import time
import threading
import json
from utils.logger import log_event   # теперь можно использовать вынесенный логгер

class RateLimiter:
    def __init__(self):
        self.buckets = {}
        self.lock = threading.Lock()
        self.initial_configs = {
            'stocks': {'rate': 1/60, 'capacity': 1, 'burst': 1},
            'cards': {'rate': 100/60, 'capacity': 5, 'burst': 5},
            'warehouses': {'rate': 300/60, 'capacity': 20, 'burst': 20},
            'default': {'rate': 1, 'capacity': 1, 'burst': 1}
        }

    def get_bucket(self, url):
        if 'supplier/stocks' in url:
            return 'stocks'
        elif 'content/v2/get/cards/list' in url:
            return 'cards'
        elif '/api/v3/warehouses' in url:
            return 'warehouses'
        return 'default'

    def wait_for_token(self, bucket_name):
        time.sleep(0.1)
        return True

    def handle_response(self, bucket_name, response):
        pass

    def update_bucket_from_headers(self, bucket_name, headers):
        pass


def safe_json_response(response, method_name, url):
    try:
        content_type = response.headers.get('content-type', '')
        if 'application/json' not in content_type:
            log_event('WARNING', method_name, f"Неожиданный content-type: {content_type}",
                      {'response_text': response.text[:1000]})
            return None
        
        if not response.text.strip():
            log_event('WARNING', method_name, "Пустой ответ от сервера")
            return None
            
        return response.json()
    except json.JSONDecodeError as e:
        log_event('ERROR', method_name, "Ошибка декодирования JSON",
                  {'error': str(e), 'response_text': response.text[:1000],
                   'status_code': response.status_code, 'url': url})
        return None
    except Exception as e:
        log_event('ERROR', method_name, "Неожиданная ошибка при обработке ответа",
                  {'error': str(e), 'status_code': response.status_code})
        return None