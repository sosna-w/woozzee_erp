import time
from flask import Blueprint, jsonify, current_app
from flask_jwt_extended import jwt_required
from sqlalchemy import inspect
from models import db, Token, Log, Product, Stock, UnifiedProduct, Warehouse, FBSStock, TagConfig, AutoReplenishmentConfig, WarehouseConfig

debug_bp = Blueprint('debug', __name__, url_prefix='/debug')


@debug_bp.route('/routes', methods=['GET'])
@jwt_required()
def debug_routes():
    routes = []
    for rule in current_app.url_map.iter_rules():
        routes.append({
            'endpoint': rule.endpoint,
            'methods': list(rule.methods),
            'path': str(rule)
        })
    return jsonify(routes)


@debug_bp.route('/db-status', methods=['GET'])
@jwt_required()
def debug_db_status():
    try:
        inspector = inspect(db.engine)
        tables = inspector.get_table_names()
        
        token_count = Token.query.count()
        log_count = Log.query.count()
        product_count = Product.query.count()
        stock_count = Stock.query.count()
        unified_count = UnifiedProduct.query.count()
        warehouse_count = Warehouse.query.count()
        fbs_count = FBSStock.query.count()
        tag_config_count = TagConfig.query.count()
        auto_config_count = AutoReplenishmentConfig.query.count()
        warehouse_config_count = WarehouseConfig.query.count()
        
        return jsonify({
            'database_tables': tables,
            'records_count': {
                'tokens': token_count,
                'logs': log_count,
                'products': product_count,
                'stocks': stock_count,
                'unified_products': unified_count,
                'warehouses': warehouse_count,
                'fbs_stocks': fbs_count,
                'tag_configs': tag_config_count,
                'auto_replenishment_configs': auto_config_count,
                'warehouse_configs': warehouse_config_count
            },
            'database_path': str(current_app.config.get('SQLALCHEMY_DATABASE_URI', 'sqlite:///sosna.db')),
            'status': 'healthy'
        })
    except Exception as e:
        return jsonify({
            'error': str(e),
            'status': 'error'
        }), 500