import time
from flask import Blueprint, jsonify, request, current_app
from flask_jwt_extended import jwt_required
from models import ReportDetail

report_details_bp = Blueprint('report_details', __name__, url_prefix='/api/report_details')


@report_details_bp.route('/metadata', methods=['GET'])
@jwt_required()
def get_report_details_metadata():
    try:
        metadata = {
            'table_name': ReportDetail.__tablename__,
            'model_name': ReportDetail.__name__,
            'module': ReportDetail.__module__,
            'columns_count': len(ReportDetail.__table__.columns),
            'primary_keys': [pk.name for pk in ReportDetail.__table__.primary_key],
            'indexes': [],
            'foreign_keys': [],
            'columns': []
        }
        
        for index in ReportDetail.__table__.indexes:
            metadata['indexes'].append({
                'name': index.name,
                'columns': [col.name for col in index.columns],
                'unique': index.unique
            })
        
        for fk in ReportDetail.__table__.foreign_keys:
            metadata['foreign_keys'].append({
                'column': fk.parent.name,
                'references': f'{fk.column.table.name}.{fk.column.name}'
            })
        
        for column in ReportDetail.__table__.columns:
            column_info = {
                'name': column.name,
                'type': str(column.type),
                'nullable': column.nullable,
                'primary_key': column.primary_key,
                'default': str(column.default) if column.default else None,
                'autoincrement': column.autoincrement,
                'unique': column.unique,
                'index': column.index,
                'description_ru': column.info.get('description_ru', '') if hasattr(column, 'info') else ''
            }
            metadata['columns'].append(column_info)
        
        return jsonify({'success': True, 'metadata': metadata})
    except Exception as e:
        current_app.logger.error(f"Ошибка при получении метаданных report_details: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500


@report_details_bp.route('/export/stats', methods=['GET'])
@jwt_required()
def get_report_details_stats():
    try:
        all_records = ReportDetail.query.all()
        if not all_records:
            return jsonify({
                'success': True,
                'message': 'Нет данных для статистики',
                'total_records': 0,
                'total_dates': 0,
                'records_per_date': []
            })
        
        date_stats = {}
        for record in all_records:
            if record.rr_dt:
                date_str = record.rr_dt.strftime('%Y-%m-%d')
                if date_str not in date_stats:
                    date_stats[date_str] = {'date': date_str, 'count': 0, 'examples': []}
                date_stats[date_str]['count'] += 1
                if len(date_stats[date_str]['examples']) < 3:
                    date_stats[date_str]['examples'].append({
                        'id': record.id,
                        'srid': record.srid,
                        'nm_id': record.nm_id,
                        'sa_name': record.sa_name,
                        'quantity': record.quantity,
                        'retail_price': record.retail_price,
                        'doc_type_name': record.doc_type_name
                    })
        
        records_per_date = list(date_stats.values())
        records_per_date.sort(key=lambda x: x['date'], reverse=True)
        
        total_records = len(all_records)
        total_dates = len(date_stats)
        
        doc_type_stats = {}
        for record in all_records:
            if record.doc_type_name:
                doc_type_stats[record.doc_type_name] = doc_type_stats.get(record.doc_type_name, 0) + 1
        
        return jsonify({
            'success': True,
            'total_records': total_records,
            'total_dates': total_dates,
            'average_records_per_date': round(total_records / total_dates, 2) if total_dates else 0,
            'records_per_date': records_per_date,
            'doc_type_distribution': doc_type_stats,
            'date_range': {
                'earliest': min(date_stats.keys()) if date_stats else None,
                'latest': max(date_stats.keys()) if date_stats else None
            },
            'summary': {
                'date_with_most_records': max(records_per_date, key=lambda x: x['count'])['date'] if records_per_date else None,
                'max_records_in_single_date': max(records_per_date, key=lambda x: x['count'])['count'] if records_per_date else 0,
                'min_records_in_single_date': min(records_per_date, key=lambda x: x['count'])['count'] if records_per_date else 0
            }
        })
    except Exception as e:
        return jsonify({'success': False, 'message': str(e), 'error': str(e)}), 500