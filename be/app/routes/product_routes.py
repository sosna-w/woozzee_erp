import json
import time
from datetime import datetime, timedelta
from io import BytesIO
from flask import Blueprint, request, jsonify, send_file
from flask_jwt_extended import jwt_required
from sqlalchemy import func, text
import pandas as pd

from models import db, Product, Stock, UnifiedProduct, StocksHistory
from utils.logger import log_event
from services.product_service import fetch_all_products, fetch_all_stocks, _update_stocks_via_api
from services.unified_product_service import update_unified_products

product_bp = Blueprint('product', __name__)


@product_bp.route('/products', methods=['GET'])
@jwt_required()
def get_products():
    start_time = time.time()
    try:
        log_event('INFO', 'get_products', 'Запрос списка товаров')
        
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 500, type=int)
        
        if per_page > 1000:
            per_page = 1000
        
        pagination = Product.query.paginate(
            page=page, 
            per_page=per_page, 
            error_out=False
        )
        products = pagination.items
        
        result = []
        for p in products:
            product_data = {
                'nmID': p.nmID,
                'imtID': p.imtID,
                'nmUUID': p.nmUUID,
                'subjectID': p.subjectID,
                'subjectName': p.subjectName,
                'vendorCode': p.vendorCode,
                'brand': p.brand,
                'title': p.title,
                'description': p.description,
                'needKiz': p.needKiz,
                'video': p.video,
                'wholesale_enabled': p.wholesale_enabled,
                'wholesale_quantum': p.wholesale_quantum,
                'dimensions_length': p.dimensions_length,
                'dimensions_width': p.dimensions_width,
                'dimensions_height': p.dimensions_height,
                'dimensions_weightBrutto': p.dimensions_weightBrutto,
                'dimensions_isValid': p.dimensions_isValid,
                'created_at': p.created_at.isoformat() if p.created_at else None,
                'updated_at': p.updated_at.isoformat() if p.updated_at else None,
                'photos': json.loads(p.photos) if p.photos else [],
                'sizes': json.loads(p.sizes) if p.sizes else [],
                'characteristics': json.loads(p.characteristics) if p.characteristics else [],
                'tags': json.loads(p.tags) if p.tags else []
            }
            result.append(product_data)
        
        response_data = {
            'products': result,
            'pagination': {
                'page': pagination.page,
                'per_page': pagination.per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            }
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', 'get_products', 'Успешный возврат списка товаров',
                 {'products_count': len(result), 'page': page, 'per_page': per_page, 'total': pagination.total},
                 duration_ms=duration, records_processed=len(result))
        return jsonify(response_data)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', 'get_products', 'Ошибка при получении списка товаров',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@product_bp.route('/products/<int:nm_id>', methods=['GET'])
@jwt_required()
def get_product(nm_id):
    start_time = time.time()
    try:
        log_event('INFO', 'get_product', f'Запрос товара nmID {nm_id}', nm_id=nm_id)
        product = Product.query.filter_by(nmID=nm_id).first()
        if not product:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', 'get_product', f'Товар nmID {nm_id} не найден',
                     nm_id=nm_id, duration_ms=duration)
            return jsonify({"error": "Product not found"}), 404
        
        product_data = {
            'nmID': product.nmID,
            'imtID': product.imtID,
            'nmUUID': product.nmUUID,
            'subjectID': product.subjectID,
            'subjectName': product.subjectName,
            'vendorCode': product.vendorCode,
            'brand': product.brand,
            'title': product.title,
            'description': product.description,
            'needKiz': product.needKiz,
            'video': product.video,
            'wholesale': {
                'enabled': product.wholesale_enabled,
                'quantum': product.wholesale_quantum
            },
            'dimensions': {
                'length': product.dimensions_length,
                'width': product.dimensions_width,
                'height': product.dimensions_height,
                'weightBrutto': product.dimensions_weightBrutto,
                'isValid': product.dimensions_isValid
            },
            'created_at': product.created_at.isoformat() if product.created_at else None,
            'updated_at': product.updated_at.isoformat() if product.updated_at else None,
            'photos': json.loads(product.photos) if product.photos else [],
            'sizes': json.loads(product.sizes) if product.sizes else [],
            'characteristics': json.loads(product.characteristics) if product.characteristics else [],
            'tags': json.loads(product.tags) if product.tags else []
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', 'get_product', f'Успешный возврат товара nmID {nm_id}',
                 nm_id=nm_id, duration_ms=duration)
        return jsonify(product_data)
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', 'get_product', f'Ошибка при получении товара nmID {nm_id}',
                 {'nm_id': nm_id, 'error': str(e)}, nm_id=nm_id, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@product_bp.route('/stocks/all', methods=['GET'])
