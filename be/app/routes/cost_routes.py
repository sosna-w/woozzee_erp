import time
from datetime import datetime
from io import BytesIO
from flask import Blueprint, request, jsonify, send_file
from flask_jwt_extended import jwt_required
from sqlalchemy import func
import pandas as pd

from models import db, ProductCost
from utils.logger import log_event

cost_bp = Blueprint('cost', __name__)


@cost_bp.route('/cost-template', methods=['GET'])
@jwt_required()
def download_cost_template():
    """Скачать шаблон XLSX файла для загрузки себестоимости"""
    start_time = time.time()
    method_name = "download_cost_template"
    
    try:
        log_event('INFO', method_name, 'Запрос шаблона для загрузки себестоимости')
        
        template_data = {
            'Артикул WB': [],
            'Мой артикул': [],
            'Себестоимость': [],
            'Дополнительные расходы': []
        }
        
        for i in range(3):
            template_data['Артикул WB'].append(f'WB{i+1}')
            template_data['Мой артикул'].append(f'VENDOR{i+1}')
            template_data['Себестоимость'].append(100.0 * (i+1))
            template_data['Дополнительные расходы'].append(10.0 * (i+1))
        
        df_template = pd.DataFrame(template_data)
        output = BytesIO()
        with pd.ExcelWriter(output, engine='xlsxwriter') as writer:
            df_template.to_excel(writer, sheet_name='Шаблон', index=False)
            worksheet = writer.sheets['Шаблон']
            worksheet.set_column('A:A', 15)
            worksheet.set_column('B:B', 15)
            worksheet.set_column('C:C', 15)
            worksheet.set_column('D:D', 20)
        
        output.seek(0)
        filename = f"шаблон_себестоимость_{datetime.utcnow().strftime('%Y%m%d')}.xlsx"
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Шаблон успешно сформирован', duration_ms=duration)
        
        return send_file(
            output,
            as_attachment=True,
            download_name=filename,
            mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        )
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при формировании шаблона',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@cost_bp.route('/upload-cost-xlsx', methods=['POST'])
@jwt_required()
def upload_cost_xlsx():
    """Загрузить себестоимость из XLSX файла"""
    start_time = time.time()
    method_name = "upload_cost_xlsx"
    
    try:
        log_event('INFO', method_name, 'Загрузка себестоимости из XLSX файла')
        
        if 'file' not in request.files:
            log_event('WARNING', method_name, 'Файл не найден в запросе')
            return jsonify({"error": "Файл не найден"}), 400
        
        file = request.files['file']
        
        if file.filename == '':
            log_event('WARNING', method_name, 'Имя файла пустое')
            return jsonify({"error": "Имя файла пустое"}), 400
        
        if not file.filename.endswith(('.xlsx', '.xls')):
            log_event('WARNING', method_name, 'Неверный формат файла', {'filename': file.filename})
            return jsonify({"error": "Только XLSX/XLS файлы поддерживаются"}), 400
        
        try:
            df = pd.read_excel(file)
            log_event('INFO', method_name, f'Файл прочитан, строк: {len(df)}')
            
            required_columns = ['Артикул WB', 'Мой артикул', 'Себестоимость', 'Дополнительные расходы']
            missing_columns = [col for col in required_columns if col not in df.columns]
            
            if missing_columns:
                log_event('ERROR', method_name, f'Отсутствуют колонки: {missing_columns}')
                return jsonify({
                    "error": f"Отсутствуют колонки: {', '.join(missing_columns)}",
                    "available_columns": list(df.columns)
                }), 400
            
            processed_count = 0
            updated_count = 0
            created_count = 0
            errors = []
            
            for index, row in df.iterrows():
                try:
                    wb_article = str(row['Артикул WB']).strip() if pd.notna(row['Артикул WB']) else None
                    my_article = str(row['Мой артикул']).strip() if pd.notna(row['Мой артикул']) else None
                    cost_price = float(row['Себестоимость']) if pd.notna(row['Себестоимость']) else None
                    additional_expenses = float(row['Дополнительные расходы']) if pd.notna(row['Дополнительные расходы']) else None
                    
                    if not wb_article and not my_article:
                        errors.append(f"Строка {index+2}: отсутствуют оба артикула")
                        continue
                    
                    existing_cost = None
                    if wb_article:
                        existing_cost = ProductCost.query.filter_by(wb_article=wb_article).first()
                    
                    if not existing_cost and my_article:
                        existing_cost = ProductCost.query.filter_by(my_article=my_article).first()
                    
                    if existing_cost:
                        if wb_article:
                            existing_cost.wb_article = wb_article
                        if my_article:
                            existing_cost.my_article = my_article
                        existing_cost.cost_price = cost_price
                        existing_cost.additional_expenses = additional_expenses
                        existing_cost.updated_at = datetime.utcnow()
                        updated_count += 1
                    else:
                        new_cost = ProductCost(
                            wb_article=wb_article,
                            my_article=my_article,
                            cost_price=cost_price,
                            additional_expenses=additional_expenses
                        )
                        db.session.add(new_cost)
                        created_count += 1
                    
                    processed_count += 1
                    
                    if processed_count % 100 == 0:
                        db.session.commit()
                        
                except Exception as e:
                    errors.append(f"Строка {index+2}: {str(e)}")
                    log_event('ERROR', method_name, f'Ошибка обработки строки {index+2}',
                             {'error': str(e), 'row_data': row.to_dict()})
                    continue
            
            db.session.commit()
            duration = (time.time() - start_time) * 1000
            
            result = {
                "status": "success",
                "message": f"Обработано {processed_count} записей",
                "statistics": {
                    "total_processed": processed_count,
                    "created": created_count,
                    "updated": updated_count,
                    "errors": len(errors)
                },
                "duration_ms": duration
            }
            
            if errors:
                result["errors"] = errors[:50]
            
            log_event('INFO', method_name, 'Успешная загрузка себестоимости из XLSX',
                     result["statistics"], duration_ms=duration, records_processed=processed_count)
            
            return jsonify(result)
            
        except Exception as e:
            db.session.rollback()
            log_event('ERROR', method_name, 'Ошибка при чтении XLSX файла',
                     {'error': str(e), 'traceback': traceback.format_exc()})
            return jsonify({"error": f"Ошибка при чтении файла: {str(e)}"}), 500
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Критическая ошибка при загрузке XLSX',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@cost_bp.route('/cost', methods=['GET'])
@jwt_required()
def get_costs():
    """Получить список себестоимостей с фильтрацией (поддержка одиночного артикула и списка)"""
    start_time = time.time()
    method_name = "get_costs"
    
    try:
        log_event('INFO', method_name, 'Запрос списка себестоимостей')
        
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 100, type=int)
        wb_article = request.args.get('wb_article')
        my_article = request.args.get('my_article')
        my_articles = request.args.get('my_articles')
        search = request.args.get('search', '')
        
        query = ProductCost.query
        
        if my_articles:
            articles_list = [article.strip() for article in my_articles.split(',') if article.strip()]
            if articles_list:
                conditions = []
                for article in articles_list:
                    conditions.append(ProductCost.my_article.ilike(f'%{article}%'))
                query = query.filter(db.or_(*conditions))
                log_event('INFO', method_name, f'Фильтрация по списку артикулов: {len(articles_list)} артикулов')
        elif wb_article:
            query = query.filter(ProductCost.wb_article.ilike(f'%{wb_article}%'))
        elif my_article:
            query = query.filter(ProductCost.my_article.ilike(f'%{my_article}%'))
        
        if search:
            query = query.filter(
                db.or_(
                    ProductCost.wb_article.ilike(f'%{search}%'),
                    ProductCost.my_article.ilike(f'%{search}%')
                )
            )
        
        query = query.order_by(ProductCost.updated_at.desc())
        
        pagination = query.paginate(page=page, per_page=per_page, error_out=False)
        costs = pagination.items
        
        result = {
            'costs': [cost.to_dict() for cost in costs],
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            },
            'filters': {
                'wb_article': wb_article,
                'my_article': my_article,
                'my_articles': my_articles,
                'search': search
            }
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат списка себестоимостей',
                 {
                     'page': page,
                     'per_page': per_page,
                     'total_items': pagination.total,
                     'returned_items': len(costs)
                 },
                 duration_ms=duration, records_processed=len(costs))
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении списка себестоимостей',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@cost_bp.route('/cost', methods=['POST'])
@jwt_required()
def add_or_update_cost():
    """Добавить или обновить себестоимость по артикулу"""
    start_time = time.time()
    method_name = "add_or_update_cost"
    
    try:
        log_event('INFO', method_name, 'Добавление/обновление себестоимости')
        data = request.get_json()
        
        if not data:
            log_event('WARNING', method_name, 'Нет данных в запросе')
            return jsonify({"error": "Данные не предоставлены"}), 400
        
        wb_article = data.get('wb_article')
        my_article = data.get('my_article')
        
        if not wb_article and not my_article:
            log_event('WARNING', method_name, 'Не указаны артикулы')
            return jsonify({"error": "Укажите хотя бы один артикул (wb_article или my_article)"}), 400
        
        existing_cost = None
        if wb_article:
            existing_cost = ProductCost.query.filter_by(wb_article=wb_article).first()
        
        if not existing_cost and my_article:
            existing_cost = ProductCost.query.filter_by(my_article=my_article).first()
        
        if existing_cost:
            if wb_article:
                existing_cost.wb_article = wb_article
            if my_article:
                existing_cost.my_article = my_article
            if 'cost_price' in data:
                existing_cost.cost_price = data.get('cost_price')
            if 'additional_expenses' in data:
                existing_cost.additional_expenses = data.get('additional_expenses')
            existing_cost.updated_at = datetime.utcnow()
            action = 'updated'
            log_event('INFO', method_name, f'Обновление существующей записи',
                     {'id': existing_cost.id, 'wb_article': wb_article, 'my_article': my_article})
        else:
            existing_cost = ProductCost(
                wb_article=wb_article,
                my_article=my_article,
                cost_price=data.get('cost_price'),
                additional_expenses=data.get('additional_expenses')
            )
            db.session.add(existing_cost)
            action = 'created'
            log_event('INFO', method_name, f'Создание новой записи',
                     {'wb_article': wb_article, 'my_article': my_article})
        
        db.session.commit()
        duration = (time.time() - start_time) * 1000
        
        result = {
            "status": "success",
            "action": action,
            "cost": existing_cost.to_dict(),
            "message": f"Запись {action} успешно"
        }
        
        log_event('INFO', method_name, f'Себестоимость {action} успешно',
                 {'id': existing_cost.id, 'action': action}, duration_ms=duration)
        
        return jsonify(result)
        
    except Exception as e:
        db.session.rollback()
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при добавлении/обновлении себестоимости',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@cost_bp.route('/cost/<int:cost_id>', methods=['PUT'])
@jwt_required()
def update_cost_by_id(cost_id):
    """Обновить себестоимость по ID"""
    start_time = time.time()
    method_name = "update_cost_by_id"
    
    try:
        log_event('INFO', method_name, f'Обновление себестоимости по ID {cost_id}')
        data = request.get_json()
        
        cost = ProductCost.query.get(cost_id)
        if not cost:
            log_event('WARNING', method_name, f'Запись с ID {cost_id} не найдена')
            return jsonify({"error": "Запись не найдена"}), 404
        
        if 'wb_article' in data:
            cost.wb_article = data['wb_article']
        if 'my_article' in data:
            cost.my_article = data['my_article']
        if 'cost_price' in data:
            cost.cost_price = data['cost_price']
        if 'additional_expenses' in data:
            cost.additional_expenses = data['additional_expenses']
        
        cost.updated_at = datetime.utcnow()
        db.session.commit()
        
        duration = (time.time() - start_time) * 1000
        
        result = {
            "status": "success",
            "cost": cost.to_dict(),
            "message": "Запись обновлена успешно"
        }
        
        log_event('INFO', method_name, f'Себестоимость с ID {cost_id} обновлена', duration_ms=duration)
        
        return jsonify(result)
        
    except Exception as e:
        db.session.rollback()
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка при обновлении себестоимости ID {cost_id}',
                 {'cost_id': cost_id, 'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@cost_bp.route('/cost/<int:cost_id>', methods=['DELETE'])
@jwt_required()
def delete_cost_by_id(cost_id):
    """Удалить себестоимость по ID"""
    start_time = time.time()
    method_name = "delete_cost_by_id"
    
    try:
        log_event('INFO', method_name, f'Удаление себестоимости по ID {cost_id}')
        
        cost = ProductCost.query.get(cost_id)
        if not cost:
            log_event('WARNING', method_name, f'Запись с ID {cost_id} не найдена')
            return jsonify({"error": "Запись не найдена"}), 404
        
        db.session.delete(cost)
        db.session.commit()
        
        duration = (time.time() - start_time) * 1000
        
        result = {
            "status": "success",
            "message": f"Запись с ID {cost_id} удалена успешно",
            "deleted_cost": cost.to_dict()
        }
        
        log_event('INFO', method_name, f'Себестоимость с ID {cost_id} удалена', duration_ms=duration)
        
        return jsonify(result)
        
    except Exception as e:
        db.session.rollback()
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, f'Ошибка при удалении себестоимости ID {cost_id}',
                 {'cost_id': cost_id, 'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@cost_bp.route('/cost/by-article', methods=['DELETE'])
@jwt_required()
def delete_cost_by_article():
    """Удалить себестоимость по артикулу"""
    start_time = time.time()
    method_name = "delete_cost_by_article"
    
    try:
        log_event('INFO', method_name, 'Удаление себестоимости по артикулу')
        data = request.get_json()
        
        if not data:
            log_event('WARNING', method_name, 'Нет данных в запросе')
            return jsonify({"error": "Данные не предоставлены"}), 400
        
        wb_article = data.get('wb_article')
        my_article = data.get('my_article')
        
        if not wb_article and not my_article:
            log_event('WARNING', method_name, 'Не указаны артикулы')
            return jsonify({"error": "Укажите хотя бы один артикул (wb_article или my_article)"}), 400
        
        cost = None
        if wb_article:
            cost = ProductCost.query.filter_by(wb_article=wb_article).first()
        
        if not cost and my_article:
            cost = ProductCost.query.filter_by(my_article=my_article).first()
        
        if not cost:
            log_event('WARNING', method_name, 'Запись не найдена', 
                     {'wb_article': wb_article, 'my_article': my_article})
            return jsonify({"error": "Запись не найдена"}), 404
        
        db.session.delete(cost)
        db.session.commit()
        
        duration = (time.time() - start_time) * 1000
        
        result = {
            "status": "success",
            "message": f"Запись удалена успешно",
            "deleted_cost": cost.to_dict()
        }
        
        log_event('INFO', method_name, 'Себестоимость удалена по артикулу',
                 {'wb_article': wb_article, 'my_article': my_article}, duration_ms=duration)
        
        return jsonify(result)
        
    except Exception as e:
        db.session.rollback()
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при удалении себестоимости по артикулу',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@cost_bp.route('/cost/export', methods=['GET'])
@jwt_required()
def export_costs():
    """Экспортировать все себестоимости в XLSX"""
    start_time = time.time()
    method_name = "export_costs"
    
    try:
        log_event('INFO', method_name, 'Экспорт себестоимостей в XLSX')
        
        costs = ProductCost.query.all()
        
        if not costs:
            log_event('WARNING', method_name, 'Нет данных для экспорта')
            return jsonify({"error": "Нет данных для экспорта"}), 404
        
        costs_data = []
        for cost in costs:
            costs_data.append({
                'Артикул WB': cost.wb_article,
                'Мой артикул': cost.my_article,
                'Себестоимость': cost.cost_price,
                'Дополнительные расходы': cost.additional_expenses,
                'Общая стоимость': (cost.cost_price or 0) + (cost.additional_expenses or 0) if cost.cost_price else None,
                'Дата создания': cost.created_at.isoformat() if cost.created_at else '',
                'Дата обновления': cost.updated_at.isoformat() if cost.updated_at else ''
            })
        
        df_costs = pd.DataFrame(costs_data)
        output = BytesIO()
        with pd.ExcelWriter(output, engine='xlsxwriter') as writer:
            df_costs.to_excel(writer, sheet_name='Себестоимость', index=False)
            workbook = writer.book
            worksheet = writer.sheets['Себестоимость']
            number_format = workbook.add_format({'num_format': '#,##0.00'})
            date_format = workbook.add_format({'num_format': 'yyyy-mm-dd hh:mm:ss'})
            worksheet.set_column('A:B', 20)
            worksheet.set_column('C:D', 15, number_format)
            worksheet.set_column('E:E', 15, number_format)
            worksheet.set_column('F:G', 20, date_format)
        
        output.seek(0)
        filename = f"себестоимость_экспорт_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.xlsx"
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный экспорт себестоимостей',
                 {'count': len(costs)}, duration_ms=duration, records_processed=len(costs))
        
        return send_file(
            output,
            as_attachment=True,
            download_name=filename,
            mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        )
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при экспорте себестоимостей',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


@cost_bp.route('/cost/stats', methods=['GET'])
@jwt_required()
def get_cost_stats():
    """Получить статистику по себестоимостям"""
    start_time = time.time()
    method_name = "get_cost_stats"
    
    try:
        log_event('INFO', method_name, 'Запрос статистики по себестоимостям')
        
        total_costs = ProductCost.query.count()
        with_wb_article = ProductCost.query.filter(ProductCost.wb_article.isnot(None)).count()
        with_my_article = ProductCost.query.filter(ProductCost.my_article.isnot(None)).count()
        with_cost_price = ProductCost.query.filter(ProductCost.cost_price.isnot(None)).count()
        with_additional_expenses = ProductCost.query.filter(ProductCost.additional_expenses.isnot(None)).count()
        
        avg_cost_price = db.session.query(func.avg(ProductCost.cost_price)).scalar()
        avg_additional_expenses = db.session.query(func.avg(ProductCost.additional_expenses)).scalar()
        
        last_updated = ProductCost.query.order_by(ProductCost.updated_at.desc()).first()
        
        result = {
            'total_records': total_costs,
            'with_wb_article': with_wb_article,
            'with_my_article': with_my_article,
            'with_cost_price': with_cost_price,
            'with_additional_expenses': with_additional_expenses,
            'average_cost_price': round(avg_cost_price, 2) if avg_cost_price else 0,
            'average_additional_expenses': round(avg_additional_expenses, 2) if avg_additional_expenses else 0,
            'last_updated': last_updated.updated_at.isoformat() if last_updated and last_updated.updated_at else None,
            'system_time': datetime.utcnow().isoformat()
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат статистики', duration_ms=duration)
        
        return jsonify(result)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении статистики',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500