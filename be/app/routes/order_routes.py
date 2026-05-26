import os
import time
import threading
from datetime import datetime, timedelta
from io import BytesIO
from flask import Blueprint, request, jsonify, send_file
from flask_jwt_extended import jwt_required
from sqlalchemy import func
import pandas as pd

from models import db, Order
from utils.logger import log_event
from utils.token_manager import get_api_key
from services.order_service import fetch_orders
from services.order_feed_service import fetch_and_save_order_feed_21_days
from services.order_feed_api import OrderFeedPrivateAPI
from services.order_export_service import create_export_task, get_export_task_status, get_export_task_result, get_export_task_dates

order_bp = Blueprint('order', __name__)


# ========== ОСНОВНЫЕ ЭНДПОИНТЫ ЗАКАЗОВ ==========

@order_bp.route('/orders', methods=['GET'])
@jwt_required()
def get_orders():
    start_time = time.time()
    method_name = "get_orders"
    
    try:
        log_event('INFO', method_name, 'Запрос списка заказов')
        
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 100, type=int)
        nm_id = request.args.get('nm_id', type=int)
        warehouse_name = request.args.get('warehouse_name')
        is_cancel = request.args.get('is_cancel')
        date_from = request.args.get('date_from')
        date_to = request.args.get('date_to')
        odid = request.args.get('odid', type=int)
        
        query = Order.query
        
        if nm_id:
            query = query.filter(Order.nmId == nm_id)
        if odid:
            query = query.filter(Order.odid == odid)
        if warehouse_name:
            query = query.filter(Order.warehouseName.ilike(f'%{warehouse_name}%'))
        if is_cancel is not None:
            if is_cancel.lower() == 'true':
                query = query.filter(Order.isCancel == True)
            elif is_cancel.lower() == 'false':
                query = query.filter(Order.isCancel == False)
        
        if date_from:
            try:
                date_from_dt = datetime.fromisoformat(date_from.replace('Z', '+00:00'))
                query = query.filter(Order.date >= date_from_dt)
            except:
                try:
                    date_from_dt = datetime.strptime(date_from, '%Y-%m-%d')
                    query = query.filter(Order.date >= date_from_dt)
                except:
                    log_event('WARNING', method_name, f'Неверный формат date_from: {date_from}')
        
        if date_to:
            try:
                date_to_dt = datetime.fromisoformat(date_to.replace('Z', '+00:00'))
                date_to_dt = date_to_dt.replace(hour=23, minute=59, second=59)
                query = query.filter(Order.date <= date_to_dt)
            except:
                try:
                    date_to_dt = datetime.strptime(date_to, '%Y-%m-%d')
                    date_to_dt = date_to_dt.replace(hour=23, minute=59, second=59)
                    query = query.filter(Order.date <= date_to_dt)
                except:
                    log_event('WARNING', method_name, f'Неверный формат date_to: {date_to}')
        
        query = query.order_by(Order.date.desc())
        pagination = query.paginate(page=page, per_page=per_page, error_out=False)
        orders = pagination.items
        
        orders_list = []
        for order in orders:
            orders_list.append({
                'id': order.id,
                'odid': order.odid,
                'date': order.date.isoformat() if order.date else None,
                'lastChangeDate': order.lastChangeDate.isoformat() if order.lastChangeDate else None,
                'nmId': order.nmId,
                'warehouseName': order.warehouseName,
                'supplierArticle': order.supplierArticle,
                'techSize': order.techSize,
                'barcode': order.barcode,
                'quantity': order.quantity,
                'totalPrice': order.totalPrice,
                'discountPercent': order.discountPercent,
                'oblast': order.oblast,
                'subject': order.subject,
                'category': order.category,
                'brand': order.brand,
                'isCancel': order.isCancel,
                'cancelDate': order.cancelDate.isoformat() if order.cancelDate else None,
                'gNumber': order.gNumber,
                'sticker': order.sticker,
                'srid': order.srid,
                'incomeID': order.incomeID,
                'created_at': order.created_at.isoformat() if order.created_at else None,
                'updated_at': order.updated_at.isoformat() if order.updated_at else None
            })
        
        result = {
            'orders': orders_list,
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
                'odid': odid,
                'warehouse_name': warehouse_name,
                'is_cancel': is_cancel,
                'date_from': date_from,
                'date_to': date_to
            }
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат списка заказов',
                 {'page': page, 'per_page': per_page, 'total_items': pagination.total, 'returned_items': len(orders)},
                 duration_ms=duration, records_processed=len(orders))
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении списка заказов', {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@order_bp.route('/orders/by-odids', methods=['POST'])
@jwt_required()
def get_orders_by_odids():
    start_time = time.time()
    method_name = "get_orders_by_odids"
    
    try:
        data = request.get_json()
        odids = data.get('odids', [])
        log_event('INFO', method_name, f'Запрос заказов по odids: {odids}')
        
        if not odids:
            return jsonify({"error": "Список odids пуст"}), 400
        
        orders = Order.query.filter(Order.odid.in_(odids)).all()
        if not orders:
            return jsonify({"orders": []}), 200
        
        orders_list = []
        for order in orders:
            orders_list.append({
                'id': order.id,
                'odid': order.odid,
                'date': order.date.isoformat() if order.date else None,
                'lastChangeDate': order.lastChangeDate.isoformat() if order.lastChangeDate else None,
                'nmId': order.nmId,
                'warehouseName': order.warehouseName,
                'supplierArticle': order.supplierArticle,
                'techSize': order.techSize,
                'barcode': order.barcode,
                'quantity': order.quantity,
                'totalPrice': order.totalPrice,
                'discountPercent': order.discountPercent,
                'oblast': order.oblast,
                'subject': order.subject,
                'category': order.category,
                'brand': order.brand,
                'isCancel': order.isCancel,
                'cancelDate': order.cancelDate.isoformat() if order.cancelDate else None,
                'gNumber': order.gNumber,
                'sticker': order.sticker,
                'srid': order.srid,
                'incomeID': order.incomeID,
                'created_at': order.created_at.isoformat() if order.created_at else None,
                'updated_at': order.updated_at.isoformat() if order.updated_at else None
            })
        
        return jsonify({"orders": orders_list})
        
    except Exception as e:
        log_event('ERROR', method_name, f'Ошибка: {str(e)}')
        return jsonify({"error": str(e)}), 500