@jwt_required()
def get_all_stocks():
    start_time = time.time()
    try:
        log_event('INFO', 'get_all_stocks', 'Запрос полных данных остатков')
        stocks = Stock.query.all()
        result = [{
            'id': s.id,
            'lastChangeDate': s.lastChangeDate.isoformat() if s.lastChangeDate else None,
            'warehouseName': s.warehouseName,
            'supplierArticle': s.supplierArticle,
            'nmId': s.nmId,
            'barcode': s.barcode,
            'quantity': s.quantity,
            'inWayToClient': s.inWayToClient,
            'inWayFromClient': s.inWayFromClient,
            'quantityFull': s.quantityFull,
            'category': s.category,
            'subject': s.subject,
            'brand': s.brand,
            'techSize': s.techSize,
            'Price': s.Price,
            'Discount': s.Discount,
            'isSupply': s.isSupply,
            'isRealization': s.isRealization,
            'SCCode': s.SCCode
        } for s in stocks]
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', 'get_all_stocks', 'Успешный возврат полных данных остатков',
                 {'stocks_count': len(result)}, duration_ms=duration, records_processed=len(result))
        return jsonify(result)
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', 'get_all_stocks', 'Ошибка при получении полных данных остатков',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@product_bp.route('/stocks', methods=['GET'])
@jwt_required()
def get_stocks():
    start_time = time.time()
    try:
        log_event('INFO', 'get_stocks', 'Запрос списка остатков')
        stocks = Stock.query.all()
        result = [{
            'nmId': s.nmId,
            'warehouse': s.warehouseName,
            'quantity': s.quantity,
            'quantityFull': s.quantityFull,
            'barcode': s.barcode,
            'subject': s.subject,
            'brand': s.brand
        } for s in stocks]
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', 'get_stocks', 'Успешный возврат списка остатков',
                 {'stocks_count': len(result)}, duration_ms=duration, records_processed=len(result))
        return jsonify(result)
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', 'get_stocks', 'Ошибка при получении списка остатков',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@product_bp.route('/stocks/dynamics', methods=['GET'])
@jwt_required()
def stocks_dynamics():
    start_time = time.time()
    method_name = "stocks_dynamics"

    try:
        days = request.args.get('days', 60, type=int)
        if days < 1:
            days = 1
        if days > 365:
            days = 365

        since_date = datetime.utcnow() - timedelta(days=days)
        today = datetime.utcnow().date()

        hourly = db.session.query(
            func.date(StocksHistory.created_at).label('day'),
            func.date_part('hour', StocksHistory.created_at).label('hour'),
            func.sum(StocksHistory.total_quantity).label('fbo_sum'),
            func.sum(StocksHistory.fbs_quantity).label('fbs_sum')
        ).filter(StocksHistory.created_at >= since_date) \
         .group_by('day', 'hour') \
         .subquery()

        query = db.session.query(
            hourly.c.day,
            hourly.c.fbo_sum,
            hourly.c.fbs_sum
        ).filter(
            db.or_(
                db.and_(hourly.c.day < today, hourly.c.hour == 23),
                db.and_(hourly.c.day == today, hourly.c.hour == (
                    db.session.query(db.func.max(hourly.c.hour))
                    .filter(hourly.c.day == today)
                    .scalar_subquery()
                ))
            )
        ).order_by(hourly.c.day)

        results = query.all()

        data = []
        for row in results:
            data.append({
                'date': row.day.isoformat(),
                'fbo_total': int(row.fbo_sum) if row.fbo_sum else 0,
                'fbs_total': int(row.fbs_sum) if row.fbs_sum else 0
            })

        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Динамика остатков за {days} дней',
                  {'days': days, 'records': len(data), 'duration_ms': duration})

        return jsonify(data)

    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, str(e), duration_ms=duration)
        return jsonify({'error': str(e)}), 500


@product_bp.route('/unified-products', methods=['GET'])
@jwt_required()
def get_unified_products():
    start_time = time.time()
    method_name = "get_unified_products"
    
    try:
        log_event('INFO', method_name, 'Запрос объединенных данных товаров')
        
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 100, type=int)
        search = request.args.get('search', '')
        min_quantity = request.args.get('min_quantity', 0, type=int)
        
        query = UnifiedProduct.query
        
        if search:
            query = query.filter(
                db.or_(
                    UnifiedProduct.vendor_code.ilike(f'%{search}%'),
                    UnifiedProduct.title.ilike(f'%{search}%'),
                    UnifiedProduct.barcode.ilike(f'%{search}%')
                )
            )
        
        if min_quantity > 0:
            query = query.filter(UnifiedProduct.total_quantity >= min_quantity)
        
        pagination = query.paginate(
            page=page, 
            per_page=per_page, 
            error_out=False
        )
        
        unified_products = pagination.items
        
        result = {
            'unified_products': [product.to_dict() for product in unified_products],
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            },
            'filters': {
                'search': search,
                'min_quantity': min_quantity
            }
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат объединенных данных',
                 {
                     'page': page,
                     'per_page': per_page,
                     'total_items': pagination.total,
                     'returned_items': len(unified_products)
                 },
                 duration_ms=duration,
                 records_processed=len(unified_products))
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении объединенных данных',
                 {'error': str(e)},
                 duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@product_bp.route('/unified-products/counts', methods=['GET'])
