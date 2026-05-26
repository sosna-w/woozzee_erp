import time
from datetime import datetime
from models import Token, db
from utils.logger import log_event

def save_token(token_value):
    start_time = time.time()
    method_name = "save_token"
    try:
        log_event('INFO', method_name, 'Сохранение токена')
        token = Token.query.first()
        if token:
            token.token_value = token_value
            token.updated_at = datetime.utcnow()
            action = 'updated'
        else:
            token = Token(token_value=token_value)
            db.session.add(token)
            action = 'created'
        db.session.commit()
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Токен успешно сохранен', {'action': action}, duration_ms=duration)
        return True
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при сохранении токена', {'error': str(e)}, duration_ms=duration)
        return False

def get_token():
    start_time = time.time()
    method_name = "get_token"
    try:
        log_event('DEBUG', method_name, 'Получение токена')
        token = Token.query.first()
        if token:
            duration = (time.time() - start_time) * 1000
            log_event('DEBUG', method_name, 'Токен найден', duration_ms=duration)
            return token.token_value
        else:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, 'Токен не найден', duration_ms=duration)
            return None
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении токена', {'error': str(e)}, duration_ms=duration)
        return None

def token_exists():
    start_time = time.time()
    method_name = "token_exists"
    try:
        log_event('DEBUG', method_name, 'Проверка наличия токена')
        exists = Token.query.first() is not None
        duration = (time.time() - start_time) * 1000
        log_event('DEBUG', method_name, f'Результат проверки токена: {exists}', {'exists': exists}, duration_ms=duration)
        return exists
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при проверке токена', {'error': str(e)}, duration_ms=duration)
        return False

def delete_token():
    start_time = time.time()
    method_name = "delete_token"
    try:
        log_event('INFO', method_name, 'Удаление токена')
        token = Token.query.first()
        if token:
            db.session.delete(token)
            db.session.commit()
            duration = (time.time() - start_time) * 1000
            log_event('INFO', method_name, 'Токен успешно удален', duration_ms=duration)
            return True
        else:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, 'Токен не найден для удаления', duration_ms=duration)
            return False
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при удалении токена', {'error': str(e)}, duration_ms=duration)
        return False

def get_api_key():
    token = get_token()
    if token:
        return token
    log_event('ERROR', 'get_api_key', 'Токен отсутствует в базе данных')
    return None