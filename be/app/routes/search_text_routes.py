import os
import re
import threading
import zipfile
import io
from datetime import datetime, timedelta, timezone
from pathlib import Path
from flask import Blueprint, request, jsonify, send_file
from flask_jwt_extended import jwt_required
import pyarrow.parquet as pq

from models import db, ProductActualSearchText
from utils.logger import log_event
from services.search_text_manager import SearchTextManager

search_text_bp = Blueprint('search_text', __name__)
SEARCH_QUERIES_DIR = Path("uploads/search_queries")
SEARCH_QUERIES_DIR.mkdir(parents=True, exist_ok=True)

# Глобальный менеджер будет передан из app.py при регистрации Blueprint
_search_manager = None

def set_search_manager(manager):
    global _search_manager
    _search_manager = manager


@search_text_bp.route('/search-texts-history/status', methods=['GET'])
@jwt_required()
def search_texts_history_status():
    try:
        target_date = request.args.get('date')
        if not target_date:
            return jsonify({"error": "Параметр 'date' обязателен"}), 400
        datetime.strptime(target_date, '%Y-%m-%d')
        
        filepath = SEARCH_QUERIES_DIR / f"search_texts_{target_date}.parquet"
        if filepath.exists():
            try:
                pf = pq.ParquetFile(filepath)
                records_count = pf.metadata.num_rows
            except:
                records_count = 0
            return jsonify({
                "date": target_date,
                "completed": True,
                "records_count": records_count,
                "exists_in_cache": True
            })
        else:
            is_loading = (target_date == _search_manager._current_load_date) if _search_manager else False
            return jsonify({
                "date": target_date,
                "completed": False,
                "records_count": 0,
                "exists_in_cache": False,
                "loading_in_progress": is_loading
            })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@search_text_bp.route('/search-texts-history/load', methods=['POST'])
@jwt_required()
def load_search_texts_history():
    """Массовая загрузка истории за указанную дату (POST JSON: {"date": "YYYY-MM-DD"})"""
    try:
        data = request.get_json()
        if not data or 'date' not in data:
            return jsonify({"error": "Не указана дата в поле 'date'"}), 400
        target_date = data['date']
        datetime.strptime(target_date, '%Y-%m-%d')
        
        def run_load():
            from flask import current_app
            with current_app.app_context():
                if _search_manager:
                    _search_manager.load_history_for_date(target_date)
        
        thread = threading.Thread(target=run_load)
        thread.daemon = True
        thread.start()
        return jsonify({"status": "Загрузка истории запущена", "date": target_date})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@search_text_bp.route('/search-texts/available-dates', methods=['GET'])
@jwt_required()
def search_texts_available_dates():
    try:
        if not SEARCH_QUERIES_DIR.exists():
            return jsonify({'dates': []})
        files = SEARCH_QUERIES_DIR.glob("search_texts_*.parquet")
        result = []
        for f in files:
            match = re.search(r'search_texts_(\d{4}-\d{2}-\d{2})\.parquet', f.name)
            if match:
                date_str = match.group(1)
                try:
                    pf = pq.ParquetFile(f)
                    records_count = pf.metadata.num_rows
                except:
                    records_count = 0
                result.append({
                    'date': date_str,
                    'exists_in_cache': True,
                    'size_bytes': f.stat().st_size,
                    'records_count': records_count
                })
        result.sort(key=lambda x: x['date'], reverse=True)
        return jsonify({'dates': result})
    except Exception as e:
        log_event('ERROR', 'search_texts_available_dates', str(e))
        return jsonify({"error": str(e)}), 500


@search_text_bp.route('/search-texts/export-daily', methods=['GET'])
@jwt_required()
def export_search_texts_daily():
    try:
        date_str = request.args.get('date')
        if not date_str:
            return jsonify({"error": "Parameter 'date' is required (format YYYY-MM-DD)"}), 400
        datetime.strptime(date_str, '%Y-%m-%d').date()
        filename = f"search_texts_{date_str}.parquet"
        filepath = SEARCH_QUERIES_DIR / filename
        if not filepath.exists():
            return jsonify({"error": f"No data for date {date_str}"}), 404
        return send_file(filepath, as_attachment=True, download_name=filename)
    except Exception as e:
        log_event('ERROR', 'export_search_texts_daily', str(e))
        return jsonify({"error": str(e)}), 500


