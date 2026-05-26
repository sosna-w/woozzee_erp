import json
import time
import threading
from datetime import datetime, timedelta
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from sqlalchemy import func

from models import db, AutoReplenishmentConfig, TagConfig, ProductAutoConfig, UnifiedProduct, WarehouseConfig, Warehouse, FBSStock
from utils.logger import log_event
from utils.token_manager import get_api_key
from services.auto_replenishment_service import auto_replenish_stocks, log_auto_replenishment_debug
from services.product_service import _update_stocks_via_api

auto_replenishment_bp = Blueprint('auto_replenishment', __name__)


# ========== КОНФИГУРАЦИЯ АВТООБНОВЛЕНИЯ ==========

@auto_replenishment_bp.route('/auto-replenishment-config', methods=['GET', 'POST'])
@jwt_required()
def handle_auto_replenishment_config():
    start_time = time.time()
    method_name = "handle_auto_replenishment_config"
    
    try:
        if request.method == 'GET':
            log_event('INFO', method_name, 'Запрос конфигурации автообновления')
            config = AutoReplenishmentConfig.query.first()
            if config:
                result = config.to_dict()
            else:
                config = AutoReplenishmentConfig()
                db.session.add(config)
                db.session.commit()
                result = config.to_dict()
            
            duration = (time.time() - start_time) * 1000
            log_event('INFO', method_name, 'Конфигурация автообновления найдена', duration_ms=duration)
            return jsonify(result)
            
        elif request.method == 'POST':
            log_event('INFO', method_name, 'Сохранение конфигурации автообновления')
            data = request.get_json()
            
            config = AutoReplenishmentConfig.query.first()
            if not config:
                config = AutoReplenishmentConfig()
                db.session.add(config)
            
            config.enabled = data.get('enabled', False)
            config.interval_minutes = data.get('interval_minutes', 15)
            config.batch_size = data.get('batch_size', 100)
            config.updated_at = datetime.utcnow()
            
            db.session.commit()
            
            duration = (time.time() - start_time) * 1000
            log_event('INFO', method_name, 'Конфигурация автообновления сохранена',
                     {'enabled': config.enabled, 'interval_minutes': config.interval_minutes},
                     duration_ms=duration)
            
            return jsonify({"status": "success", "config": config.to_dict()})
            
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при работе с конфигурацией автообновления',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


# ========== КОНФИГУРАЦИЯ ТЕГОВ ==========

@auto_replenishment_bp.route('/tag-config', methods=['GET', 'POST'])
@jwt_required()
def handle_tag_config():
    start_time = time.time()
    method_name = "handle_tag_config"
    
    try:
        if request.method == 'GET':
            log_event('INFO', method_name, 'Запрос конфигурации тегов')
            configs = TagConfig.query.all()
            result = {config.tag_name: config.to_dict() for config in configs}
            duration = (time.time() - start_time) * 1000
            log_event('INFO', method_name, 'Конфигурация тегов найдена',
                     {'configs_count': len(result)}, duration_ms=duration)
            return jsonify(result)
            
        elif request.method == 'POST':
            log_event('INFO', method_name, 'Сохранение конфигурации тегов')
            data = request.get_json()
            
            for tag_name, config_data in data.items():
                tag_config = TagConfig.query.filter_by(tag_name=tag_name).first()
                
                if tag_config:
                    tag_config.behavior = config_data.get('behavior', 'as_warehouse')
                    tag_config.fixed_amount = config_data.get('fixed_amount', 0)
                    tag_config.updated_at = datetime.utcnow()
                else:
                    tag_config = TagConfig(
                        tag_name=tag_name,
                        behavior=config_data.get('behavior', 'as_warehouse'),
                        fixed_amount=config_data.get('fixed_amount', 0)
                    )
                    db.session.add(tag_config)
            
            db.session.commit()
            duration = (time.time() - start_time) * 1000
            log_event('INFO', method_name, 'Конфигурация тегов успешно сохранена',
                     {'updated_tags_count': len(data)}, duration_ms=duration)
            
            return jsonify({"status": "success", "updated_count": len(data)})
            
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при работе с конфигурацией тегов',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


# ========== ИНДИВИДУАЛЬНЫЕ КОНФИГУРАЦИИ ТОВАРОВ ==========

