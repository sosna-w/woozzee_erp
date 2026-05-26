import time
from datetime import datetime
from io import BytesIO
from flask import Blueprint, request, jsonify, send_file
from flask_jwt_extended import jwt_required
from sqlalchemy import func
import pandas as pd

from models import db, BoxTariff
from utils.logger import log_event
from services.box_tariff_service import fetch_box_tariffs

box_tariff_bp = Blueprint('box_tariff', __name__)


@box_tariff_bp.route('/box-tariffs', methods=['GET'])
@jwt_required()
def get_box_tariffs():
    """Получить тарифы коробов с возможностью фильтрации"""
    start_time = time.time()
    method_name = "get_box_tariffs"
    
    try:
        log_event('INFO', method_name, 'Запрос тарифов коробов')
        
        date = request.args.get('date')
        warehouse_name = request.args.get('warehouse_name')
        geo_name = request.args.get('geo_name')
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 100, type=int)
        
        if not date:
            date = datetime.now().strftime('%Y-%m-%d')
        
        query = BoxTariff.query.filter_by(date=date)
        
        if warehouse_name:
            query = query.filter(BoxTariff.warehouse_name.ilike(f'%{warehouse_name}%'))
        if geo_name:
            query = query.filter(BoxTariff.geo_name.ilike(f'%{geo_name}%'))
        
        query = query.order_by(BoxTariff.warehouse_name)
        pagination = query.paginate(page=page, per_page=per_page, error_out=False)
        tariffs = pagination.items
        
        # Если нет данных на указанную дату, пробуем получить самые свежие
        if not tariffs and date:
            latest_tariff = BoxTariff.query.order_by(BoxTariff.date.desc()).first()
            if latest_tariff:
                log_event('INFO', method_name, f'Нет данных на дату {date}, используем последнюю доступную дату {latest_tariff.date}')
                query = BoxTariff.query.filter_by(date=latest_tariff.date)
                if warehouse_name:
                    query = query.filter(BoxTariff.warehouse_name.ilike(f'%{warehouse_name}%'))
                if geo_name:
                    query = query.filter(BoxTariff.geo_name.ilike(f'%{geo_name}%'))
                query = query.order_by(BoxTariff.warehouse_name)
                pagination = query.paginate(page=page, per_page=per_page, error_out=False)
                tariffs = pagination.items
        
        result = {
            'tariffs': [tariff.to_dict() for tariff in tariffs],
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            },
            'filters': {
                'date': date,
                'warehouse_name': warehouse_name,
                'geo_name': geo_name
            }
        }
        
        available_dates = db.session.query(BoxTariff.date).distinct().order_by(BoxTariff.date.desc()).all()
        result['available_dates'] = [date[0] for date in available_dates]
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат тарифов коробов',
                 {
                     'page': page,
                     'per_page': per_page,
                     'total_items': pagination.total,
                     'returned_items': len(tariffs),
                     'date': date
                 },
                 duration_ms=duration,
                 records_processed=len(tariffs))
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении тарифов коробов',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@box_tariff_bp.route('/box-tariffs/<int:tariff_id>', methods=['GET'])
@jwt_required()
def get_box_tariff_by_id(tariff_id):
    """Получить тариф короба по ID"""
    start_time = time.time()
    method_name = "get_box_tariff_by_id"
    
    try:
        log_event('INFO', method_name, f'Запрос тарифа короба по ID {tariff_id}')
        
        tariff = BoxTariff.query.get(tariff_id)
        
        if not tariff:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Тариф с ID {tariff_id} не найден',
                     duration_ms=duration)
            return jsonify({"error": "Тариф не найден"}), 404
        
        result = tariff.to_dict()
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Успешный возврат тарифа ID {tariff_id}',
                 duration_ms=duration)
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка при получении тарифа ID {tariff_id}',
                 {'tariff_id': tariff_id, 'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@box_tariff_bp.route('/box-tariffs/by-warehouse/<string:warehouse_name>', methods=['GET'])
@jwt_required()
def get_box_tariffs_by_warehouse(warehouse_name):
    """Получить тарифы коробов по названию склада"""
    start_time = time.time()
    method_name = "get_box_tariffs_by_warehouse"
    
    try:
        log_event('INFO', method_name, f'Запрос тарифов коробов по складу {warehouse_name}')
        
        date = request.args.get('date')
        limit = request.args.get('limit', 10, type=int)
        
        query = BoxTariff.query.filter(BoxTariff.warehouse_name.ilike(f'%{warehouse_name}%'))
        
        if date:
            query = query.filter_by(date=date)
        
        query = query.order_by(BoxTariff.date.desc())
        tariffs = query.limit(limit).all()
        
        if not tariffs:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Тарифы для склада {warehouse_name} не найдены',
                     duration_ms=duration)
            return jsonify({
                'warehouse_name': warehouse_name,
                'message': 'Тарифы не найдены'
            }), 404
        
        tariffs_by_date = {}
        for tariff in tariffs:
            if tariff.date not in tariffs_by_date:
                tariffs_by_date[tariff.date] = []
            tariffs_by_date[tariff.date].append(tariff.to_dict())
        
        result = {
            'warehouse_name': warehouse_name,
            'total_tariffs': len(tariffs),
            'available_dates': list(tariffs_by_date.keys()),
            'tariffs_by_date': tariffs_by_date,
            'latest_tariff': tariffs[0].to_dict() if tariffs else None
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Успешный возврат тарифов для склада {warehouse_name}',
                 {'count': len(tariffs)}, duration_ms=duration)
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка при получении тарифов для склада {warehouse_name}',
                 {'warehouse_name': warehouse_name, 'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@box_tariff_bp.route('/box-tariffs/dates', methods=['GET'])
@jwt_required()
def get_box_tariffs_dates():
    """Получить список доступных дат с тарифами"""
    start_time = time.time()
    method_name = "get_box_tariffs_dates"
    
    try:
        log_event('INFO', method_name, 'Запрос списка дат с тарифами')
        
        dates = db.session.query(BoxTariff.date).distinct().order_by(BoxTariff.date.desc()).all()
        
        dates_with_stats = []
        for date_tuple in dates:
            date = date_tuple[0]
            tariffs_count = BoxTariff.query.filter_by(date=date).count()
            warehouses_count = db.session.query(BoxTariff.warehouse_name).filter_by(date=date).distinct().count()
            latest_update = db.session.query(func.max(BoxTariff.updated_at)).filter_by(date=date).scalar()
            
            dates_with_stats.append({
                'date': date,
                'tariffs_count': tariffs_count,
                'warehouses_count': warehouses_count,
                'latest_update': latest_update.isoformat() if latest_update else None
            })
        
        result = {
            'dates': dates_with_stats,
            'total_dates': len(dates_with_stats),
            'latest_date': dates_with_stats[0]['date'] if dates_with_stats else None
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат списка дат',
                 {'total_dates': len(dates_with_stats)}, duration_ms=duration)
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении списка дат',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@box_tariff_bp.route('/update-box-tariffs', methods=['GET'])
@jwt_required()
def update_box_tariffs_endpoint():
    """Ручной запуск обновления тарифов коробов (фоновый)"""
    start_time = time.time()
    method_name = "update_box_tariffs_endpoint"
    
    try:
        log_event('INFO', method_name, 'Ручной запуск обновления тарифов коробов')
        
        date = request.args.get('date')
        
        import threading
        def run_in_background():
            try:
                from flask import current_app
                with current_app.app_context():
                    fetch_box_tariffs(date)
            except Exception as e:
                log_event('ERROR', 'update_box_tariffs_background', 
                         'Ошибка при обновлении тарифов в фоне',
                         {'error': str(e)})
        
        thread = threading.Thread(target=run_in_background)
        thread.daemon = True
        thread.start()
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Запущено фоновое обновление тарифов коробов',
                 {'date': date}, duration_ms=duration)
        
        return jsonify({
            "status": "success",
            "message": "Обновление тарифов коробов запущено в фоновом режиме",
            "date": date or "текущая дата"
        })
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при запуске обновления тарифов',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@box_tariff_bp.route('/box-tariffs/stats', methods=['GET'])
@jwt_required()
def get_box_tariffs_stats():
    """Получить статистику по тарифам коробов"""
    start_time = time.time()
    method_name = "get_box_tariffs_stats"
    
    try:
        log_event('INFO', method_name, 'Запрос статистики по тарифам коробов')
        
        total_tariffs = BoxTariff.query.count()
        unique_dates = db.session.query(func.count(func.distinct(BoxTariff.date))).scalar()
        unique_warehouses = db.session.query(func.count(func.distinct(BoxTariff.warehouse_name))).scalar()
        unique_regions = db.session.query(func.count(func.distinct(BoxTariff.geo_name))).scalar()
        
        last_tariff = BoxTariff.query.order_by(BoxTariff.updated_at.desc()).first()
        last_update = last_tariff.updated_at if last_tariff else None
        
        region_stats = db.session.query(
            BoxTariff.geo_name,
            func.count(BoxTariff.id).label('tariff_count')
        ).group_by(BoxTariff.geo_name).order_by(func.count(BoxTariff.id).desc()).all()
        
        warehouse_stats = db.session.query(
            BoxTariff.warehouse_name,
            func.count(BoxTariff.id).label('tariff_count')
        ).group_by(BoxTariff.warehouse_name).order_by(func.count(BoxTariff.id).desc()).limit(10).all()
        
        result = {
            'total_tariffs': total_tariffs,
            'unique_dates': unique_dates,
            'unique_warehouses': unique_warehouses,
            'unique_regions': unique_regions,
            'last_update': last_update.isoformat() if last_update else None,
            'region_statistics': [
                {'region': region, 'tariff_count': count} for region, count in region_stats
            ],
            'top_warehouses': [
                {'warehouse': warehouse, 'tariff_count': count} for warehouse, count in warehouse_stats
            ],
            'system_time': datetime.utcnow().isoformat()
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат статистики по тарифам',
                 duration_ms=duration)
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении статистики по тарифам',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@box_tariff_bp.route('/box-tariffs/export', methods=['GET'])
@jwt_required()
def export_box_tariffs():
    """Экспортировать тарифы коробов в XLSX"""
    start_time = time.time()
    method_name = "export_box_tariffs"
    
    try:
        log_event('INFO', method_name, 'Экспорт тарифов коробов в XLSX')
        
        date = request.args.get('date')
        warehouse_name = request.args.get('warehouse_name')
        
        query = BoxTariff.query
        if date:
            query = query.filter_by(date=date)
        if warehouse_name:
            query = query.filter(BoxTariff.warehouse_name.ilike(f'%{warehouse_name}%'))
        
        tariffs = query.order_by(BoxTariff.date.desc(), BoxTariff.warehouse_name).all()
        
        if not tariffs:
            log_event('WARNING', method_name, 'Нет данных для экспорта')
            return jsonify({"error": "Нет данных для экспорта"}), 404
        
        tariffs_data = []
        for tariff in tariffs:
            tariffs_data.append({
                'Дата': tariff.date,
                'Склад': tariff.warehouse_name,
                'Регион': tariff.geo_name,
                'Логистика база': tariff.box_delivery_base,
                'Коэф. логистики %': tariff.box_delivery_coef_expr,
                'Логистика доп.литр': tariff.box_delivery_liter,
                'FBS база': tariff.box_delivery_marketplace_base,
                'Коэф. FBS %': tariff.box_delivery_marketplace_coef_expr,
                'FBS доп.литр': tariff.box_delivery_marketplace_liter,
                'Хранение база': tariff.box_storage_base,
                'Коэф. хранения %': tariff.box_storage_coef_expr,
                'Хранение доп.литр': tariff.box_storage_liter,
                'След.тариф с': tariff.dt_next_box,
                'Текущий до': tariff.dt_till_max,
                'Дата обновления': tariff.updated_at.isoformat() if tariff.updated_at else ''
            })
        
        df_tariffs = pd.DataFrame(tariffs_data)
        output = BytesIO()
        with pd.ExcelWriter(output, engine='xlsxwriter') as writer:
            df_tariffs.to_excel(writer, sheet_name='Тарифы коробов', index=False)
            worksheet = writer.sheets['Тарифы коробов']
            worksheet.set_column('A:A', 12)
            worksheet.set_column('B:B', 25)
            worksheet.set_column('C:C', 30)
            worksheet.set_column('D:L', 15)
            worksheet.set_column('M:N', 12)
            worksheet.set_column('O:O', 20)
        
        output.seek(0)
        filename = f"тарифы_коробов_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.xlsx"
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный экспорт тарифов коробов',
                 {'count': len(tariffs)}, duration_ms=duration, records_processed=len(tariffs))
        
        return send_file(
            output,
            as_attachment=True,
            download_name=filename,
            mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        )
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при экспорте тарифов коробов',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500