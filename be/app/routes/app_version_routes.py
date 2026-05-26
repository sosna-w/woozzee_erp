import os
import re
import time
from datetime import datetime, timedelta
from pathlib import Path
from flask import Blueprint, request, jsonify, send_file, send_from_directory
from flask_jwt_extended import jwt_required
from sqlalchemy import func

from models import db, AppVersion
from utils.logger import log_event

app_version_bp = Blueprint('app_version', __name__)


@app_version_bp.route('/app/version/latest', methods=['GET'])
@jwt_required()
def get_latest_version():
    """Получить информацию о последней версии приложения"""
    start_time = time.time()
    method_name = "get_latest_version"
    
    try:
        log_event('INFO', method_name, 'Запрос последней версии приложения')
        
        latest_version = AppVersion.query.order_by(
            db.desc(db.func.cast(db.func.regexp_replace(AppVersion.version, '[^0-9.]', '', 'g'), db.String))
        ).first()
        
        if not latest_version:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, 'Версии приложения не найдены', duration_ms=duration)
            return jsonify({
                "status": "no_versions",
                "message": "Версии приложения не найдены"
            }), 404
        
        result = latest_version.to_dict()
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат последней версии',
                 {'version': latest_version.version}, duration_ms=duration)
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении последней версии',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@app_version_bp.route('/app/version/check/<string:current_version>', methods=['GET'])
@jwt_required()
def check_version_update(current_version):
    """Проверить наличие обновления для указанной версии"""
    start_time = time.time()
    method_name = "check_version_update"
    
    try:
        log_event('INFO', method_name, f'Проверка обновления для версии {current_version}')
        
        all_versions = AppVersion.query.order_by(
            db.desc(db.func.cast(db.func.regexp_replace(AppVersion.version, '[^0-9.]', '', 'g'), db.String))
        ).all()
        
        if not all_versions:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, 'Версии приложения не найдены', duration_ms=duration)
            return jsonify({
                "update_available": False,
                "message": "Версии приложения не найдены"
            })
        
        latest_version = all_versions[0]
        update_available = latest_version.version != current_version
        
        result = {
            "update_available": update_available,
            "current_version": current_version,
            "latest_version": latest_version.to_dict() if update_available else None
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Проверка обновления завершена',
                 {'update_available': update_available, 'current': current_version, 'latest': latest_version.version},
                 duration_ms=duration)
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при проверке обновления',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@app_version_bp.route('/app/version/download/<string:filename>', methods=['GET'])
@jwt_required()
def download_app_version(filename):
    """Скачать установочный файл приложения"""
    start_time = time.time()
    method_name = "download_app_version"
    
    try:
        log_event('INFO', method_name, f'Запрос на скачивание файла {filename}')
        file_path = os.path.join('uploads', 'app_versions', filename)
        
        if not os.path.exists(file_path):
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Файл не найден: {filename}', duration_ms=duration)
            return jsonify({"error": "Файл не найден"}), 404
        
        version = AppVersion.query.filter_by(filename=filename).first()
        if version:
            version.download_count += 1
            db.session.commit()
            log_event('INFO', method_name, f'Счетчик скачиваний увеличен для версии {version.version}')
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Начало скачивания файла {filename}',
                 {'file_size': os.path.getsize(file_path) if os.path.exists(file_path) else 0},
                 duration_ms=duration)
        
        return send_file(
            file_path,
            as_attachment=True,
            download_name=filename,
            mimetype='application/octet-stream'
        )
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при скачивании файла',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@app_version_bp.route('/app/versions', methods=['GET'])
@jwt_required()
def get_all_app_versions():
    """Получить список всех версий приложения"""
    start_time = time.time()
    method_name = "get_all_app_versions"
    
    try:
        log_event('INFO', method_name, 'Запрос списка всех версий приложения')
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 10, type=int)
        
        query = AppVersion.query.order_by(AppVersion.release_date.desc())
        pagination = query.paginate(page=page, per_page=per_page, error_out=False)
        versions = pagination.items
        
        result = {
            'versions': [version.to_dict() for version in versions],
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
        log_event('INFO', method_name, 'Успешный возврат списка версий',
                 {'page': page, 'per_page': per_page, 'total_versions': pagination.total, 'returned_versions': len(versions)},
                 duration_ms=duration, records_processed=len(versions))
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении списка версий',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@app_version_bp.route('/app/version/stats', methods=['GET'])
@jwt_required()
def get_app_version_stats():
    """Получить статистику по версиям приложения"""
    start_time = time.time()
    method_name = "get_app_version_stats"
    
    try:
        log_event('INFO', method_name, 'Запрос статистики по версиям приложения')
        
        total_versions = AppVersion.query.count()
        total_downloads = db.session.query(func.sum(AppVersion.download_count)).scalar() or 0
        latest_version = AppVersion.query.order_by(AppVersion.release_date.desc()).first()
        most_downloaded = AppVersion.query.order_by(AppVersion.download_count.desc()).first()
        
        month_stats = db.session.query(
            func.strftime('%Y-%m', AppVersion.release_date).label('month'),
            func.count(AppVersion.id).label('versions_count'),
            func.sum(AppVersion.download_count).label('downloads_count')
        ).group_by('month').order_by('month').all()
        
        result = {
            'total_versions': total_versions,
            'total_downloads': total_downloads,
            'latest_version': latest_version.to_dict() if latest_version else None,
            'most_downloaded_version': most_downloaded.to_dict() if most_downloaded else None,
            'monthly_statistics': [
                {
                    'month': stat.month,
                    'versions_count': stat.versions_count,
                    'downloads_count': stat.downloads_count or 0
                } for stat in month_stats
            ]
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат статистики', duration_ms=duration)
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении статистики',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@app_version_bp.route('/app/version/info', methods=['POST'])
@jwt_required()
def add_app_version_info():
    """Добавить информацию о новой версии приложения (без загрузки файла)"""
    start_time = time.time()
    method_name = "add_app_version_info"
    
    try:
        log_event('INFO', method_name, 'Запрос на добавление информации о версии (без файла)')
        
        secret_key = request.headers.get('X-Secret-Key')
        if secret_key != 'Fyukbqcrbq1':
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, 'Неверный секретный ключ', duration_ms=duration)
            return jsonify({"error": "Неверный секретный ключ"}), 401
        
        data = request.get_json()
        if not data:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, 'Нет данных в запросе', duration_ms=duration)
            return jsonify({"error": "Данные не предоставлены"}), 400
        
        version = data.get('version')
        filename = data.get('filename')
        title = data.get('title')
        description = data.get('description')
        
        if not all([version, filename, title, description]):
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, 'Не все обязательные поля заполнены', duration_ms=duration)
            return jsonify({
                "error": "Не все обязательные поля заполнены",
                "required_fields": ["version", "filename", "title", "description"],
                "received": {"version": version, "filename": filename, "title": title, "description": description}
            }), 400
        
        existing_version = AppVersion.query.filter_by(version=version).first()
        if existing_version:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Версия {version} уже существует', duration_ms=duration)
            return jsonify({"error": f"Версия {version} уже существует", "existing_version": existing_version.to_dict()}), 409
        
        file_path = os.path.join('uploads', 'app_versions', filename)
        if not os.path.exists(file_path):
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Файл не найден: {filename}', duration_ms=duration)
            return jsonify({
                "error": f"Файл {filename} не найден в директории uploads/app_versions/",
                "details": "Загрузите файл через FileZilla в папку uploads/app_versions/ перед добавлением информации о версии"
            }), 400
        
        file_size = os.path.getsize(file_path)
        if file_size == 0:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Файл пустой: {filename}', duration_ms=duration)
            return jsonify({"error": f"Файл {filename} пустой", "details": "Файл должен содержать данные"}), 400
        
        new_version = AppVersion(
            version=version,
            filename=filename,
            title=title,
            description=description,
            release_date=datetime.utcnow()
        )
        db.session.add(new_version)
        db.session.commit()
        
        duration = (time.time() - start_time) * 1000
        result = {
            "status": "success",
            "message": f"Информация о версии {version} успешно добавлена",
            "version": new_version.to_dict(),
            "file_info": {
                "path": file_path,
                "size_bytes": file_size,
                "size_mb": round(file_size / (1024 * 1024), 2)
            }
        }
        log_event('INFO', method_name, f'Информация о версии добавлена: {version}',
                 {'version': version, 'filename': filename, 'file_size': file_size, 'title': title}, duration_ms=duration)
        return jsonify(result)
        
    except Exception as e:
        db.session.rollback()
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при добавлении информации о версии',
                 {'error': str(e), 'traceback': traceback.format_exc()}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@app_version_bp.route('/app/version', methods=['POST'])