@order_bp.route('/orders/<int:order_id>', methods=['GET'])
@jwt_required()
def get_order_by_id(order_id):
    start_time = time.time()
    method_name = "get_order_by_id"
    
    try:
        order = Order.query.filter_by(odid=order_id).first()
        if not order:
            order = Order.query.get(order_id)
        if not order:
            return jsonify({"error": "Заказ не найден", "order_id": order_id}), 404
        
        order_data = {
            'id': order.id,
            'odid': order.odid,
            'date': order.date.isoformat() if order.date else None,
            'lastChangeDate': order.lastChangeDate.isoformat() if order.lastChangeDate else None,
            'nmId': order.nmId,
            'warehouseName': order.warehouseName,
            'supplierArticle': order.supplierArticle,
            'techSize': order.techSize,
            'barcode': order.barcode,
            'quantity': order.quantity,
            'totalPrice': order.totalPrice,
            'discountPercent': order.discountPercent,
            'oblast': order.oblast,
            'subject': order.subject,
            'category': order.category,
            'brand': order.brand,
            'isCancel': order.isCancel,
            'cancelDate': order.cancelDate.isoformat() if order.cancelDate else None,
            'gNumber': order.gNumber,
            'sticker': order.sticker,
            'srid': order.srid,
            'incomeID': order.incomeID,
            'created_at': order.created_at.isoformat() if order.created_at else None,
            'updated_at': order.updated_at.isoformat() if order.updated_at else None
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Успешный возврат заказа ID {order_id}', duration_ms=duration)
        return jsonify(order_data)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка: {str(e)}', duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@order_bp.route('/orders/odid/<int:odid>', methods=['GET'])
@jwt_required()
def get_order_by_odid(odid):
    start_time = time.time()
    method_name = "get_order_by_odid"
    
    try:
        order = Order.query.filter_by(odid=odid).first()
        if not order:
            return jsonify({"error": "Заказ не найден", "odid": odid}), 404
        
        order_data = {
            'id': order.id,
            'odid': order.odid,
            'date': order.date.isoformat() if order.date else None,
            'lastChangeDate': order.lastChangeDate.isoformat() if order.lastChangeDate else None,
            'nmId': order.nmId,
            'warehouseName': order.warehouseName,
            'supplierArticle': order.supplierArticle,
            'techSize': order.techSize,
            'barcode': order.barcode,
            'quantity': order.quantity,
            'totalPrice': order.totalPrice,
            'discountPercent': order.discountPercent,
            'oblast': order.oblast,
            'subject': order.subject,
            'category': order.category,
            'brand': order.brand,
            'isCancel': order.isCancel,
            'cancelDate': order.cancelDate.isoformat() if order.cancelDate else None,
            'gNumber': order.gNumber,
            'sticker': order.sticker,
            'srid': order.srid,
            'incomeID': order.incomeID,
            'created_at': order.created_at.isoformat() if order.created_at else None,
            'updated_at': order.updated_at.isoformat() if order.updated_at else None
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Успешный возврат заказа odid {odid}', duration_ms=duration)
        return jsonify(order_data)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка: {str(e)}', duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@order_bp.route('/update-orders', methods=['GET'])
@jwt_required()
def update_orders_endpoint():
    start_time = time.time()
    method_name = "update_orders_endpoint"
    
    try:
        log_event('INFO', method_name, 'Ручной запуск обновления заказов')
        api_key = get_api_key()
        if not api_key:
            return jsonify({"error": "Отсутствует API токен"}), 400
        
        def background_update():
            try:
                from flask import current_app
                with current_app.app_context():
                    orders_count = fetch_orders(first_request=True)
                    log_event('INFO', 'background_update', f'Заказов получено: {orders_count}')
            except Exception as e:
                log_event('ERROR', 'background_update', str(e))
        
        thread = threading.Thread(target=background_update)
        thread.daemon = True
        thread.start()
        
        return jsonify({"status": "success", "message": "Обновление заказов запущено в фоновом режиме"})
        
    except Exception as e:
        log_event('ERROR', method_name, str(e))
        return jsonify({"error": str(e)}), 500


@order_bp.route('/orders/stats', methods=['GET'])
@jwt_required()
def get_orders_stats():
    start_time = time.time()
    method_name = "get_orders_stats"
    
    try:
        total_orders = Order.query.count()
        active_orders = Order.query.filter(Order.isCancel == False).count()
        canceled_orders = Order.query.filter(Order.isCancel == True).count()
        
        warehouse_stats = db.session.query(
            Order.warehouseName, func.count(Order.id).label('order_count')
        ).group_by(Order.warehouseName).order_by(func.count(Order.id).desc()).all()
        
        product_stats = db.session.query(
            Order.nmId, func.count(Order.id).label('order_count')
        ).group_by(Order.nmId).order_by(func.count(Order.id).desc()).limit(10).all()
        
        latest_orders = Order.query.order_by(Order.date.desc()).limit(5).all()
        
        total_revenue = db.session.query(func.sum(Order.totalPrice)).scalar() or 0
        avg_order_value = total_revenue / total_orders if total_orders > 0 else 0
        
        result = {
            'total_orders': total_orders,
            'active_orders': active_orders,
            'canceled_orders': canceled_orders,
            'total_revenue': total_revenue,
            'average_order_value': avg_order_value,
            'warehouse_statistics': [{'warehouse': w, 'order_count': c} for w, c in warehouse_stats],
            'top_products': [{'nmId': n, 'order_count': c} for n, c in product_stats],
            'latest_orders': [
                {
                    'odid': o.odid,
                    'date': o.date.isoformat() if o.date else None,
                    'nmId': o.nmId,
                    'warehouseName': o.warehouseName,
                    'totalPrice': o.totalPrice,
                    'isCancel': o.isCancel
                } for o in latest_orders
            ],
            'last_updated': None
        }
        
        last_order = Order.query.order_by(Order.updated_at.desc()).first()
        if last_order and last_order.updated_at:
            result['last_updated'] = last_order.updated_at.isoformat()
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат статистики', duration_ms=duration)
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, str(e), duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@order_bp.route('/orders/export', methods=['GET'])
@jwt_required()
def export_orders():
    start_time = time.time()
    method_name = "export_orders"
    
    try:
        log_event('INFO', method_name, 'Экспорт заказов в XLSX')
        date_from = request.args.get('date_from')
        date_to = request.args.get('date_to')
        
        query = Order.query
        if date_from:
            try:
                date_from_dt = datetime.fromisoformat(date_from.replace('Z', '+00:00'))
                query = query.filter(Order.date >= date_from_dt)
            except:
                try:
                    date_from_dt = datetime.strptime(date_from, '%Y-%m-%d')
                    query = query.filter(Order.date >= date_from_dt)
                except:
                    pass
        if date_to:
            try:
                date_to_dt = datetime.fromisoformat(date_to.replace('Z', '+00:00'))
                date_to_dt = date_to_dt.replace(hour=23, minute=59, second=59)
                query = query.filter(Order.date <= date_to_dt)
            except:
                try:
                    date_to_dt = datetime.strptime(date_to, '%Y-%m-%d')
                    date_to_dt = date_to_dt.replace(hour=23, minute=59, second=59)
                    query = query.filter(Order.date <= date_to_dt)
                except:
                    pass
        
        orders = query.order_by(Order.date.desc()).all()
        if not orders:
            return jsonify({"error": "Нет заказов для экспорта"}), 404
        
        orders_data = []
        for order in orders:
            orders_data.append({
                'ID': order.odid,
                'Дата': order.date.isoformat() if order.date else '',
                'Дата изменения': order.lastChangeDate.isoformat() if order.lastChangeDate else '',
                'Артикул WB': order.nmId,
                'Мой артикул': order.supplierArticle,
                'Размер': order.techSize,
                'Баркод': order.barcode,
                'Количество': order.quantity,
                'Цена': order.totalPrice,
                'Скидка %': order.discountPercent,
                'Склад': order.warehouseName,
                'Область': order.oblast,
                'Предмет': order.subject,
                'Категория': order.category,
                'Бренд': order.brand,
                'Отменен': 'Да' if order.isCancel else 'Нет',
                'Дата отмены': order.cancelDate.isoformat() if order.cancelDate else '',
                'Номер заказа': order.gNumber,
                'Стикер': order.sticker,
                'SRID': order.srid,
                'IncomeID': order.incomeID,
                'Дата создания': order.created_at.isoformat() if order.created_at else '',
                'Дата обновления': order.updated_at.isoformat() if order.updated_at else ''
            })
        
        df = pd.DataFrame(orders_data)
        output = BytesIO()
        with pd.ExcelWriter(output, engine='xlsxwriter') as writer:
            df.to_excel(writer, sheet_name='Заказы', index=False)
            worksheet = writer.sheets['Заказы']
            worksheet.set_column('A:A', 15)
            worksheet.set_column('B:C', 20)
            worksheet.set_column('D:D', 15)
            worksheet.set_column('E:E', 20)
            worksheet.set_column('F:F', 10)
            worksheet.set_column('G:G', 20)
            worksheet.set_column('H:H', 10)
            worksheet.set_column('I:I', 15)
            worksheet.set_column('J:J', 10)
            worksheet.set_column('K:K', 20)
            worksheet.set_column('L:L', 20)
            worksheet.set_column('M:N', 25)
            worksheet.set_column('O:O', 20)
            worksheet.set_column('P:P', 10)
            worksheet.set_column('Q:Q', 20)
            worksheet.set_column('R:T', 20)
            worksheet.set_column('U:U', 15)
            worksheet.set_column('V:W', 20)
        
        output.seek(0)
        filename = f"заказы_экспорт_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.xlsx"
        return send_file(output, as_attachment=True, download_name=filename,
                         mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
        
    except Exception as e:
        log_event('ERROR', method_name, str(e))
        return jsonify({"error": str(e)}), 500


# ========== ЛЕНТА ЗАКАЗОВ ==========

@order_bp.route('/order-feed/latest', methods=['GET'])
@jwt_required()
def get_latest_order_feed():
    try:
        folder = os.path.join('uploads', 'orderfeed')
        if not os.path.exists(folder):
            return jsonify({'error': 'Файл ещё не создан. Дождитесь первого обновления (до 5-10 минут).'}), 404
        
        files = [f for f in os.listdir(folder) if f.startswith('order_feed_') and f.endswith('.csv')]
        if not files:
            return jsonify({'error': 'Файл ещё не создан. Дождитесь первого обновления.'}), 404
        
        latest_file = sorted(files)[-1]
        file_path = os.path.join(folder, latest_file)
        return send_file(file_path, as_attachment=True, download_name=latest_file, mimetype='text/csv')
    except Exception as e:
        log_event('ERROR', 'get_latest_order_feed', str(e))
        return jsonify({'error': str(e)}), 500


@order_bp.route('/order-feed/update', methods=['GET'])
@jwt_required()
def manually_update_order_feed():
    def background():
        from flask import current_app
        with current_app.app_context():
            fetch_and_save_order_feed_21_days()
    thread = threading.Thread(target=background)
    thread.daemon = True
    thread.start()
    return jsonify({'status': 'Обновление запущено в фоне, результат будет через несколько минут'})


# ========== СИНХРОННЫЙ ЭКСПОРТ ЗАКАЗОВ (PARQUET, JSON, CSV) ==========

@order_bp.route('/api/orders/export-parquet', methods=['POST'])
@jwt_required()
def export_orders_parquet():
    start_time = time.time()
    method_name = "export_orders_parquet"
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "JSON данные не предоставлены"}), 400
        
        date_from = data.get('date_from')
        date_to = data.get('date_to')
        authorize_v3 = data.get('authorize_v3')
        wb_seller_lk = data.get('wb_seller_lk')
        cookie = data.get('cookie')
        
        if not all([date_from, date_to, authorize_v3, wb_seller_lk, cookie]):
            return jsonify({"error": "Необходимы поля: date_from, date_to, authorize_v3, wb_seller_lk, cookie"}), 400
        
        datetime.strptime(date_from, "%Y-%m-%d")
        datetime.strptime(date_to, "%Y-%m-%d")
        
        report_name = f"OrdersExport_{date_from}_{date_to}_{int(time.time())}"
        client = OrderFeedPrivateAPI(authorize_v3, wb_seller_lk, cookie)
        client.set_period(date_from, date_to)
        report_id = client.create_report(report_name, date_from, date_to)
        client.wait_for_done(report_id, timeout=300)
        token = client.get_download_token()
        parquet_bytes = client.download_and_convert_to_parquet(report_id, token)
        filename = f"orders_{date_from}_{date_to}.parquet"
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Экспорт завершён, файл {filename}', duration_ms=duration)
        return send_file(BytesIO(parquet_bytes), as_attachment=True, download_name=filename, mimetype='application/octet-stream')
    except Exception as e:
        log_event('ERROR', method_name, str(e))
        return jsonify({"error": str(e)}), 500


@order_bp.route('/api/orders/export-json', methods=['POST'])
@jwt_required()
def export_orders_json():
    start_time = time.time()
    method_name = "export_orders_json"
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "JSON данные не предоставлены"}), 400
        
        date_from = data.get('date_from')
        date_to = data.get('date_to')
        authorize_v3 = data.get('authorize_v3')
        wb_seller_lk = data.get('wb_seller_lk')
        cookie = data.get('cookie')
        
        if not all([date_from, date_to, authorize_v3, wb_seller_lk, cookie]):
            return jsonify({"error": "Необходимы поля: date_from, date_to, authorize_v3, wb_seller_lk, cookie"}), 400
        
        datetime.strptime(date_from, "%Y-%m-%d")
        datetime.strptime(date_to, "%Y-%m-%d")
        
        report_name = f"OrdersExport_{date_from}_{date_to}_{int(time.time())}"
        client = OrderFeedPrivateAPI(authorize_v3, wb_seller_lk, cookie)
        client.set_period(date_from, date_to)
        report_id = client.create_report(report_name, date_from, date_to)
        client.wait_for_done(report_id, timeout=300)
        token = client.get_download_token()
        parquet_bytes = client.download_and_convert_to_parquet(report_id, token)
        df = pd.read_parquet(BytesIO(parquet_bytes))
        records = df.to_dict(orient='records')
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Экспорт завершён, получено {len(records)} записей', duration_ms=duration)
        return jsonify({"orders": records, "count": len(records)})
    except Exception as e:
        log_event('ERROR', method_name, str(e))
        return jsonify({"error": str(e)}), 500


