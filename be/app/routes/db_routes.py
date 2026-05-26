import re
from datetime import datetime
from pathlib import Path
from flask import Blueprint, request, jsonify, send_from_directory
from flask_jwt_extended import jwt_required
from utils.logger import log_event

db_bp = Blueprint('db', __name__)


@db_bp.route('/db_finance', methods=['GET'])
@jwt_required()
def db_finance():
    """
    Эндпоинт для получения обновленной базы данных.
    Клиент отправляет GET запрос с параметром datetime в формате YYYYMMDD_HHMMSS
    или YYYY-MM-DD HH:MM:SS
    Если версия клиента старше, чем последний файл - отдаем файл
    """
    try:
        db_dir = Path("/home/flaskapp/app/uploads/db")
        
        if not db_dir.exists():
            log_event('WARNING', 'db_finance', 'Директория с базами данных не найдена')
            return jsonify({
                'status': 'error',
                'message': 'Директория с базами данных не найдена'
            }), 404
        
        client_datetime_str = request.args.get('datetime')
        if not client_datetime_str:
            client_datetime_str = request.args.get('date')
            if client_datetime_str:
                log_event('INFO', 'db_finance', 'Используется устаревший параметр "date", используйте "datetime"')
            else:
                return jsonify({
                    'status': 'error',
                    'message': 'Параметр datetime обязателен. Формат: YYYYMMDD_HHMMSS или YYYY-MM-DD HH:MM:SS'
                }), 400
        
        try:
            if '_' in client_datetime_str and len(client_datetime_str) == 15:
                client_datetime = datetime.strptime(client_datetime_str, "%Y%m%d_%H%M%S")
            elif ' ' in client_datetime_str and len(client_datetime_str) == 19:
                client_datetime = datetime.strptime(client_datetime_str, "%Y-%m-%d %H:%M:%S")
            elif len(client_datetime_str) == 8 and client_datetime_str.isdigit():
                client_datetime = datetime.strptime(client_datetime_str, "%Y%m%d")
                log_event('INFO', 'db_finance', 'Использован формат только с датой, время установлено в 00:00:00')
            elif len(client_datetime_str) == 10 and '-' in client_datetime_str:
                client_datetime = datetime.strptime(client_datetime_str, "%Y-%m-%d")
                log_event('INFO', 'db_finance', 'Использован формат только с датой, время установлено в 00:00:00')
            else:
                return jsonify({
                    'status': 'error',
                    'message': f'Неподдерживаемый формат даты и времени: {client_datetime_str}. ' +
                              f'Используйте YYYYMMDD_HHMMSS или YYYY-MM-DD HH:MM:SS'
                }), 400
        except ValueError as e:
            return jsonify({
                'status': 'error',
                'message': f'Ошибка парсинга даты и времени: {str(e)}'
            }), 400
        
        db_files = list(db_dir.glob("db_to_client_*.parquet"))
        if not db_files:
            log_event('INFO', 'db_finance', 'Нет файлов баз данных в директории')
            return jsonify({
                'status': 'success',
                'message': 'Нет доступных баз для обновления',
                'available': False
            }), 200
        
        latest_file = None
        latest_datetime = None
        
        for file_path in db_files:
            match = re.search(r'db_to_client_(\d{8})_(\d{6})\.parquet', file_path.name)
            if match:
                file_date_str = match.group(1)
                file_time_str = match.group(2)
                try:
                    file_datetime = datetime.strptime(f"{file_date_str}_{file_time_str}", "%Y%m%d_%H%M%S")
                    if latest_datetime is None or file_datetime > latest_datetime:
                        latest_datetime = file_datetime
                        latest_file = file_path
                except ValueError:
                    continue
        
        if latest_file is None:
            log_event('WARNING', 'db_finance', 'Не удалось найти валидные файлы баз данных')
            return jsonify({
                'status': 'success',
                'message': 'Нет доступных баз для обновления',
                'available': False
            }), 200
        
        log_event('INFO', 'db_finance', 'Сравнение даты и времени', {
            'client_datetime': client_datetime.strftime("%Y-%m-%d %H:%M:%S"),
            'latest_db_datetime': latest_datetime.strftime("%Y-%m-%d %H:%M:%S"),
            'latest_file': latest_file.name
        })
        
        if client_datetime < latest_datetime:
            log_event('INFO', 'db_finance', 'Отдаем файл клиенту', {
                'client_datetime': client_datetime.strftime("%Y-%m-%d %H:%M:%S"),
                'db_datetime': latest_datetime.strftime("%Y-%m-%d %H:%M:%S"),
                'filename': latest_file.name,
                'file_size_mb': round(latest_file.stat().st_size / (1024 * 1024), 2)
            })
            return send_from_directory(
                directory=str(db_dir),
                path=latest_file.name,
                as_attachment=True,
                download_name=f"db_to_client_{latest_datetime.strftime('%Y%m%d_%H%M%S')}.parquet"
            )
        else:
            log_event('INFO', 'db_finance', 'Клиент имеет актуальную версию', {
                'client_datetime': client_datetime.strftime("%Y-%m-%d %H:%M:%S"),
                'db_datetime': latest_datetime.strftime("%Y-%m-%d %H:%M:%S")
            })
            return jsonify({
                'status': 'success',
                'message': 'У вас актуальная версия базы данных',
                'available': False,
                'client_datetime': client_datetime.strftime("%Y-%m-%d %H:%M:%S"),
                'latest_db_datetime': latest_datetime.strftime("%Y-%m-%d %H:%M:%S")
            }), 200
            
    except Exception as e:
        log_event('ERROR', 'db_finance', 'Ошибка при обработке запроса', {
            'error_details': str(e),
            'traceback': traceback.format_exc()
        })
        return jsonify({
            'status': 'error',
            'message': f'Внутренняя ошибка сервера: {str(e)}'
        }), 500