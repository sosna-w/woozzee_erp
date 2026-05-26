import time
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from sqlalchemy import func

from models import db, Subject, Product
from utils.logger import log_event
from services.subject_service import fetch_all_subjects

subject_bp = Blueprint('subject', __name__)


@subject_bp.route('/update-subjects', methods=['GET'])
@jwt_required()
def update_subjects_endpoint():
    """Ручной запуск обновления списка предметов"""
    start_time = time.time()
    method_name = "update_subjects_endpoint"
    
    try:
        log_event('INFO', method_name, 'Ручной запуск обновления предметов')
        fetch_all_subjects()
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Ручное обновление предметов завершено', duration_ms=duration)
        return jsonify({"status": "Subjects update started"})
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при ручном обновлении предметов',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@subject_bp.route('/subject/name/<int:subject_id>', methods=['GET'])
@jwt_required()
def get_subject_name_by_id(subject_id):
    """Получить только название предмета по subjectID"""
    start_time = time.time()
    method_name = "get_subject_name_by_id"
    
    try:
        log_event('INFO', method_name, f'Запрос названия предмета по subjectID {subject_id}')
        
        subject = Subject.query.filter_by(subject_id=subject_id).first()
        
        if not subject:
            product = Product.query.filter_by(subjectID=subject_id).first()
            if product:
                result = {
                    'subject_id': subject_id,
                    'subject_name': product.subjectName,
                    'source': 'products_table',
                    'message': 'Название найдено в таблице товаров'
                }
            else:
                result = {
                    'subject_id': subject_id,
                    'subject_name': None,
                    'message': 'Предмет не найден'
                }
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Предмет с subjectID {subject_id} не найден', duration_ms=duration)
            return jsonify(result), 404
        
        result = {
            'subject_id': subject.subject_id,
            'subject_name': subject.subject_name,
            'parent_id': subject.parent_id,
            'parent_name': subject.parent_name,
            'source': 'subjects_table'
        }
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Успешный возврат названия предмета subjectID {subject_id}', duration_ms=duration)
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка при получении названия предмета subjectID {subject_id}',
                 {'subject_id': subject_id, 'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@subject_bp.route('/subject/<int:subject_id>', methods=['GET'])
@jwt_required()
def get_subject_by_id(subject_id):
    """Получить информацию о предмете по subjectID"""
    start_time = time.time()
    method_name = "get_subject_by_id"
    
    try:
        log_event('INFO', method_name, f'Запрос предмета по subjectID {subject_id}')
        
        subject = Subject.query.filter_by(subject_id=subject_id).first()
        
        if not subject:
            product = Product.query.filter_by(subjectID=subject_id).first()
            if product:
                result = {
                    'subject_id': subject_id,
                    'subject_name': product.subjectName,
                    'message': 'Предмет не найден в базе предметов, но есть товары с таким subjectID',
                    'product_info': {
                        'nmID': product.nmID,
                        'vendorCode': product.vendorCode,
                        'brand': product.brand,
                        'title': product.title
                    }
                }
            else:
                result = {
                    'subject_id': subject_id,
                    'message': 'Предмет не найден в базе данных'
                }
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Предмет с subjectID {subject_id} не найден', duration_ms=duration)
            return jsonify(result), 404
        
        result = subject.to_dict()
        product_count = Product.query.filter_by(subjectID=subject_id).count()
        result['product_count'] = product_count
        
        if product_count > 0:
            sample_products = Product.query.filter_by(subjectID=subject_id).limit(3).all()
            result['sample_products'] = [
                {
                    'nmID': p.nmID,
                    'vendorCode': p.vendorCode,
                    'brand': p.brand,
                    'title': p.title[:100] + '...' if len(p.title) > 100 else p.title
                } for p in sample_products
            ]
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Успешный возврат предмета subjectID {subject_id}', duration_ms=duration)
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка при получении предмета subjectID {subject_id}',
                 {'subject_id': subject_id, 'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@subject_bp.route('/subjects', methods=['GET'])
@jwt_required()
def get_all_subjects():
    """Получить список всех предметов с пагинацией и фильтрацией"""
    start_time = time.time()
    method_name = "get_all_subjects"
    
    try:
        log_event('INFO', method_name, 'Запрос списка предметов')
        
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 100, type=int)
        parent_id = request.args.get('parent_id', type=int)
        search = request.args.get('search', '')
        
        query = Subject.query
        
        if parent_id:
            query = query.filter(Subject.parent_id == parent_id)
        if search:
            query = query.filter(
                db.or_(
                    Subject.subject_name.ilike(f'%{search}%'),
                    Subject.parent_name.ilike(f'%{search}%')
                )
            )
        
        query = query.order_by(Subject.parent_id, Subject.subject_name)
        pagination = query.paginate(page=page, per_page=per_page, error_out=False)
        subjects = pagination.items
        
        result = {
            'subjects': [subject.to_dict() for subject in subjects],
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
                'search': search
            }
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат списка предметов',
                 {
                     'page': page,
                     'per_page': per_page,
                     'total_items': pagination.total,
                     'returned_items': len(subjects)
                 },
                 duration_ms=duration,
                 records_processed=len(subjects))
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении списка предметов',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500