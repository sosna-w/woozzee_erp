from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from utils.token_manager import save_token, get_token, delete_token, token_exists
from models import PrivateKey, db
from utils.logger import log_event

admin_bp = Blueprint('admin', __name__)


@admin_bp.route('/token', methods=['POST'])
@jwt_required()
def save_token_endpoint():
    start_time = time.time()
    try:
        data = request.get_json()
        if not data or 'token_value' not in data:
            from utils.logger import log_event
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', 'save_token_endpoint', 'Неверные данные запроса',
                     {'data': data}, duration_ms=duration)
            return jsonify({"error": "token_value is required"}), 400
        
        token_value = data['token_value']
        
        if save_token(token_value):
            # Фоновый запуск загрузки данных (нужно передать функции, но они в app.py)
            # Чтобы не усложнять, импортируем их здесь (циклической зависимости не будет, т.к. они из сервисов)
            from services.unified_product_service import fetch_all_products_with_unified, fetch_all_stocks_with_unified
            from services.product_service import fetch_warehouses
            import threading
            
            def run_in_background(func, func_name):
                def wrapper():
                    try:
                        from flask import current_app
                        with current_app.app_context():
                            log_event('INFO', 'auto_start', f'Автозапуск {func_name} после сохранения токена')
                            func()
                    except Exception as e:
                        log_event('ERROR', 'auto_start', f'Ошибка при автозапуске {func_name}',
                                 {'error': str(e)})
                
                thread = threading.Thread(target=wrapper)
                thread.daemon = True
                thread.start()
            
            run_in_background(fetch_all_products_with_unified, 'товаров')
            run_in_background(fetch_all_stocks_with_unified, 'остатков')
            run_in_background(fetch_warehouses, 'складов')
            
            duration = (time.time() - start_time) * 1000
            log_event('INFO', 'save_token_endpoint', 'Токен успешно сохранен и запущена фоновая загрузка данных',
                     duration_ms=duration)
            return jsonify({
                "status": "Token saved successfully", 
                "message": "Автоматически запущена загрузка товаров, остатков и складов"
            })
        else:
            duration = (time.time() - start_time) * 1000
            log_event('ERROR', 'save_token_endpoint', 'Ошибка при сохранении токена',
                     duration_ms=duration)
            return jsonify({"error": "Failed to save token"}), 500
            
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', 'save_token_endpoint', 'Ошибка при сохранении токена',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@admin_bp.route('/token', methods=['GET'])
@jwt_required()
def get_token_endpoint():
    start_time = time.time()
    try:
        token = get_token()
        duration = (time.time() - start_time) * 1000
        
        if token:
            log_event('INFO', 'get_token_endpoint', 'Токен найден',
                     duration_ms=duration)
            return jsonify({"token_value": token})
        else:
            log_event('WARNING', 'get_token_endpoint', 'Токен не найден',
                     duration_ms=duration)
            return jsonify({"error": "Token not found"}), 404
            
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', 'get_token_endpoint', 'Ошибка при получении токена',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@admin_bp.route('/token', methods=['DELETE'])
@jwt_required()
def delete_token_endpoint():
    start_time = time.time()
    try:
        if delete_token():
            duration = (time.time() - start_time) * 1000
            log_event('INFO', 'delete_token_endpoint', 'Токен успешно удален',
                     duration_ms=duration)
            return jsonify({"status": "Token deleted successfully"})
        else:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', 'delete_token_endpoint', 'Токен не найден для удаления',
                     duration_ms=duration)
            return jsonify({"error": "Token not found"}), 404
            
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', 'delete_token_endpoint', 'Ошибка при удалении токена',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@admin_bp.route('/token/exists', methods=['GET'])
@jwt_required()
def token_exists_endpoint():
    start_time = time.time()
    try:
        exists = token_exists()
        duration = (time.time() - start_time) * 1000
        
        log_event('INFO', 'token_exists_endpoint', 'Проверка наличия токена завершена',
                 {'exists': exists}, duration_ms=duration)
        return jsonify({"exists": exists})
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', 'token_exists_endpoint', 'Ошибка при проверке токена',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@admin_bp.route('/private-keys', methods=['GET'])
@jwt_required()
def get_private_keys():
    """Получить сохранённые приватные ключи"""
    try:
        pkeys = PrivateKey.get_instance()
        return jsonify(pkeys.to_dict())
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@admin_bp.route('/private-keys', methods=['POST'])
@jwt_required()
def save_private_keys():
    """Сохранить приватные ключи"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No data"}), 400
        pkeys = PrivateKey.get_instance()
        if 'authorize_v3' in data:
            pkeys.authorize_v3 = data['authorize_v3'].strip()
        if 'wb_seller_lk' in data:
            pkeys.wb_seller_lk = data['wb_seller_lk'].strip()
        if 'cookie' in data:
            pkeys.cookie = data['cookie'].strip()
        db.session.commit()
        return jsonify({"status": "saved", "keys": pkeys.to_dict()})
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500


@admin_bp.route('/private-keys', methods=['DELETE'])
@jwt_required()
def delete_private_keys():
    """Очистить приватные ключи"""
    try:
        pkeys = PrivateKey.get_instance()
        pkeys.authorize_v3 = ''
        pkeys.wb_seller_lk = ''
        pkeys.cookie = ''
        db.session.commit()
        return jsonify({"status": "cleared"})
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500