@search_text_bp.route('/search-texts/export-range', methods=['GET'])
@jwt_required()
def export_search_texts_range():
    try:
        date_from_str = request.args.get('date_from')
        date_to_str = request.args.get('date_to')
        if not date_from_str or not date_to_str:
            return jsonify({"error": "date_from and date_to are required"}), 400
        date_from = datetime.strptime(date_from_str, '%Y-%m-%d').date()
        date_to = datetime.strptime(date_to_str, '%Y-%m-%d').date()

        zip_buffer = io.BytesIO()
        with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zipf:
            for filepath in SEARCH_QUERIES_DIR.glob("search_texts_*.parquet"):
                match = re.search(r'search_texts_(\d{4}-\d{2}-\d{2})\.parquet', filepath.name)
                if match:
                    d = datetime.strptime(match.group(1), '%Y-%m-%d').date()
                    if date_from <= d <= date_to:
                        zipf.write(filepath, arcname=filepath.name)

        zip_buffer.seek(0)
        filename = f"search_texts_{date_from_str}_{date_to_str}.zip"
        return send_file(zip_buffer, as_attachment=True, download_name=filename, mimetype='application/zip')
    except Exception as e:
        log_event('ERROR', 'export_search_texts_range', str(e))
        return jsonify({"error": str(e)}), 500


@search_text_bp.route('/search-texts-history/export', methods=['GET'])
@jwt_required()
def deprecated_export():
    return jsonify({
        "error": "This endpoint is deprecated and removed (single large file is no longer supported).",
        "message": "Please use /search-texts/export-daily?date=YYYY-MM-DD or /search-texts/export-range",
        "available_dates": "/search-texts/available-dates"
    }), 410


@search_text_bp.route('/search-texts', methods=['GET'])
@jwt_required()
def get_search_texts():
    try:
        nm_id = request.args.get('nm_id', type=int)
        report_date = request.args.get('date')
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 50, type=int)

        if not report_date:
            msk_now = datetime.now(timezone.utc) + timedelta(hours=3)
            report_date = msk_now.date().isoformat()
        else:
            datetime.strptime(report_date, '%Y-%m-%d')

        query = ProductActualSearchText.query.filter_by(report_date=report_date)
        if nm_id:
            query = query.filter_by(nm_id=nm_id)

        pagination = query.order_by(ProductActualSearchText.total_frequency.desc()).paginate(
            page=page, per_page=per_page, error_out=False
        )

        items = [r.to_dict() for r in pagination.items]

        return jsonify({
            'data': items,
            'pagination': {
                'page': pagination.page,
                'per_page': pagination.per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            },
            'date': report_date
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@search_text_bp.route('/search-texts/status', methods=['GET'])
@jwt_required()
def search_texts_status():
    """Статус фонового потока и статистика"""
    total = ProductActualSearchText.query.count()
    last_updated = db.session.query(db.func.max(ProductActualSearchText.last_updated)).scalar()
    return jsonify({
        'thread_alive': _search_manager and _search_manager.background_thread and _search_manager.background_thread.is_alive() if _search_manager else False,
        'total_records': total,
        'last_update': last_updated.isoformat() if last_updated else None,
        'report_date': (datetime.utcnow() + timedelta(hours=3)).date().isoformat()
    })


@search_text_bp.route('/search-texts/manager-status', methods=['GET'])
@jwt_required()
def manager_status():
    if not _search_manager:
        return jsonify({'started': False, 'paused': False, 'background_thread_alive': False})
    return jsonify({
        'started': _search_manager._started,
        'paused': _search_manager.is_paused(),
        'background_thread_alive': _search_manager.background_thread.is_alive() if _search_manager.background_thread else False
    })