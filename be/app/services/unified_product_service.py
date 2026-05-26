import json
import time
import traceback
from datetime import datetime
from sqlalchemy import func
from models import db, Product, Stock, FBSStock, UnifiedProduct, StocksHistory
from utils.logger import log_event
from services.product_service import fetch_all_products, fetch_all_stocks

def update_unified_products():
    start_time = time.time()
    method_name = "update_unified_products"
    
    try:
        log_event('INFO', method_name, 'Начало обновления объединенной базы данных')
        
        products = Product.query.all()
        log_event('DEBUG', method_name, f'Получено товаров: {len(products)}')
        
        # Собираем nm_id из актуальных товаров
        current_nm_ids = {product.nmID for product in products}
        
        # Удаляем из UnifiedProduct товары, которых нет в актуальном списке
        deleted_unified = 0
        try:
            unified_to_delete = UnifiedProduct.query.filter(~UnifiedProduct.nm_id.in_(current_nm_ids)).all()
            if unified_to_delete:
                deleted_unified = len(unified_to_delete)
                for item in unified_to_delete:
                    db.session.delete(item)
                log_event('INFO', method_name, f'Удалено из UnifiedProduct: {deleted_unified}')
        except Exception as e:
            log_event('ERROR', method_name, 'Ошибка при удалении устаревших товаров из UnifiedProduct',
                     {'error': str(e)})
        
        stocks_aggregated = db.session.query(
            Stock.nmId,
            func.sum(Stock.quantity).label('total_quantity')
        ).group_by(Stock.nmId).all()
        
        stocks_dict = {nm_id: total for nm_id, total in stocks_aggregated}
        log_event('DEBUG', method_name, f'Агрегировано остатков для {len(stocks_dict)} товаров')
        
        fbs_stocks = FBSStock.query.all()
        fbs_dict = {stock.nm_id: stock.quantity for stock in fbs_stocks}
        
        processed_count = 0
        updated_count = 0
        created_count = 0
        
        for product in products:
            try:
                total_quantity = stocks_dict.get(product.nmID, 0)
                fbs_quantity = fbs_dict.get(product.nmID, 0)
                
                tags_data = []
                if product.tags:
                    try:
                        original_tags = json.loads(product.tags)
                        for tag in original_tags:
                            if isinstance(tag, dict):
                                tags_data.append({
                                    'name': tag.get('name', ''),
                                    'color': tag.get('color', '')
                                })
                    except json.JSONDecodeError:
                        log_event('WARNING', method_name, f'Ошибка декодирования тегов для товара {product.nmID}')
                
                barcode = product.barcode
                
                chrt_id = None
                if product.sizes and product.sizes != '[]':
                    try:
                        sizes_data = json.loads(product.sizes)
                        if sizes_data and isinstance(sizes_data, list) and len(sizes_data) > 0:
                            first_size = sizes_data[0]
                            chrt_id = first_size.get('chrtID')
                    except json.JSONDecodeError as e:
                        log_event('WARNING', method_name, f'Ошибка декодирования sizes для товара {product.nmID}',
                                 {'error': str(e), 'sizes_raw': product.sizes[:200] if product.sizes else None})
                
                unified_product = UnifiedProduct.query.filter_by(nm_id=product.nmID).first()
                
                if unified_product:
                    unified_product.vendor_code = product.vendorCode
                    unified_product.barcode = barcode
                    unified_product.chrt_id = chrt_id
                    unified_product.title = product.title
                    unified_product.tags = json.dumps(tags_data, ensure_ascii=False)
                    unified_product.total_quantity = total_quantity
                    unified_product.fbs_quantity = fbs_quantity
                    updated_count += 1
                    
                    if chrt_id and unified_product.chrt_id != chrt_id:
                        log_event('INFO', method_name, f'Обновлен chrt_id для товара {product.nmID}',
                                 {'old_chrt_id': unified_product.chrt_id, 'new_chrt_id': chrt_id})
                else:
                    unified_product = UnifiedProduct(
                        nm_id=product.nmID,
                        vendor_code=product.vendorCode,
                        barcode=barcode,
                        chrt_id=chrt_id,
                        title=product.title,
                        tags=json.dumps(tags_data, ensure_ascii=False),
                        total_quantity=total_quantity,
                        fbs_quantity=fbs_quantity
                    )
                    db.session.add(unified_product)
                    created_count += 1
                    
                    if chrt_id:
                        log_event('INFO', method_name, f'Создан товар с chrt_id для {product.nmID}',
                                 {'chrt_id': chrt_id})
                
                processed_count += 1
                
                if processed_count % 100 == 0:
                    db.session.commit()
                    log_event('DEBUG', method_name, f'Промежуточный коммит: обработано {processed_count} товаров')
                    
            except Exception as e:
                log_event('ERROR', method_name, f'Ошибка обработки товара {product.nmID}',
                         {'nm_id': product.nmID, 'error': str(e)})
                continue
        
        db.session.commit()
        
        with_chrt_id = UnifiedProduct.query.filter(UnifiedProduct.chrt_id.isnot(None)).count()
        without_chrt_id = UnifiedProduct.query.filter(UnifiedProduct.chrt_id.is_(None)).count()
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Обновление объединенной базы данных завершено',
                 {
                     'total_processed': processed_count,
                     'created': created_count,
                     'updated': updated_count,
                     'deleted_unified': deleted_unified,
                     'with_chrt_id': with_chrt_id,
                     'without_chrt_id': without_chrt_id,
                     'chrt_id_coverage': f'{(with_chrt_id/processed_count*100):.1f}%' if processed_count > 0 else '0%',
                     'duration_ms': duration
                 },
                 duration_ms=duration,
                 records_processed=processed_count)
        
        print(f"Обновлено объединенной базы: создано {created_count}, обновлено {updated_count}, удалено {deleted_unified}")
        print(f"Статистика chrt_id: заполнено {with_chrt_id} из {processed_count} ({with_chrt_id/processed_count*100:.1f}%)")
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Критическая ошибка при обновлении объединенной базы',
                 {'error': str(e), 'traceback': traceback.format_exc()},
                 duration_ms=duration)
        raise


