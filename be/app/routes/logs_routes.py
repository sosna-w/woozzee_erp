import time
from datetime import datetime, timedelta
from flask import Blueprint, request, jsonify, send_file
from flask_jwt_extended import jwt_required
from sqlalchemy import func
from io import BytesIO

from models import db, Log
from utils.logger import log_event

logs_bp = Blueprint('logs', __name__)


@logs_bp.route('/logs', methods=['GET'])
@jwt_required()
def get_logs():
    try:
        level = request.args.get('level')
        method = request.args.get('method')
        nm_id = request.args.get('nm_id')
        limit = int(request.args.get('limit', 1000))
        offset = int(request.args.get('offset', 0))

        query = db.session.query(Log)

        if level:
            query = query.filter(Log.level == level)
        if method:
            query = query.filter(Log.method == method)
        if nm_id:
            query = query.filter(Log.nm_id == nm_id)

        query = query.order_by(Log.timestamp.desc())

        total_count = query.count()
        logs = query.offset(offset).limit(limit).all()

        result = {
            'total_count': total_count,
            'logs': [log.to_dict() for log in logs],
            'limit': limit,
            'offset': offset
        }

        return jsonify(result)
    except Exception as e:
        print(f"Ошибка при получении логов: {e}")
        return jsonify({"error": str(e)}), 500


@logs_bp.route('/logs/stats', methods=['GET'])
@jwt_required()
def get_logs_stats():
    try:
        level_stats = db.session.query(
            Log.level,
            func.count(Log.id)
        ).group_by(Log.level).all()

        method_stats = db.session.query(
            Log.method,
            func.count(Log.id)
        ).group_by(Log.method).order_by(func.count(Log.id).desc()).limit(10).all()

        recent_errors = db.session.query(Log).filter(
            Log.level == 'ERROR'
        ).order_by(Log.timestamp.desc()).limit(5).all()

        result = {
            'level_stats': {level: count for level, count in level_stats},
            'top_methods': {method: count for method, count in method_stats},
            'recent_errors': [log.to_dict() for log in recent_errors]
        }

        return jsonify(result)
    except Exception as e:
        print(f"Ошибка при получении статистики логов: {e}")
        return jsonify({"error": str(e)}), 500


@logs_bp.route('/logs/clear', methods=['GET'])
@jwt_required()
def clear_all_logs():
    start_time = time.time()
    method_name = "clear_all_logs"

    try:
        log_event('INFO', method_name, 'Запрос на полную очистку всех логов через браузер')

        count_before = db.session.query(Log).count()

        if count_before == 0:
            duration = (time.time() - start_time) * 1000
            log_event('INFO', method_name, 'Нет логов для удаления', duration_ms=duration)
            return jsonify({
                "status": "no_logs",
                "message": "База логов уже пуста",
                "deleted_count": 0
            })

        delete_start = time.time()
        deleted_count = db.session.query(Log).delete()
        db.session.commit()
        delete_duration = (time.time() - delete_start) * 1000

        total_duration = (time.time() - start_time) * 1000

        log_event('INFO', method_name, 'Все логи успешно удалены через браузер',
                  {
                      'deleted_count': deleted_count,
                      'delete_duration_ms': delete_duration,
                      'total_duration_ms': total_duration
                  },
                  duration_ms=total_duration,
                  records_processed=deleted_count)

        return jsonify({
            "status": "success",
            "message": f"Удалено всех логов: {deleted_count} записей",
            "deleted_count": deleted_count,
            "duration_ms": total_duration
        })

    except Exception as e:
        db.session.rollback()
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при удалении логов через браузер',
                  {'error': str(e), 'traceback': traceback.format_exc()},
                  duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@logs_bp.route('/logs/stream', methods=['GET'])
