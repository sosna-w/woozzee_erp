import time
import threading
import re
from datetime import date, datetime, timedelta
from flask import Blueprint, request, jsonify, send_file
from flask_jwt_extended import jwt_required
from sqlalchemy import func
from io import BytesIO
import pandas as pd

from models import db, ReportDetail, SalesFunnelReport
from utils.logger import log_event
from report_fetcher import WBReportFetcher
from services.sales_funnel_service import fetch_sales_funnel_period, enrich_all_existing_reports

report_bp = Blueprint('report', __name__)


# ========== ЕЖЕДНЕВНЫЕ ОТЧЁТЫ ==========

@report_bp.route('/reports/daily/load', methods=['POST'])
@jwt_required()
def load_daily_reports():
    """Загрузка ежедневных отчетов за указанный период (фоново)"""
    start_time = time.time()
    method_name = "load_daily_reports"
    
    try:
        log_event('INFO', method_name, 'Запрос на загрузку ежедневных отчетов')
        data = request.get_json()
        if not data:
            return jsonify({"error": "Данные не предоставлены"}), 400
        
        date_from = data.get('date_from')
        date_to = data.get('date_to')
        if not date_from or not date_to:
            return jsonify({"error": "date_from и date_to обязательны"}), 400
        
        datetime.strptime(date_from, "%Y-%m-%d")
        datetime.strptime(date_to, "%Y-%m-%d")
        
        def background_load():
            try:
                from flask import current_app
                with current_app.app_context():
                    fetcher = WBReportFetcher()
                    result = fetcher.load_reports_for_period(date_from, date_to)
                    log_event('INFO', method_name, 'Загрузка отчетов завершена',
                             result, records_processed=result['saved_records'])
            except Exception as e:
                log_event('ERROR', method_name, 'Ошибка при фоновой загрузке отчетов', {'error': str(e)})
        
        thread = threading.Thread(target=background_load)
        thread.daemon = True
        thread.start()
        
        return jsonify({
            "status": "success",
            "message": "Загрузка отчетов запущена в фоновом режиме",
            "period": {"date_from": date_from, "date_to": date_to}
        })
        
    except Exception as e:
        log_event('ERROR', method_name, str(e))
        return jsonify({"error": str(e)}), 500


