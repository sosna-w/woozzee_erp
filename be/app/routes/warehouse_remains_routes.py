import time
import threading
from datetime import datetime
from io import BytesIO
from flask import Blueprint, request, jsonify, send_file, current_app
from flask_jwt_extended import jwt_required
import pandas as pd
from models import db, WarehouseRemains
from utils.logger import log_event
from services.warehouse_remains_service import fetch_warehouse_remains

warehouse_remains_bp = Blueprint('warehouse_remains', __name__, url_prefix='/warehouse-remains')


@warehouse_remains_bp.route('', methods=['GET'])
@jwt_required()
def get_warehouse_remains():
    start_time = time.time()
    try:
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 10000, type=int)
        nm_id = request.args.get('nm_id', type=int)
        warehouse_name = request.args.get('warehouse_name')
        brand = request.args.get('brand')
        vendor_code = request.args.get('vendor_code')
        report_date = request.args.get('report_date')

        query = WarehouseRemains.query
        exclude_warehouses = ['В пути до получателей', 'В пути возвраты на склад WB', 'Всего находится на складах']
        query = query.filter(~WarehouseRemains.warehouse_name.in_(exclude_warehouses))

        if nm_id:
            query = query.filter(WarehouseRemains.nm_id == nm_id)
        if warehouse_name:
            query = query.filter(WarehouseRemains.warehouse_name.ilike(f'%{warehouse_name}%'))
        if brand:
            query = query.filter(WarehouseRemains.brand.ilike(f'%{brand}%'))
        if vendor_code:
            query = query.filter(WarehouseRemains.vendor_code.ilike(f'%{vendor_code}%'))
        if report_date:
            try:
                rdate = datetime.strptime(report_date, '%Y-%m-%d').date()
                query = query.filter(WarehouseRemains.report_date == rdate)
            except:
                pass

        if not report_date:
            latest_date = db.session.query(db.func.max(WarehouseRemains.report_date)).scalar()
            if latest_date:
                query = query.filter(WarehouseRemains.report_date == latest_date)

        pagination = query.order_by(WarehouseRemains.nm_id, WarehouseRemains.warehouse_name).paginate(
            page=page, per_page=per_page, error_out=False
        )

        result = {
            'data': [item.to_dict() for item in pagination.items],
            'pagination': {
                'page': pagination.page,
                'per_page': pagination.per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            },
            'filters': {
                'nm_id': nm_id,
                'warehouse_name': warehouse_name,
                'brand': brand,
                'vendor_code': vendor_code,
                'report_date': report_date
            }
        }
        duration = (time.time() - start_time) * 1000
        log_event('INFO', 'get_warehouse_remains', f'Возвращено {len(pagination.items)} записей', duration_ms=duration)
        return jsonify(result)
    except Exception as e:
        log_event('ERROR', 'get_warehouse_remains', str(e))
        return jsonify({'error': str(e)}), 500


@warehouse_remains_bp.route('/<int:record_id>', methods=['GET'])
@jwt_required()
def get_warehouse_remains_by_id(record_id):
    try:
        record = WarehouseRemains.query.get(record_id)
        if not record:
            return jsonify({'error': 'Запись не найдена'}), 404
        return jsonify(record.to_dict())
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@warehouse_remains_bp.route('/export', methods=['GET'])
@jwt_required()
def export_warehouse_remains():
    start_time = time.time()
    try:
        nm_id = request.args.get('nm_id', type=int)
        warehouse_name = request.args.get('warehouse_name')
        report_date = request.args.get('report_date')
        get_all = request.args.get('get_all', 'false').lower() == 'true'

        query = WarehouseRemains.query
        if nm_id:
            query = query.filter(WarehouseRemains.nm_id == nm_id)
        if warehouse_name:
            query = query.filter(WarehouseRemains.warehouse_name.ilike(f'%{warehouse_name}%'))

        if report_date:
            try:
                rdate = datetime.strptime(report_date, '%Y-%m-%d').date()
                query = query.filter(WarehouseRemains.report_date == rdate)
            except:
                pass
        else:
            latest_date = db.session.query(db.func.max(WarehouseRemains.report_date)).scalar()
            if latest_date:
                query = query.filter(WarehouseRemains.report_date == latest_date)

        if get_all:
            records = query.order_by(WarehouseRemains.nm_id, WarehouseRemains.warehouse_name).all()
        else:
            limit = request.args.get('limit', 10000, type=int)
            records = query.limit(limit).all()

        if not records:
            return jsonify({'error': 'Нет данных для экспорта'}), 404

        data = []
        for r in records:
            data.append({
                'nm_id': r.nm_id,
                'Бренд': r.brand,
                'Предмет': r.subject_name,
                'Артикул продавца': r.vendor_code,
                'Баркод': r.barcode,
                'Размер': r.tech_size,
                'Объём, л': r.volume,
                'Склад': r.warehouse_name,
                'Количество': r.quantity,
                'Дата отчёта': r.report_date.isoformat() if r.report_date else '',
            })

        df = pd.DataFrame(data)
        output = BytesIO()
        with pd.ExcelWriter(output, engine='xlsxwriter') as writer:
            df.to_excel(writer, sheet_name='Остатки по складам', index=False)
            worksheet = writer.sheets['Остатки по складам']
            worksheet.set_column('A:A', 12)
            worksheet.set_column('B:B', 25)
            worksheet.set_column('C:C', 25)
            worksheet.set_column('D:D', 20)
            worksheet.set_column('E:E', 20)
            worksheet.set_column('F:F', 10)
            worksheet.set_column('G:G', 12)
            worksheet.set_column('H:H', 30)
            worksheet.set_column('I:I', 12)
            worksheet.set_column('J:J', 15)
        output.seek(0)
        filename = f"warehouse_remains_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.xlsx"
        return send_file(output, as_attachment=True, download_name=filename,
                         mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    except Exception as e:
        log_event('ERROR', 'export_warehouse_remains', str(e))
        return jsonify({'error': str(e)}), 500


@warehouse_remains_bp.route('/update', methods=['GET'])
@jwt_required()
def manual_update_warehouse_remains():
    try:
        def background():
            with current_app.app_context():
                fetch_warehouse_remains()
        thread = threading.Thread(target=background)
        thread.daemon = True
        thread.start()
        return jsonify({'status': 'success', 'message': 'Обновление запущено в фоновом режиме'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500