@jwt_required()
def logs_stream():
    """
    Long Polling эндпоинт для получения логов в реальном времени.
    Клиент передает last_id для получения новых логов с момента последнего запроса.
    Если новых логов нет, сервер ждет до 30 секунд.
    """
    start_time = time.time()
    method_name = "logs_stream"

    try:
        last_id = request.args.get('last_id', 0, type=int)
        timeout = request.args.get('timeout', 30, type=int)
        limit = request.args.get('limit', 1000, type=int)

        timeout = min(timeout, 60)

        # Сначала проверяем, есть ли уже новые логи
        if last_id > 0:
            new_logs = Log.query.filter(Log.id > last_id).order_by(Log.timestamp.asc()).limit(limit).all()
        else:
            new_logs = Log.query.order_by(Log.timestamp.desc()).limit(limit).all()
            new_logs = list(reversed(new_logs))

        if new_logs:
            logs_data = [log.to_dict() for log in new_logs]
            current_last_id = new_logs[-1].id if new_logs else last_id
            duration = (time.time() - start_time) * 1000
            return jsonify({
                'status': 'success',
                'logs': logs_data,
                'last_id': current_last_id,
                'has_more': len(new_logs) >= limit,
                'immediate': True
            })

        poll_start = time.time()
        check_interval = 0.5
        max_attempts = int(timeout / check_interval)

        for attempt in range(max_attempts):
            if request.environ.get('wsgi.disconnected', False):
                return jsonify({'status': 'client_disconnected'}), 499

            new_logs = Log.query.filter(Log.id > last_id).order_by(Log.timestamp.asc()).limit(limit).all()

            if new_logs:
                logs_data = [log.to_dict() for log in new_logs]
                current_last_id = new_logs[-1].id
                poll_duration = (time.time() - poll_start) * 1000
                total_duration = (time.time() - start_time) * 1000
                return jsonify({
                    'status': 'success',
                    'logs': logs_data,
                    'last_id': current_last_id,
                    'has_more': len(new_logs) >= limit,
                    'wait_ms': poll_duration,
                    'attempts': attempt + 1
                })

            time.sleep(check_interval)

        total_duration = (time.time() - start_time) * 1000
        return jsonify({
            'status': 'timeout',
            'logs': [],
            'last_id': last_id,
            'message': f'No new logs for {timeout} seconds',
            'wait_ms': total_duration
        })

    except Exception as e:
        duration = (time.time() - start_time) * 1000
        return jsonify({
            'status': 'error',
            'error': str(e),
            'message': 'Internal server error'
        }), 500


@logs_bp.route('/logs/initial', methods=['GET'])
@jwt_required()
def get_initial_logs():
    """
    Получить начальную порцию логов (последние 1000 записей)
    для инициализации клиента перед подключением к Long Polling
    """
    start_time = time.time()
    method_name = "get_initial_logs"

    try:
        limit = request.args.get('limit', 1000, type=int)

        logs = Log.query.order_by(Log.timestamp.desc()).limit(limit).all()
        logs = list(reversed(logs))

        logs_data = [log.to_dict() for log in logs]
        last_id = logs[-1].id if logs else 0

        duration = (time.time() - start_time) * 1000

        return jsonify({
            'status': 'success',
            'logs': logs_data,
            'last_id': last_id,
            'total_count': len(logs_data)
        })

    except Exception as e:
        duration = (time.time() - start_time) * 1000
        return jsonify({'status': 'error', 'error': str(e)}), 500


