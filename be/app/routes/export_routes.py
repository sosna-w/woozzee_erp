import time
from datetime import datetime
from io import BytesIO
from flask import Blueprint, jsonify, send_file
from flask_jwt_extended import jwt_required
import pandas as pd

from models import db, Product, Stock, Log, UnifiedProduct
from utils.logger import log_event

export_bp = Blueprint('export', __name__)


@export_bp.route('/export-xlsx', methods=['GET'])
@jwt_required()
def export_xlsx():
    start_time = time.time()
    method_name = "export_xlsx"
    
    try:
        log_event('INFO', method_name, 'Начало выгрузки данных в XLSX')
        
        products_count = Product.query.count()
        stocks_count = Stock.query.count()
        logs_count = Log.query.count()
        unified_count = UnifiedProduct.query.count()
        
        log_event('INFO', method_name, 'Проверка данных для экспорта',
                 {'products_count': products_count, 'stocks_count': stocks_count, 
                  'logs_count': logs_count, 'unified_count': unified_count})
        
        if products_count == 0 and stocks_count == 0 and logs_count == 0 and unified_count == 0:
            log_event('WARNING', method_name, 'Нет данных для экспорта')
            return jsonify({"error": "Нет данных для экспорта"}), 400
        
        output = BytesIO()
        log_event('DEBUG', method_name, 'Создан BytesIO буфер')
        
        try:
            with pd.ExcelWriter(output, engine='xlsxwriter') as writer:
                log_event('DEBUG', method_name, 'Создан Excel writer')
                workbook = writer.book
                
                # ========== ЛИСТ ТОВАРОВ ==========
                try:
                    log_event('INFO', method_name, 'Начало формирования листа товаров')
                    products = Product.query.all()
                    log_event('DEBUG', method_name, f'Получено товаров из БД: {len(products)}')
                    
                    if products:
                        products_data = []
                        for p in products:
                            try:
                                product_dict = {
                                    'nmID': p.nmID,
                                    'imtID': p.imtID,
                                    'vendorCode': p.vendorCode,
                                    'brand': p.brand,
                                    'title': p.title,
                                    'subjectName': p.subjectName,
                                    'needKiz': p.needKiz,
                                    'wholesale_enabled': p.wholesale_enabled,
                                    'wholesale_quantum': p.wholesale_quantum,
                                    'created_at': p.created_at.isoformat() if p.created_at else '',
                                    'updated_at': p.updated_at.isoformat() if p.updated_at else ''
                                }
                                products_data.append(product_dict)
                            except Exception as e:
                                log_event('ERROR', method_name, f'Ошибка при обработке товара {p.nmID}',
                                         {'nm_id': p.nmID, 'error': str(e)})
                                continue
                        
                        df_products = pd.DataFrame(products_data)
                        df_products.to_excel(writer, sheet_name='Товары', index=False)
                        worksheet_products = writer.sheets['Товары']
                        worksheet_products.set_column('A:A', 12)
                        worksheet_products.set_column('B:B', 12)
                        worksheet_products.set_column('C:C', 15)
                        worksheet_products.set_column('D:D', 20)
                        worksheet_products.set_column('E:E', 50)
                        worksheet_products.set_column('F:F', 25)
                        worksheet_products.set_column('G:G', 10)
                        worksheet_products.set_column('H:H', 15)
                        worksheet_products.set_column('I:I', 15)
                        worksheet_products.set_column('J:J', 20)
                        worksheet_products.set_column('K:K', 20)
                        
                        log_event('INFO', method_name, 'Лист товаров успешно сформирован',
                                 {'products_count': len(products_data)})
                    else:
                        log_event('INFO', method_name, 'Нет товаров для экспорта')
                        
                except Exception as e:
                    log_event('ERROR', method_name, 'Ошибка при формировании листа товаров',
                             {'error': str(e), 'traceback': traceback.format_exc()})
                
                # ========== ЛИСТ ОСТАТКОВ ==========
                try:
                    log_event('INFO', method_name, 'Начало формирования листа остатков')
                    stocks = Stock.query.all()
                    log_event('DEBUG', method_name, f'Получено остатков из БД: {len(stocks)}')
                    
                    if stocks:
                        stocks_data = []
                        for s in stocks:
                            try:
                                stock_dict = {
                                    'nmId': s.nmId,
                                    'warehouseName': s.warehouseName,
                                    'supplierArticle': s.supplierArticle,
                                    'barcode': s.barcode,
                                    'quantity': s.quantity,
                                    'quantityFull': s.quantityFull,
                                    'inWayToClient': s.inWayToClient,
                                    'inWayFromClient': s.inWayFromClient,
                                    'subject': s.subject,
                                    'brand': s.brand,
                                    'techSize': s.techSize,
                                    'Price': s.Price,
                                    'Discount': s.Discount,
                                    'lastChangeDate': s.lastChangeDate.isoformat() if s.lastChangeDate else ''
                                }
                                stocks_data.append(stock_dict)
                            except Exception as e:
                                log_event('ERROR', method_name, f'Ошибка при обработке остатка {s.nmId}',
                                         {'nm_id': s.nmId, 'error': str(e)})
                                continue
                        
                        df_stocks = pd.DataFrame(stocks_data)
                        df_stocks.to_excel(writer, sheet_name='Остатки', index=False)
                        worksheet_stocks = writer.sheets['Остатки']
                        worksheet_stocks.set_column('A:A', 12)
                        worksheet_stocks.set_column('B:B', 20)
                        worksheet_stocks.set_column('C:C', 20)
                        worksheet_stocks.set_column('D:D', 20)
                        worksheet_stocks.set_column('E:E', 10)
                        worksheet_stocks.set_column('F:F', 15)
                        worksheet_stocks.set_column('G:G', 15)
                        worksheet_stocks.set_column('H:H', 15)
                        worksheet_stocks.set_column('I:I', 20)
                        worksheet_stocks.set_column('J:J', 20)
                        worksheet_stocks.set_column('K:K', 15)
                        worksheet_stocks.set_column('L:L', 10)
                        worksheet_stocks.set_column('M:M', 10)
                        worksheet_stocks.set_column('N:N', 20)
                        
                        log_event('INFO', method_name, 'Лист остатков успешно сформирован',
                                 {'stocks_count': len(stocks_data)})
                    else:
                        log_event('INFO', method_name, 'Нет остатков для экспорта')
                        
                except Exception as e:
                    log_event('ERROR', method_name, 'Ошибка при формировании листа остатков',
                             {'error': str(e), 'traceback': traceback.format_exc()})
                
                # ========== ЛИСТ ОБЪЕДИНЕННЫХ ДАННЫХ ==========
                try:
                    log_event('INFO', method_name, 'Начало формирования листа объединенных данных')
                    unified_products = UnifiedProduct.query.all()
                    log_event('DEBUG', method_name, f'Получено объединенных товаров из БД: {len(unified_products)}')
                    
                    if unified_products:
                        unified_data = []
                        for u in unified_products:
                            try:
                                unified_dict = {
                                    'nm_id': u.nm_id,
                                    'vendor_code': u.vendor_code,
                                    'barcode': u.barcode,
                                    'title': u.title,
                                    'total_quantity': u.total_quantity,
                                    'fbs_quantity': u.fbs_quantity,
                                    'updated_at': u.updated_at.isoformat() if u.updated_at else ''
                                }
                                unified_data.append(unified_dict)
                            except Exception as e:
                                log_event('ERROR', method_name, f'Ошибка при обработке объединенного товара {u.nm_id}',
                                         {'nm_id': u.nm_id, 'error': str(e)})
                                continue
                        
                        df_unified = pd.DataFrame(unified_data)
                        df_unified.to_excel(writer, sheet_name='Объединенные_данные', index=False)
                        worksheet_unified = writer.sheets['Объединенные_данные']
                        worksheet_unified.set_column('A:A', 12)
                        worksheet_unified.set_column('B:B', 15)
                        worksheet_unified.set_column('C:C', 20)
                        worksheet_unified.set_column('D:D', 50)
                        worksheet_unified.set_column('E:E', 15)
                        worksheet_unified.set_column('F:F', 15)
                        worksheet_unified.set_column('G:G', 20)
                        
                        log_event('INFO', method_name, 'Лист объединенных данных успешно сформирован',
                                 {'unified_count': len(unified_data)})
                    else:
                        log_event('INFO', method_name, 'Нет объединенных данных для экспорта')
                        
                except Exception as e:
                    log_event('ERROR', method_name, 'Ошибка при формировании листа объединенных данных',
                             {'error': str(e), 'traceback': traceback.format_exc()})
                
                # ========== ЛИСТ ЛОГОВ ==========
                try:
                    log_event('INFO', method_name, 'Начало формирования листа логов')
                    logs = Log.query.order_by(Log.timestamp.desc()).limit(1000).all()
                    log_event('DEBUG', method_name, f'Получено логов из БД: {len(logs)}')
                    
                    if logs:
                        logs_data = []
                        for log in logs:
                            try:
                                log_dict = {
                                    'timestamp': log.timestamp.isoformat() if log.timestamp else '',
                                    'level': log.level,
                                    'method': log.method,
                                    'event': log.event,
                                    'nm_id': log.nm_id,
                                    'duration_ms': log.duration_ms,
                                    'response_status': log.response_status,
                                    'records_processed': log.records_processed
                                }
                                logs_data.append(log_dict)
                            except Exception as e:
                                log_event('ERROR', method_name, f'Ошибка при обработке лога {log.id}',
                                         {'log_id': log.id, 'error': str(e)})
                                continue
                        
                        df_logs = pd.DataFrame(logs_data)
                        df_logs.to_excel(writer, sheet_name='Логи', index=False)
                        worksheet_logs = writer.sheets['Логи']
                        worksheet_logs.set_column('A:A', 25)
                        worksheet_logs.set_column('B:B', 10)
                        worksheet_logs.set_column('C:C', 30)
                        worksheet_logs.set_column('D:D', 50)
                        worksheet_logs.set_column('E:E', 12)
                        worksheet_logs.set_column('F:F', 15)
                        worksheet_logs.set_column('G:G', 15)
                        worksheet_logs.set_column('H:H', 20)
                        
                        log_event('INFO', method_name, 'Лист логов успешно сформирован',
                                 {'logs_count': len(logs_data)})
                    else:
                        log_event('INFO', method_name, 'Нет логов для экспорта')
                        
                except Exception as e:
                    log_event('ERROR', method_name, 'Ошибка при формировании листа логов',
                             {'error': str(e), 'traceback': traceback.format_exc()})
                
                # ========== ЛИСТ СТАТИСТИКИ ==========
                try:
                    log_event('INFO', method_name, 'Начало формирования листа статистики')
                    stats_data = {
                        'Метрика': [
                            'Всего товаров',
                            'Всего остатков',
                            'Всего объединенных записей',
                            'Всего логов',
                            'Последнее обновление'
                        ],
                        'Значение': [
                            products_count,
                            stocks_count,
                            unified_count,
                            logs_count,
                            datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
                        ]
                    }
                    df_stats = pd.DataFrame(stats_data)
                    df_stats.to_excel(writer, sheet_name='Статистика', index=False)
                    worksheet_stats = writer.sheets['Статистика']
                    worksheet_stats.set_column('A:A', 25)
                    worksheet_stats.set_column('B:B', 15)
                    log_event('INFO', method_name, 'Лист статистики успешно сформирован')
                    
                except Exception as e:
                    log_event('ERROR', method_name, 'Ошибка при формировании листа статистики',
                             {'error': str(e), 'traceback': traceback.format_exc()})
            
            log_event('DEBUG', method_name, 'Excel файл сформирован в буфере')
            
        except Exception as e:
            log_event('ERROR', method_name, 'Ошибка при создании Excel файла',
                     {'error': str(e), 'traceback': traceback.format_exc()})
            return jsonify({"error": f"Ошибка при создании Excel файла: {str(e)}"}), 500
        
        output.seek(0)
        log_event('DEBUG', method_name, 'Указатель буфера перемещен в начало')
        
        filename = f"wildberries_export_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.xlsx"
        
        duration = (time.time() - start_time) * 1000
        
        log_event('INFO', method_name, 'Успешная выгрузка данных в XLSX',
                 {
                     'products_count': products_count,
                     'stocks_count': stocks_count,
                     'unified_count': unified_count,
                     'logs_count': logs_count,
                     'filename': filename,
                     'file_size_bytes': len(output.getvalue())
                 },
                 duration_ms=duration,
                 records_processed=products_count + stocks_count + unified_count + logs_count)
        
        try:
            log_event('INFO', method_name, 'Начало отправки файла клиенту', {'filename': filename})
            response = send_file(
                output,
                as_attachment=True,
                download_name=filename,
                mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            )
            log_event('INFO', method_name, 'Файл успешно отправлен клиенту', {'filename': filename})
            return response
            
        except Exception as e:
            log_event('ERROR', method_name, 'Ошибка при отправке файла клиенту',
                     {'filename': filename, 'error': str(e), 'traceback': traceback.format_exc()})
            return jsonify({"error": f"Ошибка при отправке файла: {str(e)}"}), 500
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Критическая ошибка при выгрузке данных в XLSX',
                 {'error': str(e), 'traceback': traceback.format_exc()},
                 duration_ms=duration)
        return jsonify({"error": f"Критическая ошибка при выгрузке: {str(e)}"}), 500