@order_bp.route('/api/orders/export-csv', methods=['POST'])
@jwt_required()
def export_orders_csv():
    start_time = time.time()
    method_name = "export_orders_csv"
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "JSON данные не предоставлены"}), 400
        
        date_from = data.get('date_from')
        date_to = data.get('date_to')
        authorize_v3 = data.get('authorize_v3')
        wb_seller_lk = data.get('wb_seller_lk')
        cookie = data.get('cookie')
        
        if not all([date_from, date_to, authorize_v3, wb_seller_lk, cookie]):
            return jsonify({"error": "Необходимы поля: date_from, date_to, authorize_v3, wb_seller_lk, cookie"}), 400
        
        datetime.strptime(date_from, "%Y-%m-%d")
        datetime.strptime(date_to, "%Y-%m-%d")
        
        report_name = f"OrdersExport_{date_from}_{date_to}_{int(time.time())}"
        client = OrderFeedPrivateAPI(authorize_v3, wb_seller_lk, cookie)
        client.set_period(date_from, date_to)
        report_id = client.create_report(report_name, date_from, date_to)
        client.wait_for_done(report_id, timeout=300)
        token = client.get_download_token()
        parquet_bytes = client.download_and_convert_to_parquet(report_id, token)
        df = pd.read_parquet(BytesIO(parquet_bytes))
        csv_buffer = BytesIO()
        df.to_csv(csv_buffer, index=False, encoding='utf-8-sig')
        csv_buffer.seek(0)
        filename = f"orders_{date_from}_{date_to}.csv"
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Экспорт завершён, файл {filename}', duration_ms=duration)
        return send_file(csv_buffer, as_attachment=True, download_name=filename, mimetype='text/csv')
    except Exception as e:
        log_event('ERROR', method_name, str(e))
        return jsonify({"error": str(e)}), 500