@logs_bp.route('/logs/realtime-stats', methods=['GET'])
@jwt_required()
def get_realtime_stats():
    """
    Получить статистику в реальном времени для мониторинга
    """
    start_time = time.time()
    method_name = "get_realtime_stats"

    try:
        total_logs = Log.query.count()
        one_hour_ago = datetime.utcnow() - timedelta(hours=1)
        logs_last_hour = Log.query.filter(Log.timestamp >= one_hour_ago).count()

        five_minutes_ago = datetime.utcnow() - timedelta(minutes=5)
        logs_last_5min = Log.query.filter(Log.timestamp >= five_minutes_ago).count()

        levels_stats = {}
        for level in ['INFO', 'WARNING', 'ERROR', 'DEBUG']:
            count = Log.query.filter_by(level=level).count()
            levels_stats[level] = count

        top_methods = db.session.query(
            Log.method,
            func.count(Log.id).label('count')
        ).group_by(Log.method).order_by(func.count(Log.id).desc()).limit(10).all()

        recent_errors = Log.query.filter_by(level='ERROR').order_by(
            Log.timestamp.desc()
        ).limit(10).all()

        twenty_four_hours_ago = datetime.utcnow() - timedelta(hours=24)
        hourly_activity = db.session.query(
            func.date_trunc('hour', Log.timestamp).label('hour'),
            func.count(Log.id).label('count')
        ).filter(
            Log.timestamp >= twenty_four_hours_ago
        ).group_by(
            func.date_trunc('hour', Log.timestamp)
        ).order_by(
            func.date_trunc('hour', Log.timestamp)
        ).all()

        stats = {
            'overall': {
                'total_logs': total_logs,
                'logs_last_hour': logs_last_hour,
                'logs_last_5min': logs_last_5min,
                'logs_per_minute': logs_last_hour / 60 if logs_last_hour > 0 else 0
            },
            'levels': levels_stats,
            'top_methods': [{'method': method, 'count': count} for method, count in top_methods],
            'recent_errors': [log.to_dict() for log in recent_errors],
            'hourly_activity': [
                {'hour': hour.isoformat(), 'count': count}
                for hour, count in hourly_activity
            ],
            'timestamp': datetime.utcnow().isoformat(),
            'long_polling_endpoint': '/logs/stream',
            'initial_endpoint': '/logs/initial'
        }

        duration = (time.time() - start_time) * 1000

        return jsonify(stats)

    except Exception as e:
        duration = (time.time() - start_time) * 1000
        return jsonify({'status': 'error', 'error': str(e)}), 500