@auto_replenishment_bp.route('/product-auto-config', methods=['GET'])
@jwt_required()
def get_all_product_auto_config():
    start_time = time.time()
    method_name = "get_all_product_auto_config"
    
    try:
        log_event('INFO', method_name, 'Запрос всех товаров из ProductAutoConfig')
        
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 100, type=int)
        nm_id_filter = request.args.get('nm_id', type=int)
        
        query = ProductAutoConfig.query
        if nm_id_filter:
            query = query.filter(ProductAutoConfig.nm_id == nm_id_filter)
        
        pagination = query.paginate(page=page, per_page=per_page, error_out=False)
        configs = pagination.items
        
        result = {
            'product_auto_configs': [config.to_dict() for config in configs],
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            }
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат всех товаров из ProductAutoConfig',
                 {
                     'page': page,
                     'per_page': per_page,
                     'total_items': pagination.total,
                     'returned_items': len(configs)
                 },
                 duration_ms=duration,
                 records_processed=len(configs))
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении товаров из ProductAutoConfig',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@auto_replenishment_bp.route('/product-auto-config/<int:nm_id>', methods=['GET'])
@jwt_required()
def get_product_auto_config(nm_id):
    start_time = time.time()
    method_name = "get_product_auto_config"
    
    try:
        log_event('INFO', method_name, f'Запрос товара из ProductAutoConfig nm_id {nm_id}')
        config = ProductAutoConfig.query.filter_by(nm_id=nm_id).first()
        
        if not config:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Товар nm_id {nm_id} не найден в ProductAutoConfig',
                     duration_ms=duration)
            return jsonify({"error": "Product not found in ProductAutoConfig"}), 404
        
        result = config.to_dict()
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Успешный возврат товара nm_id {nm_id} из ProductAutoConfig',
                 duration_ms=duration)
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка при получении товара nm_id {nm_id} из ProductAutoConfig',
                 {'nm_id': nm_id, 'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@auto_replenishment_bp.route('/product-auto-config', methods=['POST'])
@jwt_required()
def add_product_auto_config():
    start_time = time.time()
    method_name = "add_product_auto_config"
    
    try:
        log_event('INFO', method_name, 'Добавление товара в ProductAutoConfig')
        data = request.get_json()
        
        if not data or 'nm_id' not in data:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, 'Неверные данные запроса - отсутствует nm_id',
                     {'data': data}, duration_ms=duration)
            return jsonify({"error": "nm_id is required"}), 400
        
        nm_id = data['nm_id']
        existing_config = ProductAutoConfig.query.filter_by(nm_id=nm_id).first()
        
        if existing_config:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Товар nm_id {nm_id} уже существует в ProductAutoConfig',
                     duration_ms=duration)
            return jsonify({"error": f"Product with nm_id {nm_id} already exists"}), 409
        
        config = ProductAutoConfig(
            nm_id=nm_id,
            fbo_threshold=data.get('fbo_threshold'),
            fbs_minimum=data.get('fbs_minimum'),
            ignore_auto_replenishment=data.get('ignore_auto_replenishment', False)
        )
        db.session.add(config)
        db.session.commit()
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Товар nm_id {nm_id} успешно добавлен в ProductAutoConfig',
                 {
                     'nm_id': nm_id,
                     'fbo_threshold': config.fbo_threshold,
                     'fbs_minimum': config.fbs_minimum,
                     'ignore_auto_replenishment': config.ignore_auto_replenishment
                 },
                 duration_ms=duration)
        
        return jsonify({
            "status": "success", 
            "message": f"Product with nm_id {nm_id} added to ProductAutoConfig",
            "config": config.to_dict()
        })
        
    except Exception as e:
        db.session.rollback()
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при добавлении товара в ProductAutoConfig',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@auto_replenishment_bp.route('/product-auto-config/<int:nm_id>', methods=['PUT'])
@jwt_required()
def update_product_auto_config(nm_id):
    start_time = time.time()
    method_name = "update_product_auto_config"
    
    try:
        log_event('INFO', method_name, f'Обновление товара nm_id {nm_id} в ProductAutoConfig')
        data = request.get_json()
        
        config = ProductAutoConfig.query.filter_by(nm_id=nm_id).first()
        if not config:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Товар nm_id {nm_id} не найден в ProductAutoConfig',
                     duration_ms=duration)
            return jsonify({"error": "Product not found in ProductAutoConfig"}), 404
        
        if 'fbo_threshold' in data:
            config.fbo_threshold = data['fbo_threshold']
        if 'fbs_minimum' in data:
            config.fbs_minimum = data['fbs_minimum']
        if 'ignore_auto_replenishment' in data:
            config.ignore_auto_replenishment = data['ignore_auto_replenishment']
        
        config.updated_at = datetime.utcnow()
        db.session.commit()
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Товар nm_id {nm_id} успешно обновлен в ProductAutoConfig',
                 {
                     'fbo_threshold': config.fbo_threshold,
                     'fbs_minimum': config.fbs_minimum,
                     'ignore_auto_replenishment': config.ignore_auto_replenishment
                 },
                 duration_ms=duration)
        
        return jsonify({
            "status": "success", 
            "message": f"Product with nm_id {nm_id} updated in ProductAutoConfig",
            "config": config.to_dict()
        })
        
    except Exception as e:
        db.session.rollback()
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка при обновлении товара nm_id {nm_id} в ProductAutoConfig',
                 {'nm_id': nm_id, 'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@auto_replenishment_bp.route('/product-auto-config/<int:nm_id>', methods=['DELETE'])
@jwt_required()
def delete_product_auto_config(nm_id):
    start_time = time.time()
    method_name = "delete_product_auto_config"
    
    try:
        log_event('INFO', method_name, f'Удаление товара nm_id {nm_id} из ProductAutoConfig')
        config = ProductAutoConfig.query.filter_by(nm_id=nm_id).first()
        
        if not config:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Товар nm_id {nm_id} не найден в ProductAutoConfig',
                     duration_ms=duration)
            return jsonify({"error": "Product not found in ProductAutoConfig"}), 404
        
        db.session.delete(config)
        db.session.commit()
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Товар nm_id {nm_id} успешно удален из ProductAutoConfig',
                 duration_ms=duration)
        
        return jsonify({
            "status": "success", 
            "message": f"Product with nm_id {nm_id} deleted from ProductAutoConfig"
        })
        
    except Exception as e:
        db.session.rollback()
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка при удалении товара nm_id {nm_id} из ProductAutoConfig',
                 {'nm_id': nm_id, 'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@auto_replenishment_bp.route('/debug/product-auto-config-status', methods=['GET'])
@jwt_required()
def debug_product_auto_config_status():
    """Диагностическая ручка для проверки статуса индивидуальных конфигураций товаров"""
    try:
        product_auto_configs = ProductAutoConfig.query.all()
        configured_products = []
        
        for config in product_auto_configs:
            product = UnifiedProduct.query.filter_by(nm_id=config.nm_id).first()
            configured_products.append({
                'nm_id': config.nm_id,
                'vendor_code': product.vendor_code if product else 'N/A',
                'title': product.title if product else 'N/A',
                'fbo_threshold': config.fbo_threshold,
                'fbs_minimum': config.fbs_minimum,
                'ignore_auto_replenishment': config.ignore_auto_replenishment,
                'current_stock': product.total_quantity if product else 0,
                'has_product': product is not None
            })
        
        active_configs = [c for c in configured_products if not c['ignore_auto_replenishment']]
        ignored_configs = [c for c in configured_products if c['ignore_auto_replenishment']]
        
        status = {
            'total_individual_configs': len(product_auto_configs),
            'active_configs': len(active_configs),
            'ignored_configs': len(ignored_configs),
            'configs_with_fbo_threshold': len([c for c in product_auto_configs if c.fbo_threshold is not None]),
            'configs_with_fbs_minimum': len([c for c in product_auto_configs if c.fbs_minimum is not None]),
            'configured_products': configured_products,
            'system_time': datetime.utcnow().isoformat()
        }
        return jsonify(status)
        
    except Exception as e:
        log_event('ERROR', 'debug_product_auto_config_status', 'Ошибка при получении статуса индивидуальных конфигураций',
                 {'error': str(e)})
        return jsonify({"error": str(e)}), 500


# ========== РУЧНОЙ ЗАПУСК И ТЕСТИРОВАНИЕ ==========

@auto_replenishment_bp.route('/run-auto-replenishment', methods=['GET'])
@jwt_required()
def run_auto_replenishment():
    start_time = time.time()
    method_name = "run_auto_replenishment"
    
    try:
        log_event('INFO', method_name, 'Ручной запуск автообновления остатков')
        auto_replenish_stocks()
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Ручное автообновление завершено', duration_ms=duration)
        return jsonify({"status": "Auto replenishment completed"})
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при ручном автообновлении', {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@auto_replenishment_bp.route('/test-auto-replenishment', methods=['GET'])
@jwt_required()
def test_auto_replenishment():
    """Ручка для тестирования автообновления без фактического обновления в WB"""
    try:
        log_event('INFO', 'test_auto_replenishment', 'Начало тестового автообновления')
        
        config = AutoReplenishmentConfig.query.first()
        if not config or not config.enabled:
            return jsonify({"status": "disabled", "message": "Автообновление отключено в настройках"})
        
        warehouse_config = WarehouseConfig.query.first()
        if not warehouse_config:
            return jsonify({"status": "error", "message": "Конфигурация складов не найдена"})
        
        threshold = warehouse_config.uniform_threshold
        unified_products = UnifiedProduct.query.all()
        
        tag_configs = TagConfig.query.all()
        tag_config_dict = {c.tag_name: c for c in tag_configs}
        
        products_analysis = []
        for product in unified_products:
            if not product.barcode:
                continue
                
            product_tags = []
            if product.tags:
                try:
                    tags_data = json.loads(product.tags)
                    for tag in tags_data:
                        if isinstance(tag, dict) and 'name' in tag:
                            product_tags.append(tag['name'])
                except json.JSONDecodeError:
                    pass
            
            skip_product = False
            fixed_amount = None
            for tag_name in product_tags:
                if tag_name in tag_config_dict:
                    tag_config = tag_config_dict[tag_name]
                    behavior = tag_config.behavior
                    if behavior == 'always_zero' or behavior == 'ignore':
                        skip_product = True
                        break
                    elif behavior == 'always_n':
                        fixed_amount = tag_config.fixed_amount
                        break
            
            if skip_product:
                products_analysis.append({
                    'nm_id': product.nm_id,
                    'vendor_code': product.vendor_code,
                    'current_stock': product.total_quantity,
                    'action': 'skip',
                    'reason': 'tag_behavior',
                    'tags': product_tags
                })
                continue
            
            action = 'no_action'
            amount = 0
            if fixed_amount is not None:
                action = 'update'
                amount = fixed_amount
            elif product.total_quantity < threshold:
                action = 'update'
                amount = config.batch_size
            
            products_analysis.append({
                'nm_id': product.nm_id,
                'vendor_code': product.vendor_code,
                'current_stock': product.total_quantity,
                'action': action,
                'update_amount': amount,
                'reason': 'fixed_amount_tag' if fixed_amount is not None else ('below_threshold' if action == 'update' else ''),
                'tags': product_tags
            })
        
        total_products = len(products_analysis)
        to_update = len([p for p in products_analysis if p['action'] == 'update'])
        to_skip = len([p for p in products_analysis if p['action'] == 'skip'])
        no_action = len([p for p in products_analysis if p['action'] == 'no_action'])
        
        result = {
            "status": "test_completed",
            "message": f"Проанализировано {total_products} товаров: {to_update} к обновлению, {to_skip} пропущено, {no_action} без действий",
            "analysis": {
                "total_products": total_products,
                "to_update": to_update,
                "to_skip": to_skip,
                "no_action": no_action,
                "threshold": threshold,
                "batch_size": config.batch_size
            },
            "products_sample": products_analysis[:20]
        }
        return jsonify(result)
        
    except Exception as e:
        log_event('ERROR', 'test_auto_replenishment', 'Ошибка тестового автообновления', {'error': str(e)})
        return jsonify({"status": "error", "error": str(e)}), 500


@auto_replenishment_bp.route('/debug/auto-replenishment-status', methods=['GET'])
@jwt_required()
def debug_auto_replenishment_status():
    """Диагностическая ручка для проверки статуса автообновления"""
    try:
        config = AutoReplenishmentConfig.query.first()
        warehouse_config = WarehouseConfig.query.first()
        
        warehouses = Warehouse.query.all()
        individual_configs = json.loads(warehouse_config.individual_config) if warehouse_config and warehouse_config.individual_config else {}
        
        active_warehouses = []
        for warehouse in warehouses:
            warehouse_key = str(warehouse.warehouse_id)
            config_data = individual_configs.get(warehouse_key, {})
            if config_data.get('is_activate', True):
                active_warehouses.append(warehouse)
        
        tag_configs = TagConfig.query.all()
        unified_products = UnifiedProduct.query.all()
        products_with_barcode = [p for p in unified_products if p.barcode]
        threshold = warehouse_config.uniform_threshold if warehouse_config else 0
        products_below_threshold = [p for p in unified_products if p.total_quantity < threshold]
        
        from models import Log
        recent_auto_logs = Log.query.filter(
            Log.method.in_(['auto_replenish_stocks', 'auto_replenishment_debug'])
        ).order_by(Log.timestamp.desc()).limit(10).all()
        
        from apscheduler.schedulers.background import BackgroundScheduler
        scheduler = BackgroundScheduler()
        
        status = {
            'auto_replenishment_config': config.to_dict() if config else None,
            'warehouse_config': warehouse_config.to_dict() if warehouse_config else None,
            'warehouses': {
                'total': len(warehouses),
                'active': len(active_warehouses),
                'active_list': [{'id': w.warehouse_id, 'name': w.name} for w in active_warehouses],
                'individual_configs': individual_configs
            },
            'tag_configs': {'total': len(tag_configs), 'configs': [t.to_dict() for t in tag_configs]},
            'products': {
                'total': len(unified_products),
                'with_barcode': len(products_with_barcode),
                'below_threshold': len(products_below_threshold),
                'threshold': threshold
            },
            'recent_logs': [log.to_dict() for log in recent_auto_logs],
            'scheduler_status': 'active',
            'next_auto_run': None,
            'system_time': datetime.utcnow().isoformat()
        }
        
        if config and config.last_run:
            next_run = config.last_run + timedelta(minutes=config.interval_minutes)
            status['next_auto_run'] = next_run.isoformat()
            status['minutes_until_next_run'] = (next_run - datetime.utcnow()).total_seconds() / 60
        
        return jsonify(status)
        
    except Exception as e:
        log_event('ERROR', 'debug_auto_replenishment_status', 'Ошибка при получении статуса автообновления',
                 {'error': str(e)})
        return jsonify({"error": str(e)}), 500


# ========== РУЧНОЕ ОБНОВЛЕНИЕ ОДНОГО ОСТАТКА ==========

@auto_replenishment_bp.route('/update-single-stock', methods=['POST'])
@jwt_required()
def update_single_stock():
    start_time = time.time()
    method_name = "update_single_stock"
    
    try:
        log_event('INFO', method_name, 'Ручное обновление остатка одного товара')
        data = request.get_json()
        if not data or 'barcode' not in data or 'quantity' not in data:
            return jsonify({"error": "barcode and quantity are required"}), 400
        
        barcode = data['barcode']
        quantity = data['quantity']
        warehouse_id = data.get('warehouse_id')
        
        if not warehouse_id:
            warehouse_config = WarehouseConfig.query.first()
            if warehouse_config:
                individual_configs = json.loads(warehouse_config.individual_config) if warehouse_config.individual_config else {}
                warehouses = Warehouse.query.all()
                for warehouse in warehouses:
                    warehouse_key = str(warehouse.warehouse_id)
                    config_data = individual_configs.get(warehouse_key, {})
                    if config_data.get('is_activate', True):
                        warehouse_id = warehouse.warehouse_id
                        break
        
        if not warehouse_id:
            return jsonify({"error": "No active warehouse found"}), 400
        
        product = UnifiedProduct.query.filter_by(barcode=barcode).first()
        if not product:
            return jsonify({"error": f"Product with barcode {barcode} not found"}), 404
        
        if not product.chrt_id:
            return jsonify({"error": f"Product with barcode {barcode} has no chrt_id"}), 404
        
        api_key = get_api_key()
        if not api_key:
            return jsonify({"error": "API token not found"}), 400
        
        stock_update = [{'chrt_id': product.chrt_id, 'amount': quantity}]
        updated_count = _update_stocks_via_api(api_key, warehouse_id, stock_update, method_name)
        
        if updated_count > 0:
            fbs_stock = FBSStock.query.filter_by(
                nm_id=product.nm_id,
                warehouse_id=warehouse_id
            ).first()
            
            if fbs_stock:
                fbs_stock.quantity = quantity
                fbs_stock.updated_at = datetime.utcnow()
            else:
                fbs_stock = FBSStock(
                    nm_id=product.nm_id,
                    warehouse_id=warehouse_id,
                    barcode=barcode,
                    quantity=quantity
                )
                db.session.add(fbs_stock)
            
            db.session.commit()
            
            duration = (time.time() - start_time) * 1000
            log_event('INFO', method_name, 'Успешное ручное обновление остатка',
                     {'barcode': barcode, 'chrt_id': product.chrt_id, 'quantity': quantity, 'warehouse_id': warehouse_id},
                     duration_ms=duration)
            
            return jsonify({
                "status": "success",
                "message": f"Stock updated to {quantity} for barcode {barcode}",
                "product": {
                    "nm_id": product.nm_id,
                    "chrt_id": product.chrt_id,
                    "vendor_code": product.vendor_code,
                    "title": product.title
                }
            })
        else:
            return jsonify({"error": "Failed to update stock via API"}), 500
            
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при ручном обновлении остатка',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500