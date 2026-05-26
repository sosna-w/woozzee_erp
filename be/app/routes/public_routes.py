import os
import re
from pathlib import Path
from flask import Blueprint, send_from_directory, jsonify, send_file
from flask_jwt_extended import jwt_required
from utils.logger import log_event

public_bp = Blueprint('public', __name__)


@public_bp.route('/app', methods=['GET'])
@jwt_required()
def landing_page():
    """
    Отдаёт главную страницу сайта (landing) из папки uploads/landing/index.html
    """
    try:
        return send_from_directory('uploads/landing', 'index.html')
    except FileNotFoundError:
        return jsonify({"error": "Landing page not found"}), 404
    except Exception as e:
        return jsonify({"error": f"Internal server error: {str(e)}"}), 500


@public_bp.route('/logo.png', methods=['GET'])
@jwt_required()
def landing_logo():
    """
    Отдаёт файл логотипа для лендинга.
    """
    try:
        return send_from_directory('uploads/landing', 'logo.png')
    except FileNotFoundError:
        return jsonify({"error": "Logo not found"}), 404
    except Exception as e:
        return jsonify({"error": f"Internal server error: {str(e)}"}), 500


@public_bp.route('/download-latest-app', methods=['GET'])
@jwt_required()
def download_latest_app():
    """
    Отдаёт последнюю версию установщика Windows из папки public_app_ver.
    Имя файла должно соответствовать маске: Parser_Marser_*.exe
    Версия извлекается из имени и сравнивается семантически.
    """
    start_time = time.time()
    method_name = "download_latest_app"

    try:
        app_versions_dir = Path("uploads/landing/public_app_ver")
        if not app_versions_dir.exists():
            log_event('ERROR', method_name, 'Директория public_app_ver не найдена')
            return jsonify({"error": "Directory not found"}), 500

        pattern = "Parser_Marser_*.exe"
        files = list(app_versions_dir.glob(pattern))

        if not files:
            log_event('WARNING', method_name, 'Файлы установщика не найдены')
            return jsonify({"error": "No installer files found"}), 404

        def extract_version(filename):
            match = re.search(r'Parser_Marser_([\d.]+)\.exe', filename.name)
            if match:
                return match.group(1)
            return None

        def version_key(ver_str):
            if not ver_str:
                return (0, 0, 0)
            parts = ver_str.split('.')
            while len(parts) < 3:
                parts.append('0')
            return tuple(int(p) for p in parts)

        file_versions = []
        for f in files:
            ver = extract_version(f)
            if ver:
                file_versions.append((f, ver, version_key(ver)))

        if not file_versions:
            log_event('ERROR', method_name, 'Не удалось извлечь версию из имён файлов')
            return jsonify({"error": "Invalid file naming"}), 500

        file_versions.sort(key=lambda x: x[2], reverse=True)
        latest_file, latest_version, _ = file_versions[0]

        log_event('INFO', method_name, f'Отдаём последнюю версию: {latest_version}',
                  {'filename': latest_file.name, 'version': latest_version})

        return send_from_directory(
            directory=str(app_versions_dir),
            path=latest_file.name,
            as_attachment=True,
            download_name=f"Parser_Marser_{latest_version}.exe"
        )

    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при скачивании последней версии',
                  {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": "Internal server error"}), 500


@public_bp.route('/uploads/fbs_app_ver/<path:filename>', methods=['GET'])
@jwt_required()
def download_fbs_app(filename):
    """
    Отдаёт файл из папки uploads/fbs_app_ver/.
    Использование: /uploads/fbs_app_ver/имя_файла.exe
    """
    start_time = time.time()
    method_name = "download_fbs_app"

    try:
        log_event('INFO', method_name, f'Запрос на скачивание файла: {filename}')

        base_dir = os.path.join(os.path.dirname(__file__), 'uploads', 'fbs_app_ver')
        safe_path = os.path.normpath(os.path.join(base_dir, filename))

        if not safe_path.startswith(base_dir):
            log_event('WARNING', method_name, 'Попытка path traversal',
                     {'filename': filename, 'resolved_path': safe_path})
            return jsonify({"error": "Invalid file path"}), 400

        if not os.path.isfile(safe_path):
            log_event('WARNING', method_name, 'Файл не найден',
                     {'filename': filename, 'path': safe_path})
            return jsonify({"error": "File not found"}), 404

        if not filename.endswith('.exe'):
            log_event('WARNING', method_name, 'Попытка скачать файл недопустимого типа',
                     {'filename': filename})
            return jsonify({"error": "Only .exe files are allowed"}), 400

        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Файл успешно отправлен',
                 {'filename': filename, 'size': os.path.getsize(safe_path)},
                 duration_ms=duration)

        return send_file(safe_path, as_attachment=True, download_name=filename)

    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при скачивании файла',
                 {'filename': filename, 'error': str(e)},
                 duration_ms=duration)
        return jsonify({"error": "Internal server error"}), 500


@public_bp.route('/health', methods=['GET'])
@jwt_required()
def health():
    return jsonify({"status": "healthy"})