# ========== АСИНХРОННЫЙ ЭКСПОРТ ЗАКАЗОВ ==========

@order_bp.route('/api/orders/export-csv/start', methods=['POST'])
@jwt_required()
def start_async_export():
    data = request.get_json()
    if not data:
        return jsonify({"error": "JSON данные не предоставлены"}), 400

    date_from = data.get('date_from')
    date_to = data.get('date_to')
    authorize_v3 = data.get('authorize_v3')
    wb_seller_lk = data.get('wb_seller_lk')
    cookie = data.get('cookie')

    if not all([date_from, date_to, authorize_v3, wb_seller_lk, cookie]):
        return jsonify({"error": "Необходимы поля: date_from, date_to, authorize_v3, wb_seller_lk, cookie"}), 400

    try:
        datetime.strptime(date_from, "%Y-%m-%d")
        datetime.strptime(date_to, "%Y-%m-%d")
    except ValueError:
        return jsonify({"error": "Даты должны быть в формате YYYY-MM-DD"}), 400

    task_id = create_export_task(date_from, date_to, authorize_v3, wb_seller_lk, cookie)
    return jsonify({"task_id": task_id, "status": "pending"})


@order_bp.route('/api/orders/export-csv/status/<task_id>', methods=['GET'])
@jwt_required()
def get_async_export_status(task_id):
    status_data = get_export_task_status(task_id)
    if status_data is None:
        return jsonify({"error": "Задача не найдена"}), 404
    return jsonify(status_data)


@order_bp.route('/api/orders/export-csv/download/<task_id>', methods=['GET'])
@jwt_required()
def download_async_export(task_id):
    csv_data = get_export_task_result(task_id)
    if csv_data is None:
        return jsonify({"error": "Файл не готов или не найден"}), 404
    
    dates = get_export_task_dates(task_id)
    if dates is None:
        return jsonify({"error": "Задача не найдена"}), 404
    date_from, date_to = dates
    filename = f"orders_{date_from}_{date_to}.csv"
    
    return send_file(BytesIO(csv_data), as_attachment=True, download_name=filename, mimetype='text/csv')