@report_bp.route('/reports/daily', methods=['GET'])
@jwt_required()
def get_daily_reports():
    """Получение ежедневных отчетов с фильтрацией по дате"""
    start_time = time.time()
    try:
        date_from = request.args.get('dateFrom')
        date_to = request.args.get('dateTo')
        
        if not date_from:
            date_from = (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d')
        if not date_to:
            date_to = datetime.now().strftime('%Y-%m-%d')
        
        get_all = request.args.get('get_all', 'false').lower() == 'true'
        no_limit = request.args.get('no_limit', 'false').lower() == 'true'
        
        query = ReportDetail.query.filter(
            ReportDetail.report_date >= date_from,
            ReportDetail.report_date <= date_to
        )
        
        nm_id = request.args.get('nm_id')
        if nm_id and nm_id.isdigit():
            query = query.filter(ReportDetail.nm_id == int(nm_id))
        
        sa_name = request.args.get('sa_name')
        if sa_name:
            query = query.filter(ReportDetail.sa_name.ilike(f'%{sa_name}%'))
        
        srid = request.args.get('srid')
        if srid:
            query = query.filter(ReportDetail.srid.ilike(f'%{srid}%'))
        
        doc_type = request.args.get('doc_type_name')
        if doc_type:
            query = query.filter(ReportDetail.doc_type_name == doc_type)
        
        type_fb = request.args.get('type_fb')
        if type_fb:
            query = query.filter(ReportDetail.type_fb == type_fb)
        
        model_fields = [column.name for column in ReportDetail.__table__.columns]
        
        if get_all:
            all_reports = query.order_by(ReportDetail.report_date.desc(), ReportDetail.id.desc()).all()
            reports_data = []
            for report in all_reports:
                ordered_dict = {}
                for field in model_fields:
                    value = getattr(report, field, None)
                    if isinstance(value, (datetime, date)):
                        ordered_dict[field] = value.isoformat()
                    else:
                        ordered_dict[field] = value
                reports_data.append(ordered_dict)
            
            response_data = {
                'status': 'success',
                'data': reports_data,
                'pagination': {
                    'page': 1,
                    'per_page': len(reports_data),
                    'total': len(reports_data),
                    'pages': 1,
                    'has_next': False,
                    'has_prev': False,
                    'note': 'Включен режим get_all=true - получены все данные без ограничений'
                },
                'filters': {
                    'date_from': date_from,
                    'date_to': date_to,
                    'nm_id': nm_id,
                    'sa_name': sa_name,
                    'srid': srid,
                    'doc_type_name': doc_type,
                    'type_fb': type_fb,
                    'get_all': True,
                    'no_limit': no_limit
                },
                'meta': {
                    'records_count': len(reports_data),
                    'query_time_ms': (time.time() - start_time) * 1000,
                    'fields_order': model_fields
                }
            }
        else:
            page = request.args.get('page', 1, type=int)
            if no_limit:
                per_page = query.count()
            else:
                per_page = request.args.get('per_page', 100000, type=int)
                max_per_page = 1000000
                per_page = min(per_page, max_per_page)
            
            pagination = query.order_by(ReportDetail.report_date.desc(), ReportDetail.id.desc()).paginate(
                page=page, per_page=per_page, error_out=False
            )
            
            reports_data = []
            for report in pagination.items:
                ordered_dict = {}
                for field in model_fields:
                    value = getattr(report, field, None)
                    if isinstance(value, (datetime, date)):
                        ordered_dict[field] = value.isoformat()
                    else:
                        ordered_dict[field] = value
                reports_data.append(ordered_dict)
            
            response_data = {
                'status': 'success',
                'data': reports_data,
                'pagination': {
                    'page': pagination.page,
                    'per_page': pagination.per_page,
                    'total': pagination.total,
                    'pages': pagination.pages,
                    'has_next': pagination.has_next,
                    'has_prev': pagination.has_prev,
                    'note': 'no_limit=true' if no_limit else f'per_page ограничен {max_per_page if per_page >= max_per_page else per_page}'
                },
                'filters': {
                    'date_from': date_from,
                    'date_to': date_to,
                    'nm_id': nm_id,
                    'sa_name': sa_name,
                    'srid': srid,
                    'doc_type_name': doc_type,
                    'type_fb': type_fb,
                    'get_all': False,
                    'no_limit': no_limit
                },
                'meta': {
                    'records_count': len(reports_data),
                    'query_time_ms': (time.time() - start_time) * 1000,
                    'fields_order': model_fields
                }
            }
        
        log_event('INFO', 'get_daily_reports', 'Ежедневные отчеты успешно получены',
                 {'date_from': date_from, 'date_to': date_to, 'records_count': len(reports_data)})
        return jsonify(response_data)
        
    except Exception as e:
        log_event('ERROR', 'get_daily_reports', str(e))
        return jsonify({'status': 'error', 'message': f'Ошибка при получении отчетов: {str(e)}'}), 500


@report_bp.route('/reports/sync/info', methods=['GET'])
@jwt_required()
def get_sync_info():
    """Получение информации для синхронизации"""
    try:
        last_report = ReportDetail.query.order_by(ReportDetail.updated_at.desc()).first()
        info = {
            'last_update': last_report.updated_at.isoformat() if last_report else datetime.utcnow().isoformat(),
            'total_records': ReportDetail.query.count(),
            'last_update_id': last_report.id if last_report else None,
        }
        return jsonify(info)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@report_bp.route('/reports/sync/changes', methods=['GET'])
@jwt_required()
def get_sync_changes():
    """Получение изменений с определенной даты"""
    try:
        since_date_str = request.args.get('since')
        if not since_date_str:
            return jsonify({'error': 'Параметр since обязателен'}), 400
        
        since_date = datetime.fromisoformat(since_date_str.replace('Z', '+00:00'))
        changed_reports = ReportDetail.query.filter(
            ReportDetail.updated_at >= since_date
        ).order_by(ReportDetail.updated_at.asc()).all()
        reports_data = [report.to_dict() for report in changed_reports]
        return jsonify({
            'status': 'success',
            'data': reports_data,
            'total': len(reports_data),
            'last_update': datetime.utcnow().isoformat()
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@report_bp.route('/reports/check-dates', methods=['POST'])
@jwt_required()
def check_dates():
    """Быстрая проверка наличия записей по датам YYYY-MM-DD"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Данные не предоставлены"}), 400
        
        dates = data.get('dates')
        if not dates or not isinstance(dates, list):
            return jsonify({"error": "Параметр 'dates' обязателен и должен быть массивом"}), 400
        
        for date_str in dates:
            if not re.match(r'^\d{4}-\d{2}-\d{2}$', date_str):
                return jsonify({"error": f"Неверный формат даты: {date_str}. Используйте YYYY-MM-DD"}), 400
        
        date_objects = [datetime.strptime(d, "%Y-%m-%d").date() for d in dates]
        existing_dates = db.session.query(
            func.date(ReportDetail.rr_dt).label('date_only')
        ).filter(
            func.date(ReportDetail.rr_dt).in_(date_objects),
            ReportDetail.rr_dt.isnot(None)
        ).distinct().all()
        existing_date_set = {d.date_only for d in existing_dates}
        
        result = {date_str: (date_objects[i] in existing_date_set) for i, date_str in enumerate(dates)}
        return jsonify(result)
        
    except Exception as e:
        log_event('ERROR', 'check_dates', str(e))
        return jsonify({"error": str(e)}), 500


@report_bp.route('/reports/enrich-all', methods=['POST'])
@jwt_required()
def enrich_all_reports():
    """Обогащение всех существующих записей в базе"""
    try:
        result = enrich_all_existing_reports()
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ========== ВОРОНКА ПРОДАЖ ==========

@report_bp.route('/reports/sales-funnel/update', methods=['POST'])
@jwt_required()
def manual_sales_funnel_update():
    """Ручной запуск обновления воронки продаж за последние 30 дней"""
    try:
        end = date.today()
        start = end - timedelta(days=30)
        log_event('INFO', 'manual_sales_funnel', f'Ручной запуск за {start} - {end}')
        saved = fetch_sales_funnel_period(start, end, nm_ids=None, delete_old=True)
        return jsonify({'status': 'success', 'saved_records': saved})
    except Exception as e:
        log_event('ERROR', 'manual_sales_funnel', str(e))
        return jsonify({'status': 'error', 'message': str(e)}), 500


@report_bp.route('/reports/sales-funnel', methods=['GET'])
@jwt_required()
def get_sales_funnel():
    """Получить данные воронки продаж с фильтрацией. ?get_all=true - все записи без пагинации."""
    try:
        date_from = request.args.get('date_from')
        date_to = request.args.get('date_to')
        nm_id = request.args.get('nm_id', type=int)
        get_all = request.args.get('get_all', 'false').lower() == 'true'

        query = SalesFunnelReport.query
        if date_from:
            query = query.filter(SalesFunnelReport.date >= datetime.strptime(date_from, '%Y-%m-%d').date())
        if date_to:
            query = query.filter(SalesFunnelReport.date <= datetime.strptime(date_to, '%Y-%m-%d').date())
        if nm_id:
            query = query.filter(SalesFunnelReport.nm_id == nm_id)

        if get_all:
            all_records = query.order_by(SalesFunnelReport.date.desc(), SalesFunnelReport.nm_id).all()
            return jsonify({
                'data': [r.to_dict() for r in all_records],
                'total': len(all_records),
                'filters': {'date_from': date_from, 'date_to': date_to, 'nm_id': nm_id}
            })

        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 100, type=int)
        pagination = query.order_by(SalesFunnelReport.date.desc(), SalesFunnelReport.nm_id).paginate(
            page=page, per_page=per_page, error_out=False
        )
        return jsonify({
            'data': [r.to_dict() for r in pagination.items],
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            }
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@report_bp.route('/reports/sales-funnel/parquet', methods=['GET'])
@jwt_required()
def export_sales_funnel_parquet():
    """Экспорт данных воронки продаж в формате Parquet."""
    try:
        date_from = request.args.get('date_from')
        date_to = request.args.get('date_to')
        nm_id = request.args.get('nm_id', type=int)

        query = SalesFunnelReport.query
        if date_from:
            query = query.filter(SalesFunnelReport.date >= datetime.strptime(date_from, '%Y-%m-%d').date())
        if date_to:
            query = query.filter(SalesFunnelReport.date <= datetime.strptime(date_to, '%Y-%m-%d').date())
        if nm_id:
            query = query.filter(SalesFunnelReport.nm_id == nm_id)

        records = query.order_by(SalesFunnelReport.date.desc(), SalesFunnelReport.nm_id).all()
        if not records:
            return jsonify({'error': 'Нет данных для указанных фильтров'}), 404

        data = [r.to_dict() for r in records]
        df = pd.DataFrame(data)
        df['date'] = pd.to_datetime(df['date'])
        df['created_at'] = pd.to_datetime(df['created_at'])
        buffer = BytesIO()
        df.to_parquet(buffer, index=False, compression='snappy')
        buffer.seek(0)
        filename = f"sales_funnel_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.parquet"
        return send_file(buffer, as_attachment=True, download_name=filename, mimetype='application/octet-stream')
    except Exception as e:
        log_event('ERROR', 'export_sales_funnel_parquet', str(e))
        return jsonify({'error': str(e)}), 500