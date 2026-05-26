import json
import time
from datetime import datetime
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from models import db, Warehouse, WarehouseConfig, WarehouseMapping
from utils.logger import log_event
from services.product_service import fetch_warehouses

warehouse_bp = Blueprint('warehouse', __name__)


@warehouse_bp.route('/warehouses', methods=['GET'])
@jwt_required()
def get_warehouses():
    start_time = time.time()
    method_name = "get_warehouses"
    
    try:
        log_event('INFO', method_name, 'Запрос списка складов')
        
        show_deleting = request.args.get('show_deleting', 'false').lower() == 'true'
        
        query = Warehouse.query
        
        if not show_deleting:
            query = query.filter(Warehouse.is_deleting == False)
        
        warehouses = query.order_by(Warehouse.name).all()
        
        result = [warehouse.to_dict() for warehouse in warehouses]
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат списка складов',
                 {'warehouses_count': len(result), 'show_deleting': show_deleting},
                 duration_ms=duration, records_processed=len(result))
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении списка складов',
                 {'error': str(e)},
                 duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@warehouse_bp.route('/update-warehouses', methods=['GET'])
@jwt_required()
def update_warehouses():
    start_time = time.time()
    method_name = "update_warehouses"
    
    try:
        log_event('INFO', method_name, 'Ручной запуск обновления складов')
        fetch_warehouses()
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Ручное обновление складов завершено',
                 duration_ms=duration)
        return jsonify({"status": "Warehouses update started"})
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при ручном обновлении складов',
                 {'error': str(e)},
                 duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@warehouse_bp.route('/warehouses/<int:warehouse_id>', methods=['GET'])
@jwt_required()
def get_warehouse(warehouse_id):
    start_time = time.time()
    method_name = "get_warehouse"
    
    try:
        log_event('INFO', method_name, f'Запрос склада ID {warehouse_id}')
        
        warehouse = Warehouse.query.filter_by(warehouse_id=warehouse_id).first()
        
        if not warehouse:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Склад ID {warehouse_id} не найден',
                     duration_ms=duration)
            return jsonify({"error": "Warehouse not found"}), 404
        
        result = warehouse.to_dict()
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Успешный возврат склада ID {warehouse_id}',
                 duration_ms=duration)
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка при получении склада ID {warehouse_id}',
                 {'warehouse_id': warehouse_id, 'error': str(e)},
                 duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@warehouse_bp.route('/warehouse-config', methods=['GET', 'POST'])
@jwt_required()
def handle_warehouse_config():
    start_time = time.time()
    method_name = "handle_warehouse_config"
    
    try:
        if request.method == 'GET':
            log_event('INFO', method_name, 'Запрос конфигурации складов')
            
            config = WarehouseConfig.query.first()
            if config:
                result = config.to_dict()
                duration = (time.time() - start_time) * 1000
                log_event('INFO', method_name, 'Конфигурация складов найдена',
                         duration_ms=duration)
                return jsonify(result)
            else:
                default_config = WarehouseConfig(
                    mode='uniform',
                    uniform_threshold=0,
                    uniform_minimum=0,
                    individual_config='{}'
                )
                db.session.add(default_config)
                db.session.commit()
                
                result = default_config.to_dict()
                duration = (time.time() - start_time) * 1000
                log_event('INFO', method_name, 'Создана конфигурация складов по умолчанию',
                         duration_ms=duration)
                return jsonify(result)
                
        elif request.method == 'POST':
            log_event('INFO', method_name, 'Сохранение конфигурации складов')
            data = request.get_json()
            
            config = WarehouseConfig.query.first()
            if not config:
                config = WarehouseConfig()
                db.session.add(config)
            
            config.mode = data.get('mode', 'uniform')
            config.uniform_threshold = data.get('uniform_threshold', 0)
            config.uniform_minimum = data.get('uniform_minimum', 0)
            
            individual_config = data.get('individual_config', {})
            config.individual_config = json.dumps(individual_config, ensure_ascii=False)
            
            config.updated_at = datetime.utcnow()
            db.session.commit()
            
            duration = (time.time() - start_time) * 1000
            log_event('INFO', method_name, 'Конфигурация складов успешно сохранена',
                     {'mode': config.mode},
                     duration_ms=duration)
            
            return jsonify({"status": "success", "config": config.to_dict()})
            
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при работе с конфигурацией складов',
                 {'error': str(e)},
                 duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@warehouse_bp.route('/warehouse-config/<int:warehouse_id>', methods=['GET'])