@logs_bp.route('/logs/live')
@jwt_required()
def logs_live_page():
    """
    HTML страница для отображения логов в реальном времени
    """
    return '''
    <!DOCTYPE html>
    <html>
    <head>
        <title>Live Logs</title>
        <meta charset="utf-8">
        <style>
            body {
                font-family: 'Courier New', monospace;
                margin: 0;
                padding: 20px;
                background-color: #0a0a0a;
                color: #f0f0f0;
            }
            .container {
                max-width: 1400px;
                margin: 0 auto;
            }
            .header {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-bottom: 20px;
                padding: 15px;
                background: #1a1a1a;
                border-radius: 8px;
            }
            .stats {
                display: flex;
                gap: 20px;
                font-size: 14px;
            }
            .stat-item {
                padding: 5px 10px;
                background: #2a2a2a;
                border-radius: 4px;
            }
            .controls {
                display: flex;
                gap: 10px;
                margin-bottom: 20px;
            }
            button {
                padding: 8px 16px;
                background: #007acc;
                color: white;
                border: none;
                border-radius: 4px;
                cursor: pointer;
                font-family: inherit;
            }
            button:hover {
                background: #005a99;
            }
            button.clear {
                background: #cc0000;
            }
            button.clear:hover {
                background: #990000;
            }
            select, input {
                padding: 8px;
                background: #2a2a2a;
                color: white;
                border: 1px solid #444;
                border-radius: 4px;
                font-family: inherit;
            }
            .log-entry {
                padding: 12px;
                margin-bottom: 8px;
                border-radius: 6px;
                border-left: 4px solid #444;
                background: #1a1a1a;
                transition: all 0.3s;
            }
            .log-entry:hover {
                background: #2a2a2a;
                transform: translateX(5px);
            }
            .log-timestamp {
                color: #888;
                font-size: 12px;
            }
            .log-level {
                display: inline-block;
                padding: 2px 8px;
                border-radius: 12px;
                font-size: 12px;
                font-weight: bold;
                margin-right: 10px;
                min-width: 60px;
                text-align: center;
            }
            .INFO { border-left-color: #00aa00; background: #002200; }
            .WARNING { border-left-color: #ffaa00; background: #332200; }
            .ERROR { border-left-color: #ff4444; background: #330000; }
            .DEBUG { border-left-color: #8888ff; background: #222244; }
            .log-method {
                color: #88ccff;
                font-weight: bold;
                margin-right: 10px;
            }
            .log-event {
                color: #f0f0f0;
            }
            .log-details {
                margin-top: 8px;
                padding: 8px;
                background: #2a2a2a;
                border-radius: 4px;
                font-size: 12px;
                color: #aaa;
                display: none;
            }
            .log-entry.expanded .log-details {
                display: block;
            }
            .filter-row {
                display: flex;
                gap: 10px;
                margin-bottom: 15px;
                flex-wrap: wrap;
            }
            .filter-group {
                display: flex;
                flex-direction: column;
                gap: 5px;
            }
            .filter-label {
                font-size: 12px;
                color: #888;
            }
            .auto-scroll {
                margin-left: auto;
                display: flex;
                align-items: center;
                gap: 8px;
            }
            #log-container {
                max-height: 70vh;
                overflow-y: auto;
                padding: 10px;
                background: #111;
                border-radius: 8px;
            }
            .connection-status {
                padding: 5px 10px;
                border-radius: 4px;
                font-size: 12px;
                font-weight: bold;
            }
            .connected { background: #002200; color: #00ff00; }
            .disconnected { background: #330000; color: #ff4444; }
            .connecting { background: #333300; color: #ffff00; }
            .search-box {
                flex: 1;
                min-width: 200px;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>📊 Live Logs Monitor</h1>
                <div class="stats">
                    <div class="stat-item">Total: <span id="total-count">0</span></div>
                    <div class="stat-item">Last Hour: <span id="hour-count">0</span></div>
                    <div class="stat-item">Last 5min: <span id="five-min-count">0</span></div>
                    <div class="connection-status" id="connection-status">Connecting...</div>
                </div>
            </div>
            
            <div class="filter-row">
                <div class="filter-group">
                    <div class="filter-label">Level</div>
                    <select id="level-filter">
                        <option value="">All Levels</option>
                        <option value="INFO">INFO</option>
                        <option value="WARNING">WARNING</option>
                        <option value="ERROR">ERROR</option>
                        <option value="DEBUG">DEBUG</option>
                    </select>
                </div>
                
                <div class="filter-group">
                    <div class="filter-label">Method</div>
                    <select id="method-filter">
                        <option value="">All Methods</option>
                    </select>
                </div>
                
                <div class="filter-group search-box">
                    <div class="filter-label">Search</div>
                    <input type="text" id="search-box" placeholder="Search in logs...">
                </div>
                
                <div class="auto-scroll">
                    <input type="checkbox" id="auto-scroll" checked>
                    <label for="auto-scroll">Auto Scroll</label>
                </div>
                
                <button onclick="loadInitialLogs()">🔄 Refresh</button>
                <button onclick="clearLogs()" class="clear">🗑️ Clear</button>
                <button onclick="exportLogs()">📥 Export</button>
                <button onclick="toggleTheme()">🌓 Theme</button>
            </div>
            
            <div id="log-container"></div>
        </div>
        
        <script>
            let lastLogId = 0;
            let logs = [];
            let connectionStatus = 'disconnected';
            let reconnectTimeout = null;
            let isPolling = true;
            
            const logContainer = document.getElementById('log-container');
            const connectionStatusEl = document.getElementById('connection-status');
            const totalCountEl = document.getElementById('total-count');
            const hourCountEl = document.getElementById('hour-count');
            const fiveMinCountEl = document.getElementById('five-min-count');
            const levelFilter = document.getElementById('level-filter');
            const methodFilter = document.getElementById('method-filter');
            const searchBox = document.getElementById('search-box');
            const autoScroll = document.getElementById('auto-scroll');
            
            async function loadInitialLogs() {
                try {
                    const response = await fetch('/logs/initial?limit=1000');
                    const data = await response.json();
                    if (data.status === 'success') {
                        logs = data.logs;
                        lastLogId = data.last_id;
                        updateLogDisplay();
                        updateStats();
                        updateMethodFilter();
                    }
                } catch (error) {
                    console.error('Error loading initial logs:', error);
                }
            }
            
            async function pollNewLogs() {
                if (!isPolling) return;
                try {
                    const response = await fetch(`/logs/stream?last_id=${lastLogId}&timeout=30`);
                    if (response.status === 499) return;
                    const data = await response.json();
                    if (data.status === 'success' && data.logs.length > 0) {
                        logs.push(...data.logs);
                        lastLogId = data.last_id;
                        if (logs.length > 5000) logs = logs.slice(-5000);
                        updateLogDisplay();
                        updateStats();
                        if (autoScroll.checked) logContainer.scrollTop = logContainer.scrollHeight;
                    }
                    if (isPolling) setTimeout(pollNewLogs, 100);
                } catch (error) {
                    console.error('Error in long polling:', error);
                    setConnectionStatus('disconnected');
                    if (isPolling) setTimeout(pollNewLogs, 5000);
                }
            }
            
            function updateLogDisplay() {
                const filteredLogs = filterLogs();
                logContainer.innerHTML = filteredLogs.map(log => `
                    <div class="log-entry ${log.level}" onclick="toggleLogDetails(this)">
                        <div>
                            <span class="log-timestamp">${new Date(log.timestamp).toLocaleString()}</span>
                            <span class="log-level ${log.level}">${log.level}</span>
                            <span class="log-method">${log.method}</span>
                            <span class="log-event">${log.event}</span>
                        </div>
                        <div class="log-details">
                            ${log.details ? `<div><strong>Details:</strong> ${JSON.stringify(log.details)}</div>` : ''}
                            ${log.nm_id ? `<div><strong>NM ID:</strong> ${log.nm_id}</div>` : ''}
                            ${log.duration_ms ? `<div><strong>Duration:</strong> ${log.duration_ms}ms</div>` : ''}
                            ${log.records_processed ? `<div><strong>Records:</strong> ${log.records_processed}</div>` : ''}
                        </div>
                    </div>
                `).join('');
            }
            
            function filterLogs() {
                return logs.filter(log => {
                    if (levelFilter.value && log.level !== levelFilter.value) return false;
                    if (methodFilter.value && log.method !== methodFilter.value) return false;
                    if (searchBox.value) {
                        const searchTerm = searchBox.value.toLowerCase();
                        const logText = JSON.stringify(log).toLowerCase();
                        if (!logText.includes(searchTerm)) return false;
                    }
                    return true;
                });
            }
            
            function updateStats() {
                totalCountEl.textContent = logs.length;
                const oneHourAgo = new Date(Date.now() - 3600000);
                const hourCount = logs.filter(log => new Date(log.timestamp) > oneHourAgo).length;
                hourCountEl.textContent = hourCount;
                const fiveMinAgo = new Date(Date.now() - 300000);
                const fiveMinCount = logs.filter(log => new Date(log.timestamp) > fiveMinAgo).length;
                fiveMinCountEl.textContent = fiveMinCount;
            }
            
            function updateMethodFilter() {
                const methods = [...new Set(logs.map(log => log.method))].sort();
                methodFilter.innerHTML = `<option value="">All Methods</option>${methods.map(m => `<option value="${m}">${m}</option>`).join('')}`;
            }
            
            function setConnectionStatus(status) {
                connectionStatus = status;
                connectionStatusEl.textContent = status.charAt(0).toUpperCase() + status.slice(1);
                connectionStatusEl.className = `connection-status ${status}`;
            }
            
            function toggleLogDetails(element) {
                element.classList.toggle('expanded');
            }
            
            function clearLogs() {
                if (confirm('Clear all logs? This action cannot be undone.')) {
                    fetch('/logs/clear')
                        .then(response => response.json())
                        .then(data => {
                            if (data.status === 'success') {
                                logs = [];
                                lastLogId = 0;
                                updateLogDisplay();
                                updateStats();
                                alert(`Cleared ${data.deleted_count} logs`);
                            }
                        })
                        .catch(error => console.error('Error clearing logs:', error));
                }
            }
            
            function exportLogs() {
                const dataStr = JSON.stringify(logs, null, 2);
                const dataUri = 'data:application/json;charset=utf-8,' + encodeURIComponent(dataStr);
                const linkElement = document.createElement('a');
                linkElement.setAttribute('href', dataUri);
                linkElement.setAttribute('download', `logs_export_${new Date().toISOString().slice(0,19)}.json`);
                linkElement.click();
            }
            
            function toggleTheme() {
                document.body.classList.toggle('light-theme');
            }
            
            levelFilter.addEventListener('change', updateLogDisplay);
            methodFilter.addEventListener('change', updateLogDisplay);
            searchBox.addEventListener('input', updateLogDisplay);
            
            async function init() {
                setConnectionStatus('connecting');
                await loadInitialLogs();
                setConnectionStatus('connected');
                pollNewLogs();
            }
            
            document.addEventListener('DOMContentLoaded', init);
            window.addEventListener('beforeunload', () => { isPolling = false; });
        </script>
    </body>
    </html>
    '''