@jwt_required()
def add_app_version():
    """Добавить новую версию приложения (требуется секретный ключ)"""
    start_time = time.time()
    method_name = "add_app_version"
    
    try:
        log_event('INFO', method_name, 'Запрос на добавление новой версии приложения')
        
        secret_key = request.headers.get('X-Secret-Key')
        if secret_key != 'Fyukbqcrbq1':
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, 'Неверный секретный ключ', duration_ms=duration)
            return jsonify({"error": "Неверный секретный ключ"}), 401
        
        if 'file' not in request.files:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, 'Файл не найден в запросе', duration_ms=duration)
            return jsonify({"error": "Файл не найден в запросе"}), 400
        
        file = request.files['file']
        if file.filename == '':
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, 'Имя файла пустое', duration_ms=duration)
            return jsonify({"error": "Имя файла пустое"}), 400
        
        version = request.form.get('version')
        title = request.form.get('title')
        description = request.form.get('description')
        
        if not all([version, title, description]):
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, 'Не все обязательные поля заполнены', duration_ms=duration)
            return jsonify({"error": "Не все обязательные поля заполнены (version, title, description)"}), 400
        
        existing_version = AppVersion.query.filter_by(version=version).first()
        if existing_version:
            duration = (time.time() - start_time) * 1000
            log_event('WARNING', method_name, f'Версия {version} уже существует', duration_ms=duration)
            return jsonify({"error": f"Версия {version} уже существует"}), 409
        
        filename = f"Woozzee_WB_Setup_{version}.exe"
        file_path = os.path.join('uploads', 'app_versions', filename)
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        file.save(file_path)
        log_event('INFO', method_name, f'Файл сохранен: {file_path}', {'file_size': os.path.getsize(file_path)})
        
        new_version = AppVersion(
            version=version,
            filename=filename,
            title=title,
            description=description,
            release_date=datetime.utcnow()
        )
        db.session.add(new_version)
        db.session.commit()
        
        duration = (time.time() - start_time) * 1000
        result = {
            "status": "success",
            "message": f"Версия {version} успешно добавлена",
            "version": new_version.to_dict()
        }
        log_event('INFO', method_name, f'Новая версия добавлена: {version}', result, duration_ms=duration)
        return jsonify(result)
        
    except Exception as e:
        db.session.rollback()
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при добавлении версии',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500