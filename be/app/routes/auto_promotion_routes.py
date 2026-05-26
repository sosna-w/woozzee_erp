import time
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from utils.logger import log_event
from services.wb_auto_promotion import WBAutoPromotionManager

auto_promo_bp = Blueprint('auto_promo', __name__)


@auto_promo_bp.route('/auto-promotions/process', methods=['POST'])
@jwt_required()
def process_auto_promotions():
    """
    Эндпоинт для обработки автоакций.
    Принимает authorize_v3, wb_seller_lk, cookie и список ID акций.
    Возвращает пары "Артикул WB" и "Скидка".
    """
    start_time = time.time()
    method_name = "process_auto_promotions"
    
    try:
        log_event('INFO', method_name, 'Запрос на обработку автоакций')
        
        data = request.get_json()
        if not data:
            log_event('WARNING', method_name, 'Нет данных в запросе')
            return jsonify({"error": "Данные не предоставлены"}), 400
        
        authorize_v3 = data.get('authorize_v3')
        wb_seller_lk = data.get('wb_seller_lk')
        cookie = data.get('cookie')
        root_version = data.get('root_version')  # опционально
        promotion_ids = data.get('promotion_ids', [])
        
        if not authorize_v3:
            log_event('WARNING', method_name, 'Не указан authorize_v3')
            return jsonify({"error": "authorize_v3 обязателен"}), 400
        
        if not wb_seller_lk:
            log_event('WARNING', method_name, 'Не указан wb_seller_lk')
            return jsonify({"error": "wb_seller_lk обязателен"}), 400
        
        if not promotion_ids or not isinstance(promotion_ids, list):
            log_event('WARNING', method_name, 'Не указаны или некорректны promotion_ids')
            return jsonify({"error": "promotion_ids должен быть непустым списком"}), 400
        
        if not cookie:
            return jsonify({"error": "cookie обязателен"}), 400
        
        log_event('INFO', method_name, 'Параметры запроса получены',
                 {'promotion_ids_count': len(promotion_ids)})
        
        promo_manager = WBAutoPromotionManager(authorize_v3, wb_seller_lk, cookie, root_version)
        
        log_event('INFO', method_name, 'Тестирование доступа к API автоакций')
        if not promo_manager.test_access():
            log_event('ERROR', method_name, 'Нет доступа к API автоакций')
            return jsonify({"error": "Нет доступа к API автоакций. Проверьте authorize_v3 и wb_seller_lk"}), 403
        
        log_event('INFO', method_name, f'Начало обработки {len(promotion_ids)} автоакций')
        results = promo_manager.process_multiple_promotions(promotion_ids)
        
        total_results = 0
        for promotion_id, promo_results in results.items():
            total_results += len(promo_results)
        
        duration = (time.time() - start_time) * 1000
        
        log_event('INFO', method_name, 'Обработка автоакций завершена',
                 {
                     'promotion_ids_count': len(promotion_ids),
                     'total_results': total_results,
                     'duration_ms': duration
                 },
                 duration_ms=duration,
                 records_processed=total_results)
        
        return jsonify({
            "status": "success",
            "message": f"Обработано {len(promotion_ids)} автоакций, найдено {total_results} товаров",
            "results": results,
            "statistics": {
                "promotions_processed": len(promotion_ids),
                "total_products_found": total_results,
                "duration_ms": duration
            }
        })
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при обработке автоакций',
                 {'error': str(e), 'traceback': traceback.format_exc()},
                 duration_ms=duration)
        return jsonify({"error": str(e)}), 500