@jwt_required()
def get_warehouse_config(warehouse_id):
    start_time = time.time()
    method_name = "get_warehouse_config"
    
    try:
        log_event('INFO', method_name, f'Запрос конфигурации склада {warehouse_id}')
        
        config = WarehouseConfig.query.first()
        if not config:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, 'Конфигурация складов не найдена',
                     duration_ms=duration)
            return jsonify({"error": "Warehouse config not found"}), 404
        
        individual_config = json.loads(config.individual_config) if config.individual_config else {}
        warehouse_config = individual_config.get(str(warehouse_id), {})
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Конфигурация склада {warehouse_id} возвращена',
                 duration_ms=duration)
        
        return jsonify(warehouse_config)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка при получении конфигурации склада {warehouse_id}',
                 {'warehouse_id': warehouse_id, 'error': str(e)},
                 duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@warehouse_bp.route('/warehouse-mapping', methods=['GET'])
@jwt_required()
def get_warehouse_mapping():
    """Возвращает весь список маппинга складов"""
    try:
        mappings = WarehouseMapping.query.order_by(WarehouseMapping.id).all()
        return jsonify([m.to_dict() for m in mappings])
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@warehouse_bp.route('/warehouse-mapping', methods=['POST'])
@jwt_required()
def add_warehouse_mapping():
    """Добавляет новую запись маппинга"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No data provided"}), 400
        
        required = ['wh_name_wb_api_warehouses', 'wh_name_my_api_warehouse_remains', 'wh_name_my_api_order_feed']
        for field in required:
            if field not in data:
                return jsonify({"error": f"Missing field: {field}"}), 400
        
        mapping = WarehouseMapping(
            wh_name_wb_api_warehouses=data['wh_name_wb_api_warehouses'],
            wh_name_my_api_warehouse_remains=data['wh_name_my_api_warehouse_remains'],
            wh_name_my_api_order_feed=data['wh_name_my_api_order_feed']
        )
        db.session.add(mapping)
        db.session.commit()
        return jsonify(mapping.to_dict()), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500


@warehouse_bp.route('/warehouse-mapping/<int:id>', methods=['DELETE'])
@jwt_required()
def delete_warehouse_mapping(id):
    """Удаляет запись маппинга по ID"""
    try:
        mapping = WarehouseMapping.query.get(id)
        if not mapping:
            return jsonify({"error": "Mapping not found"}), 404
        db.session.delete(mapping)
        db.session.commit()
        return jsonify({"status": "deleted", "id": id})
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500


@warehouse_bp.route('/warehouse-mapping/<int:id>', methods=['PUT'])
@jwt_required()
def update_warehouse_mapping(id):
    """Обновить запись маппинга по ID"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No data provided"}), 400

        mapping = WarehouseMapping.query.get(id)
        if not mapping:
            return jsonify({"error": "Mapping not found"}), 404

        if 'wh_name_wb_api_warehouses' in data:
            mapping.wh_name_wb_api_warehouses = data['wh_name_wb_api_warehouses']
        if 'wh_name_my_api_warehouse_remains' in data:
            mapping.wh_name_my_api_warehouse_remains = data['wh_name_my_api_warehouse_remains']
        if 'wh_name_my_api_order_feed' in data:
            mapping.wh_name_my_api_order_feed = data['wh_name_my_api_order_feed']

        db.session.commit()
        return jsonify(mapping.to_dict())
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500