def create_stocks_snapshot():
    """Создание часового снимка остатков из UnifiedProduct"""
    start_time = time.time()
    method_name = "create_stocks_snapshot"
    
    try:
        log_event('INFO', method_name, 'Начало создания часового снимка остатков')
        now = datetime.now()
        unified_products = UnifiedProduct.query.all()
        
        if not unified_products:
            log_event('WARNING', method_name, 'Нет данных в UnifiedProduct для создания снимка')
            return
        
        created_count = 0
        error_count = 0
        
        for product in unified_products:
            try:
                stocks_history = StocksHistory(
                    nm_id=product.nm_id,
                    total_quantity=product.total_quantity,
                    fbs_quantity=product.fbs_quantity
                )
                db.session.add(stocks_history)
                created_count += 1
                if created_count % 100 == 0:
                    db.session.commit()
            except Exception as e:
                error_count += 1
                log_event('ERROR', method_name, f'Ошибка при создании снимка для товара {product.nm_id}',
                         {'nm_id': product.nm_id, 'error': str(e)})
                continue
        
        db.session.commit()
        duration = (time.time() - start_time) * 1000
        
        log_event('INFO', method_name, 'Создание часового снимка остатков завершено',
                 {
                     'total_processed': len(unified_products),
                     'created': created_count,
                     'errors': error_count,
                     'duration_ms': duration,
                     'snapshot_time': now.isoformat()
                 },
                 duration_ms=duration,
                 records_processed=created_count)
        
        print(f"✅ Создан часовой снимок остатков: {created_count} записей, ошибок: {error_count}")
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Критическая ошибка при создании снимка остатков',
                 {'error': str(e), 'traceback': traceback.format_exc()},
                 duration_ms=duration)
        raise


def schedule_unified_update():
    """Обёртка для вызова update_unified_products в контексте приложения (используется в планировщике)"""
    # Эта функция будет вызываться внутри run_with_app_context, поэтому контекст уже есть
    update_unified_products()


def fetch_all_products_with_unified():
    """Обновить товары, затем объединённую базу"""
    fetch_all_products()
    schedule_unified_update()


def fetch_all_stocks_with_unified():
    """Обновить остатки, затем объединённую базу"""
    fetch_all_stocks()
    schedule_unified_update()