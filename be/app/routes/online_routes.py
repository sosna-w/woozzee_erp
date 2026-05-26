import time
from datetime import datetime, timedelta
from io import BytesIO
from flask import Blueprint, request, jsonify, send_file
from flask_jwt_extended import jwt_required
from sqlalchemy import func
import pandas as pd

from models import db, OnlineActivity, UserActivity
from utils.logger import log_event

online_bp = Blueprint('online', __name__)


# ========== ONLINE TRACK (HEARTBEAT) ==========

@online_bp.route('/online-track', methods=['POST'])
@jwt_required()
def online_track():
    """Принимает heartbeat от клиента и сохраняет в историю"""
    try:
        data = request.get_json()
        if not data or 'uuid' not in data:
            return jsonify({"error": "uuid required"}), 400

        first_run = None
        if data.get('first_run'):
            try:
                first_run = datetime.fromisoformat(data['first_run'].replace('Z', '+00:00'))
            except:
                pass

        activity = OnlineActivity(
            uuid=data['uuid'],
            computer_name=data.get('computer_name'),
            user_name=data.get('user_name'),
            os_version=data.get('os_version'),
            first_run=first_run
        )
        db.session.add(activity)
        db.session.commit()
        return jsonify({"status": "ok"}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500


@online_bp.route('/online-track/export', methods=['GET'])
@jwt_required()
def online_track_export():
    """Экспорт всей истории активности в XLSX (с фильтрацией по дате и uuid)"""
    try:
        from_date = request.args.get('from_date')
        to_date = request.args.get('to_date')
        uuid_filter = request.args.get('uuid')

        query = OnlineActivity.query
        if from_date:
            try:
                from_dt = datetime.fromisoformat(from_date)
                query = query.filter(OnlineActivity.created_at >= from_dt)
            except:
                pass
        if to_date:
            try:
                to_dt = datetime.fromisoformat(to_date)
                query = query.filter(OnlineActivity.created_at <= to_dt)
            except:
                pass
        if uuid_filter:
            query = query.filter(OnlineActivity.uuid == uuid_filter)

        records = query.order_by(OnlineActivity.created_at.desc()).all()
        if not records:
            return jsonify({"error": "Нет данных для экспорта"}), 404

        data = [r.to_dict() for r in records]
        df = pd.DataFrame(data)

        for col in ['created_at', 'first_run']:
            if col in df.columns:
                df[col] = pd.to_datetime(df[col], errors='coerce').dt.strftime('%Y-%m-%d %H:%M')

        output = BytesIO()
        with pd.ExcelWriter(output, engine='xlsxwriter') as writer:
            df.to_excel(writer, sheet_name='Online Activity', index=False)
        output.seek(0)
        filename = f"online_activity_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.xlsx"
        return send_file(
            output,
            as_attachment=True,
            download_name=filename,
            mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        )
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ========== ONLINE ПОЛЬЗОВАТЕЛЕЙ (UserActivity) ==========

@online_bp.route('/online', methods=['POST'])
@jwt_required()
def track_user_activity():
    """Эндпоинт для передачи информации об онлайне пользователя"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Данные не предоставлены"}), 400

        username = data.get('username')
        if not username:
            return jsonify({"error": "Имя пользователя (username) обязательно"}), 400

        ip_address = request.remote_addr
        user_agent = request.headers.get('User-Agent', '')
        activity_type = data.get('activity_type', 'login')
        details = data.get('details', {})

        user_activity = UserActivity(
            username=username,
            activity_type=activity_type,
            ip_address=ip_address,
            user_agent=user_agent[:500],
            details=json.dumps(details, ensure_ascii=False) if details else None
        )
        db.session.add(user_activity)
        db.session.commit()

        return jsonify({
            "status": "success",
            "message": f"Активность пользователя {username} сохранена",
            "activity": user_activity.to_dict()
        })
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500


@online_bp.route('/online', methods=['GET'])
@jwt_required()
def get_online_users():
    """Эндпоинт для получения данных об онлайне пользователей"""
    try:
        username = request.args.get('username')
        minutes = int(request.args.get('minutes', 15))
        limit = int(request.args.get('limit', 100))

        time_threshold = datetime.utcnow() - timedelta(minutes=minutes)

        query = UserActivity.query.filter(UserActivity.activity_datetime >= time_threshold)
        if username:
            query = query.filter(UserActivity.username == username)

        subquery = query.subquery()
        latest_activities = db.session.query(
            subquery.c.username,
            db.func.max(subquery.c.activity_datetime).label('last_activity'),
            db.func.count(subquery.c.id).label('activity_count')
        ).group_by(subquery.c.username).order_by(db.desc('last_activity')).limit(limit).all()

        online_users = []
        for username, last_activity, activity_count in latest_activities:
            last_activity_record = UserActivity.query.filter(
                UserActivity.username == username,
                UserActivity.activity_datetime == last_activity
            ).first()

            if last_activity_record:
                user_data = last_activity_record.to_dict()
                user_data['activity_count'] = activity_count
                user_data['minutes_since_last_activity'] = int((datetime.utcnow() - last_activity).total_seconds() / 60)
                user_data['is_online'] = user_data['minutes_since_last_activity'] <= minutes
                online_users.append(user_data)

        total_users = len(online_users)
        online_count = len([u for u in online_users if u['is_online']])

        result = {
            'online_users': online_users,
            'statistics': {
                'total_users': total_users,
                'online_count': online_count,
                'offline_count': total_users - online_count,
                'time_threshold_minutes': minutes,
                'threshold_time': time_threshold.isoformat(),
                'current_time': datetime.utcnow().isoformat()
            },
            'parameters': {
                'username_filter': username,
                'minutes': minutes,
                'limit': limit
            }
        }
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@online_bp.route('/online/stats', methods=['GET'])
@jwt_required()
def get_online_stats():
    """Получить статистику по активности пользователей"""
    try:
        days = int(request.args.get('days', 7))
        start_date = datetime.utcnow() - timedelta(days=days)

        total_activities = UserActivity.query.filter(UserActivity.activity_datetime >= start_date).count()
        unique_users = db.session.query(
            db.func.count(db.func.distinct(UserActivity.username))
        ).filter(UserActivity.activity_datetime >= start_date).scalar()

        activity_types = db.session.query(
            UserActivity.activity_type,
            db.func.count(UserActivity.id).label('count')
        ).filter(UserActivity.activity_datetime >= start_date).group_by(UserActivity.activity_type).all()

        daily_stats = db.session.query(
            db.func.date(UserActivity.activity_datetime).label('date'),
            db.func.count(UserActivity.id).label('activity_count'),
            db.func.count(db.func.distinct(UserActivity.username)).label('unique_users')
        ).filter(UserActivity.activity_datetime >= start_date).group_by('date').order_by('date').all()

        top_users = db.session.query(
            UserActivity.username,
            db.func.count(UserActivity.id).label('activity_count'),
            db.func.max(UserActivity.activity_datetime).label('last_activity')
        ).filter(UserActivity.activity_datetime >= start_date).group_by(UserActivity.username).order_by(
            db.desc('activity_count')
        ).limit(10).all()

        result = {
            'period': {
                'days': days,
                'start_date': start_date.isoformat(),
                'end_date': datetime.utcnow().isoformat()
            },
            'statistics': {
                'total_activities': total_activities,
                'unique_users': unique_users,
                'average_activities_per_user': total_activities / unique_users if unique_users > 0 else 0
            },
            'activity_types': [{'type': atype, 'count': count} for atype, count in activity_types],
            'daily_statistics': [
                {
                    'date': date.isoformat() if hasattr(date, 'isoformat') else str(date),
                    'activity_count': activity_count,
                    'unique_users': unique_users_count
                } for date, activity_count, unique_users_count in daily_stats
            ],
            'top_users': [
                {
                    'username': username,
                    'activity_count': activity_count,
                    'last_activity': last_activity.isoformat() if last_activity else None
                } for username, activity_count, last_activity in top_users
            ]
        }
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@online_bp.route('/online/users/all', methods=['GET'])
@jwt_required()
def get_all_users():
    users = db.session.query(UserActivity.username).distinct().all()
    return jsonify([u[0] for u in users])


@online_bp.route('/online/<string:username>', methods=['GET'])
@jwt_required()
def get_user_activity(username):
    """Получить историю активности конкретного пользователя"""
    try:
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 50, type=int)
        days = int(request.args.get('days', 30))

        start_date = datetime.utcnow() - timedelta(days=days)

        query = UserActivity.query.filter(
            UserActivity.username == username,
            UserActivity.activity_datetime >= start_date
        ).order_by(UserActivity.activity_datetime.desc())

        pagination = query.paginate(page=page, per_page=per_page, error_out=False)
        activities = pagination.items

        if not activities:
            return jsonify({
                'username': username,
                'message': 'Активность не найдена за указанный период',
                'activities': []
            }), 404

        activity_stats = {
            'total_activities': query.count(),
            'first_activity': activities[-1].activity_datetime.isoformat() if activities else None,
            'last_activity': activities[0].activity_datetime.isoformat() if activities else None,
            'activity_types': {}
        }

        type_counts = db.session.query(
            UserActivity.activity_type,
            db.func.count(UserActivity.id).label('count')
        ).filter(
            UserActivity.username == username,
            UserActivity.activity_datetime >= start_date
        ).group_by(UserActivity.activity_type).all()
        activity_stats['activity_types'] = {atype: count for atype, count in type_counts}

        result = {
            'username': username,
            'activities': [activity.to_dict() for activity in activities],
            'statistics': activity_stats,
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            },
            'period': {
                'days': days,
                'start_date': start_date.isoformat()
            }
        }
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@online_bp.route('/online/check/<string:username>', methods=['GET'])
@jwt_required()
def check_user_online(username):
    """Проверить, онлайн ли пользователь"""
    try:
        minutes_threshold = int(request.args.get('minutes', 1))
        time_threshold = datetime.utcnow() - timedelta(minutes=minutes_threshold)

        last_activity = UserActivity.query.filter(
            UserActivity.username == username,
            UserActivity.activity_datetime >= time_threshold
        ).order_by(UserActivity.activity_datetime.desc()).first()

        is_online = last_activity is not None

        result = {
            'username': username,
            'is_online': is_online,
            'last_activity': last_activity.to_dict() if last_activity else None,
            'minutes_threshold': minutes_threshold,
            'checked_at': datetime.utcnow().isoformat()
        }
        if last_activity:
            minutes_since = (datetime.utcnow() - last_activity.activity_datetime).total_seconds() / 60
            result['minutes_since_last_activity'] = round(minutes_since, 2)

        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@online_bp.route('/online/detailed/<string:username>', methods=['GET'])
@jwt_required()
def get_user_detailed_stats(username):
    """Получить детальную статистику активности пользователя за последние 24 часа"""
    try:
        hours = int(request.args.get('hours', 24))
        interval_minutes = int(request.args.get('interval', 10))

        time_threshold = datetime.utcnow() - timedelta(hours=hours)
        activities = UserActivity.query.filter(
            UserActivity.username == username,
            UserActivity.activity_datetime >= time_threshold
        ).order_by(UserActivity.activity_datetime).all()

        if not activities:
            return jsonify({
                'username': username,
                'message': 'Активность не найдена за указанный период',
                'intervals': [],
                'raw_activities': []
            })

        intervals = []
        start_time = time_threshold
        end_time = datetime.utcnow()
        current_interval_start = start_time

        while current_interval_start < end_time:
            current_interval_end = current_interval_start + timedelta(minutes=interval_minutes)
            interval_activities = [
                a for a in activities
                if current_interval_start <= a.activity_datetime < current_interval_end
            ]
            intervals.append({
                'interval_start': current_interval_start.isoformat(),
                'interval_end': current_interval_end.isoformat(),
                'activity_count': len(interval_activities),
                'is_online': len(interval_activities) > 0,
                'activities': [{
                    'id': act.id,
                    'type': act.activity_type,
                    'time': act.activity_datetime.isoformat(),
                    'details': act.details
                } for act in interval_activities]
            })
            current_interval_start = current_interval_end

        online_intervals = [i for i in intervals if i['is_online']]

        result = {
            'username': username,
            'period': {
                'hours': hours,
                'start_time': start_time.isoformat(),
                'end_time': end_time.isoformat(),
                'interval_minutes': interval_minutes
            },
            'statistics': {
                'total_intervals': len(intervals),
                'online_intervals': len(online_intervals),
                'online_percentage': round((len(online_intervals) / len(intervals)) * 100, 2) if intervals else 0,
                'total_activities': len(activities),
                'first_activity': activities[0].activity_datetime.isoformat(),
                'last_activity': activities[-1].activity_datetime.isoformat()
            },
            'intervals': intervals,
            'raw_summary': {
                'total_activities': len(activities),
                'activities_by_type': {},
                'hourly_distribution': {}
            }
        }

        for activity in activities:
            atype = activity.activity_type
            result['raw_summary']['activities_by_type'][atype] = result['raw_summary']['activities_by_type'].get(atype, 0) + 1
            hour = activity.activity_datetime.strftime('%H:00')
            result['raw_summary']['hourly_distribution'][hour] = result['raw_summary']['hourly_distribution'].get(hour, 0) + 1

        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500