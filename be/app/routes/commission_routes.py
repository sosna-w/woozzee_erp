import time
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from sqlalchemy import func

from models import db, Commission, Product
from utils.logger import log_event
from services.commission_service import fetch_commissions

commission_bp = Blueprint('commission', __name__)


@commission_bp.route('/commissions', methods=['GET'])
@jwt_required()
def get_all_commissions():
    start_time = time.time()
    method_name = "get_all_commissions"
    
    try:
        log_event('INFO', method_name, 'Запрос всех комиссий')
        
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 100, type=int)
        parent_id = request.args.get('parent_id', type=int)
        subject_id = request.args.get('subject_id', type=int)
        search = request.args.get('search', '')
        
        query = Commission.query
        
        if parent_id:
            query = query.filter(Commission.parentID == parent_id)
        if subject_id:
            query = query.filter(Commission.subjectID == subject_id)
        if search:
            query = query.filter(
                db.or_(
                    Commission.parentName.ilike(f'%{search}%'),
                    Commission.subjectName.ilike(f'%{search}%')
                )
            )
        
        query = query.order_by(Commission.parentID, Commission.subjectID)
        
        pagination = query.paginate(page=page, per_page=per_page, error_out=False)
        commissions = pagination.items
        
        result = {
            'commissions': [commission.to_dict() for commission in commissions],
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            },
            'filters': {
                'parent_id': parent_id,
                'subject_id': subject_id,
                'search': search
            }
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат всех комиссий',
                 {
                     'page': page,
                     'per_page': per_page,
                     'total_items': pagination.total,
                     'returned_items': len(commissions)
                 },
                 duration_ms=duration,
                 records_processed=len(commissions))
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении комиссий',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@commission_bp.route('/commissions/subject/<int:subject_id>', methods=['GET'])
@jwt_required()
def get_commission_by_subject_id(subject_id):
    start_time = time.time()
    method_name = "get_commission_by_subject_id"
    
    try:
        log_event('INFO', method_name, f'Запрос комиссии по subjectID {subject_id}')
        
        commission = Commission.query.filter_by(subjectID=subject_id).first()
        
        if not commission:
            product = Product.query.filter_by(subjectID=subject_id).first()
            if product:
                result = {
                    'subjectID': subject_id,
                    'subjectName': product.subjectName,
                    'message': 'Комиссия не найдена в базе, но товар с таким subjectID существует',
                    'product_info': {
                        'nmID': product.nmID,
                        'vendorCode': product.vendorCode,
                        'brand': product.brand,
                        'title': product.title
                    }
                }
            else:
                result = {
                    'subjectID': subject_id,
                    'message': 'Комиссия не найдена в базе'
                }
            
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Комиссия для subjectID {subject_id} не найдена',
                     duration_ms=duration)
            return jsonify(result), 404
        
        result = commission.to_dict()
        
        related_products = Product.query.filter_by(subjectID=subject_id).limit(5).all()
        result['related_products'] = [
            {
                'nmID': p.nmID,
                'vendorCode': p.vendorCode,
                'brand': p.brand,
                'title': p.title[:100] + '...' if len(p.title) > 100 else p.title
            } for p in related_products
        ]
        result['related_products_count'] = Product.query.filter_by(subjectID=subject_id).count()
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Успешный возврат комиссии для subjectID {subject_id}',
                 duration_ms=duration)
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка при получении комиссии для subjectID {subject_id}',
                 {'subject_id': subject_id, 'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@commission_bp.route('/commissions/parent/<int:parent_id>', methods=['GET'])
@jwt_required()
def get_commissions_by_parent_id(parent_id):
    start_time = time.time()
    method_name = "get_commissions_by_parent_id"
    
    try:
        log_event('INFO', method_name, f'Запрос комиссий по parentID {parent_id}')
        
        commissions = Commission.query.filter_by(parentID=parent_id).order_by(Commission.subjectID).all()
        
        if not commissions:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Комиссии для parentID {parent_id} не найдены',
                     duration_ms=duration)
            return jsonify({
                'parentID': parent_id,
                'message': 'Комиссии не найдены в базе'
            }), 404
        
        result = {
            'parentID': parent_id,
            'parentName': commissions[0].parentName if commissions else '',
            'commissions': [commission.to_dict() for commission in commissions],
            'total_subjects': len(commissions)
        }
        
        if commissions:
            commission_fields = ['kgvpBooking', 'kgvpMarketplace', 'kgvpPickup', 
                               'kgvpSupplier', 'kgvpSupplierExpress', 'paidStorageKgvp']
            stats = {}
            for field in commission_fields:
                values = [getattr(c, field) for c in commissions if getattr(c, field) is not None]
                if values:
                    stats[field] = {
                        'min': min(values),
                        'max': max(values),
                        'avg': sum(values) / len(values)
                    }
            result['statistics'] = stats
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Успешный возврат комиссий для parentID {parent_id}',
                 {'count': len(commissions)}, duration_ms=duration)
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка при получении комиссий для parentID {parent_id}',
                 {'parent_id': parent_id, 'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@commission_bp.route('/commissions/stats', methods=['GET'])
@jwt_required()
def get_commissions_stats():
    start_time = time.time()
    method_name = "get_commissions_stats"
    
    try:
        log_event('INFO', method_name, 'Запрос статистики по комиссиям')
        
        total_commissions = Commission.query.count()
        unique_parents = db.session.query(func.count(func.distinct(Commission.parentID))).scalar()
        unique_subjects = db.session.query(func.count(func.distinct(Commission.subjectID))).scalar()
        
        parent_stats = db.session.query(
            Commission.parentID,
            Commission.parentName,
            func.count(Commission.id).label('subject_count')
        ).group_by(Commission.parentID, Commission.parentName).order_by(func.count(Commission.id).desc()).all()
        
        avg_stats = {}
        commission_fields = ['kgvpBooking', 'kgvpMarketplace', 'kgvpPickup', 
                           'kgvpSupplier', 'kgvpSupplierExpress', 'paidStorageKgvp']
        
        for field in commission_fields:
            avg_value = db.session.query(func.avg(getattr(Commission, field))).scalar()
            avg_stats[field] = round(avg_value, 2) if avg_value else 0
        
        result = {
            'total_commissions': total_commissions,
            'unique_parent_categories': unique_parents,
            'unique_subjects': unique_subjects,
            'average_commissions': avg_stats,
            'parent_categories': [
                {
                    'parentID': parent_id,
                    'parentName': parent_name,
                    'subject_count': subject_count
                } for parent_id, parent_name, subject_count in parent_stats
            ],
            'last_updated': None
        }
        
        last_commission = Commission.query.order_by(Commission.updated_at.desc()).first()
        if last_commission and last_commission.updated_at:
            result['last_updated'] = last_commission.updated_at.isoformat()
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат статистики по комиссиям',
                 duration_ms=duration)
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении статистики по комиссиям',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@commission_bp.route('/update-commissions', methods=['GET'])
@jwt_required()
def update_commissions_endpoint():
    start_time = time.time()
    method_name = "update_commissions_endpoint"
    
    try:
        log_event('INFO', method_name, 'Ручной запуск обновления комиссий')
        fetch_commissions()
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Ручное обновление комиссий завершено',
                 duration_ms=duration)
        return jsonify({"status": "Commissions update started"})
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при ручном обновлении комиссий',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500