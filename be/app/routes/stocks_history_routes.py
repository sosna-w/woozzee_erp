import time
from datetime import datetime, timedelta
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required

from models import db, StocksHistory, UnifiedProduct
from utils.logger import log_event
from services.unified_product_service import create_stocks_snapshot

stocks_history_bp = Blueprint('stocks_history', __name__)


@stocks_history_bp.route('/stocks-history', methods=['GET'])
@jwt_required()
def get_stocks_history():
    """Получить исторические данные остатков с фильтрацией"""
    start_time = time.time()
    method_name = "get_stocks_history"
    
    try:
        log_event('INFO', method_name, 'Запрос исторических данных остатков')
        
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 10000, type=int)
        nm_id = request.args.get('nm_id', type=int)
        date_from = request.args.get('date_from')
        date_to = request.args.get('date_to')
        
        # Ограничиваем максимальный размер страницы для безопасности
        if per_page > 20000:
            per_page = 20000
        
        query = StocksHistory.query
        
        if nm_id:
            query = query.filter(StocksHistory.nm_id == nm_id)
        
        if date_from:
            try:
                date_from_dt = datetime.fromisoformat(date_from.replace('Z', '+00:00'))
                query = query.filter(StocksHistory.created_at >= date_from_dt)
            except:
                try:
                    date_from_dt = datetime.strptime(date_from, '%Y-%m-%d')
                    query = query.filter(StocksHistory.created_at >= date_from_dt)
                except:
                    log_event('WARNING', method_name, f'Неверный формат date_from: {date_from}')
        
        if date_to:
            try:
                date_to_dt = datetime.fromisoformat(date_to.replace('Z', '+00:00'))
                date_to_dt = date_to_dt.replace(hour=23, minute=59, second=59)
                query = query.filter(StocksHistory.created_at <= date_to_dt)
            except:
                try:
                    date_to_dt = datetime.strptime(date_to, '%Y-%m-%d')
                    date_to_dt = date_to_dt.replace(hour=23, minute=59, second=59)
                    query = query.filter(StocksHistory.created_at <= date_to_dt)
                except:
                    log_event('WARNING', method_name, f'Неверный формат date_to: {date_to}')
        
        # Сортировка по дате создания (новые сначала)
        query = query.order_by(StocksHistory.created_at.desc())
        
        pagination = query.paginate(
            page=page, 
            per_page=per_page, 
            error_out=False
        )
        
        history_records = pagination.items
        
        result = {
            'history': [record.to_dict() for record in history_records],
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            },
            'filters': {
                'nm_id': nm_id,
                'date_from': date_from,
                'date_to': date_to
            }
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат исторических данных остатков',
                 {
                     'page': page,
                     'per_page': per_page,
                     'total_items': pagination.total,
                     'returned_items': len(history_records)
                 },
                 duration_ms=duration,
                 records_processed=len(history_records))
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении исторических данных остатков',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@stocks_history_bp.route('/stocks-history/<int:nm_id>', methods=['GET'])
@jwt_required()
def get_stocks_history_by_nm_id(nm_id):
    """Получить исторические данные остатков по конкретному товару"""
    start_time = time.time()
    method_name = "get_stocks_history_by_nm_id"
    
    try:
        log_event('INFO', method_name, f'Запрос исторических данных остатков для nm_id {nm_id}')
        
        limit = request.args.get('limit', 10000, type=int)
        days = request.args.get('days', type=int)
        
        if limit > 20000:
            limit = 20000
        
        query = StocksHistory.query.filter_by(nm_id=nm_id)
        
        if days:
            date_from = datetime.utcnow() - timedelta(days=days)
            query = query.filter(StocksHistory.created_at >= date_from)
        
        query = query.order_by(StocksHistory.created_at.desc())
        history_records = query.limit(limit).all()
        
        if not history_records:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Исторические данные для nm_id {nm_id} не найдены',
                     duration_ms=duration)
            return jsonify({
                'nm_id': nm_id,
                'message': 'Исторические данные не найдены',
                'history': []
            }), 404
        
        product = UnifiedProduct.query.filter_by(nm_id=nm_id).first()
        product_info = product.to_dict() if product else None
        
        result = {
            'nm_id': nm_id,
            'product_info': product_info,
            'history': [record.to_dict() for record in history_records],
            'total_records': len(history_records),
            'filters': {
                'limit': limit,
                'days': days
            }
        }
        
        if history_records:
            total_quantities = [record.total_quantity for record in history_records]
            fbs_quantities = [record.fbs_quantity for record in history_records]
            
            result['statistics'] = {
                'total_quantity': {
                    'min': min(total_quantities) if total_quantities else 0,
                    'max': max(total_quantities) if total_quantities else 0,
                    'avg': sum(total_quantities) / len(total_quantities) if total_quantities else 0,
                    'current': total_quantities[0] if total_quantities else 0
                },
                'fbs_quantity': {
                    'min': min(fbs_quantities) if fbs_quantities else 0,
                    'max': max(fbs_quantities) if fbs_quantities else 0,
                    'avg': sum(fbs_quantities) / len(fbs_quantities) if fbs_quantities else 0,
                    'current': fbs_quantities[0] if fbs_quantities else 0
                }
            }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Успешный возврат исторических данных для nm_id {nm_id}',
                 {'records_count': len(history_records)}, duration_ms=duration)
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка при получении исторических данных для nm_id {nm_id}',
                 {'nm_id': nm_id, 'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@stocks_history_bp.route('/stocks-history/manual-snapshot', methods=['GET'])
@jwt_required()
def create_manual_snapshot():
    """Создание ручного снимка остатков через GET запрос"""
    start_time = time.time()
    method_name = "create_manual_snapshot"
    
    try:
        log_event('INFO', method_name, 'GET запрос на создание ручного снимка остатков')
        create_stocks_snapshot()
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Ручное создание снимка остатков через GET завершено',
                 duration_ms=duration)
        return jsonify({"status": "Снэпшот сделан"})
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при ручном создании снимка остатков через GET',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500