@jwt_required()
def get_unified_products_counts():
    start_time = time.time()
    method_name = "get_unified_products_counts"
    try:
        log_event('INFO', method_name, 'Запрос статистики количества и сумм товаров')

        any_stock_count = UnifiedProduct.query.filter(
            db.or_(
                UnifiedProduct.total_quantity > 0,
                UnifiedProduct.fbs_quantity > 0
            )
        ).count()

        fbs_stock_count = UnifiedProduct.query.filter(UnifiedProduct.fbs_quantity > 0).count()
        fbo_stock_count = UnifiedProduct.query.filter(UnifiedProduct.total_quantity > 0).count()
        no_stock_count = UnifiedProduct.query.filter(
            UnifiedProduct.total_quantity == 0,
            UnifiedProduct.fbs_quantity == 0
        ).count()

        total_stock_sum = db.session.query(
            func.sum(UnifiedProduct.total_quantity + UnifiedProduct.fbs_quantity)
        ).scalar() or 0
        total_fbo_sum = db.session.query(func.sum(UnifiedProduct.total_quantity)).scalar() or 0
        total_fbs_sum = db.session.query(func.sum(UnifiedProduct.fbs_quantity)).scalar() or 0

        result = {
            'products_with_any_stock': any_stock_count,
            'products_with_fbs_stock': fbs_stock_count,
            'products_with_fbo_stock': fbo_stock_count,
            'products_without_stock': no_stock_count,
            'total_stock_sum': total_stock_sum,
            'total_fbo_sum': total_fbo_sum,
            'total_fbs_sum': total_fbs_sum
        }

        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат статистики количества и сумм товаров',
                  result, duration_ms=duration)
        return jsonify(result)

    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении статистики количества и сумм товаров',
                  {'error': str(e)}, duration_ms=duration)
        return jsonify({'error': str(e)}), 500


@product_bp.route('/unified-products/stats', methods=['GET'])
@jwt_required()
def get_unified_stats():
    try:
        total_products = UnifiedProduct.query.count()
        total_with_stock = UnifiedProduct.query.filter(UnifiedProduct.total_quantity > 0).count()
        total_zero_stock = UnifiedProduct.query.filter(UnifiedProduct.total_quantity == 0).count()
        total_quantity = db.session.query(func.sum(UnifiedProduct.total_quantity)).scalar() or 0
        
        top_stocked = UnifiedProduct.query.order_by(UnifiedProduct.total_quantity.desc()).limit(10).all()
        
        stats = {
            'total_products': total_products,
            'products_with_stock': total_with_stock,
            'products_zero_stock': total_zero_stock,
            'total_quantity': total_quantity,
            'avg_quantity_per_product': total_quantity / total_products if total_products > 0 else 0,
            'top_stocked_products': [{
                'nm_id': product.nm_id,
                'title': product.title,
                'quantity': product.total_quantity
            } for product in top_stocked]
        }
        
        return jsonify(stats)
    except Exception as e:
        log_event('ERROR', 'get_unified_stats', 'Ошибка при получении статистики объединенной базы',
                 {'error': str(e)})
        return jsonify({"error": str(e)}), 500


@product_bp.route('/update-products', methods=['GET'])
@jwt_required()
def update_products():
    start_time = time.time()
    try:
        log_event('INFO', 'update_products', 'Ручной запуск обновления товаров')
        fetch_all_products()
        duration = (time.time() - start_time) * 1000
        log_event('INFO', 'update_products', 'Ручное обновление товаров завершено',
                 duration_ms=duration)
        return jsonify({"status": "Products update started"})
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', 'update_products', 'Ошибка при ручном обновлении товаров',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@product_bp.route('/update-stocks', methods=['GET'])
@jwt_required()
def update_stocks():
    start_time = time.time()
    try:
        log_event('INFO', 'update_stocks', 'Ручной запуск обновления остатков')
        fetch_all_stocks()
        duration = (time.time() - start_time) * 1000
        log_event('INFO', 'update_stocks', 'Ручное обновление остатков завершено',
                 duration_ms=duration)
        return jsonify({"status": "Stocks update started"})
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', 'update_stocks', 'Ошибка при ручном обновлении остатков',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@product_bp.route('/update-unified', methods=['GET'])
@jwt_required()
def update_unified_endpoint():
    start_time = time.time()
    method_name = "update_unified_endpoint"
    
    try:
        log_event('INFO', method_name, 'Ручной запуск обновления объединенной базы')
        update_unified_products()
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Ручное обновление объединенной базы завершено',
                 duration_ms=duration)
        return jsonify({"status": "Unified products update completed"})
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при ручном обновлении объединенной базы',
                 {'error': str(e)},
                 duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@product_bp.route('/update-single-stock', methods=['POST'])
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
        
        # Если warehouse_id не указан, используем первый активный склад
        if not warehouse_id:
            from models import WarehouseConfig
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
        
        from utils.token_manager import get_api_key
        api_key = get_api_key()
        if not api_key:
            return jsonify({"error": "API token not found"}), 400
        
        stock_update = [{
            'chrt_id': product.chrt_id,
            'amount': quantity
        }]
        
        updated_count = _update_stocks_via_api(api_key, warehouse_id, stock_update, method_name)
        
        if updated_count > 0:
            from models import FBSStock
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