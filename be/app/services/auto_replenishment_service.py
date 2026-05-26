import json
import time
import traceback
from datetime import datetime
from models import db, AutoReplenishmentConfig, WarehouseConfig, Warehouse, TagConfig, ProductAutoConfig, UnifiedProduct
from utils.logger import log_event
from utils.token_manager import get_api_key
from services.product_service import _update_stocks_via_api

def log_auto_replenishment_debug(step, details):
    """Детальное логирование для отладки автообновления"""
    log_event('DEBUG', 'auto_replenishment_debug', step, details)


def auto_replenish_stocks():
    start_time = time.time()
    method_name = "auto_replenish_stocks"
    
    try:
        log_event('INFO', method_name, 'НАЧАЛО автообновления остатков с учетом индивидуальной конфигурации')
        log_auto_replenishment_debug('start', {'timestamp': datetime.utcnow().isoformat()})
        
        # Проверка конфигурации
        config = AutoReplenishmentConfig.query.first()
        if not config or not config.enabled:
            log_event('INFO', method_name, 'Автообновление отключено в настройках')
            return
        
        # Проверка токена
        api_key = get_api_key()
        if not api_key:
            log_event('ERROR', method_name, 'Отсутствует API токен')
            return
        
        # Проверка конфигурации складов
        warehouse_config = WarehouseConfig.query.first()
        if not warehouse_config:
            log_event('ERROR', method_name, 'Конфигурация складов не найдена')
            return
        
        # Загрузка конфигураций тегов
        tag_configs = TagConfig.query.all()
        tag_config_dict = {config.tag_name: config for config in tag_configs}
        
        # Загрузка индивидуальных конфигураций товаров
        product_auto_configs = ProductAutoConfig.query.all()
        product_auto_config_dict = {config.nm_id: config for config in product_auto_configs}
        
        log_auto_replenishment_debug('config_loaded', {
            'tag_configs_count': len(tag_configs),
            'product_auto_configs_count': len(product_auto_configs)
        })
        
        # Загрузка индивидуальных конфигураций складов
        individual_configs = json.loads(warehouse_config.individual_config) if warehouse_config.individual_config else {}
        
        # Поиск активных складов
        warehouses = Warehouse.query.all()
        active_warehouses = []
        
        for warehouse in warehouses:
            warehouse_key = str(warehouse.warehouse_id)
            config_data = individual_configs.get(warehouse_key, {})
            is_active = config_data.get('is_activate', True)
            
            if is_active:
                active_warehouses.append(warehouse)
        
        if not active_warehouses:
            log_event('WARNING', method_name, 'Нет активированных складов')
            return
        
        log_event('INFO', method_name, f'Обработка {len(active_warehouses)} активированных складов')
        
        total_updated = 0
        warehouse_details = []
        
        # Обработка каждого активного склада
        for warehouse in active_warehouses:
            warehouse_start = time.time()
            warehouse_updated = 0
            
            try:
                warehouse_key = str(warehouse.warehouse_id)
                warehouse_config_data = individual_configs.get(warehouse_key, {})
                
                # Определение порога для склада
                if warehouse_config.mode == 'uniform':
                    threshold = warehouse_config.uniform_threshold
                    minimum = warehouse_config.uniform_minimum
                else:
                    threshold = warehouse_config_data.get('threshold', 0)
                    minimum = warehouse_config_data.get('minimum', config.batch_size)

                log_auto_replenishment_debug('warehouse_processing', {
                    'warehouse_id': warehouse.warehouse_id,
                    'threshold': threshold,
                    'minimum': minimum,
                    'batch_size': config.batch_size
                })
                
                # Поиск товаров для обновления
                products_to_update = []
                unified_products = UnifiedProduct.query.all()
                
                for product in unified_products:
                    try:
                        if not product.barcode:
                            continue
                        
                        # ПРИОРИТЕТ 1: Проверка индивидуальной конфигурации товара
                        product_auto_config = product_auto_config_dict.get(product.nm_id)
                        if product_auto_config and product_auto_config.ignore_auto_replenishment:
                            log_auto_replenishment_debug('skip_individual_config', {
                                'nm_id': product.nm_id,
                                'reason': 'ignore_auto_replenishment'
                            })
                            continue
                        
                        # Обработка тегов товара
                        product_tags = []
                        if product.tags:
                            try:
                                tags_data = json.loads(product.tags)
                                for tag in tags_data:
                                    if isinstance(tag, dict) and 'name' in tag:
                                        product_tags.append(tag['name'])
                            except json.JSONDecodeError:
                                continue
                        
                        skip_product = False
                        fixed_amount = None
                        
                        # ПРИОРИТЕТ 2: Проверка конфигурации тегов
                        for tag_name in product_tags:
                            if tag_name in tag_config_dict:
                                tag_config = tag_config_dict[tag_name]
                                behavior = tag_config.behavior
                                
                                if behavior == 'always_zero':
                                    skip_product = True
                                    break
                                elif behavior == 'ignore':
                                    skip_product = True
                                    break
                                elif behavior == 'always_n':
                                    fixed_amount = tag_config.fixed_amount
                                    break
                        
                        if skip_product:
                            continue
                        
                        # ПРИОРИТЕТ 3: Определение количества на основе индивидуальной конфигурации или общих правил
                        amount_to_send = 0
                        reason = ''

                        if product_auto_config:
                            individual_threshold = product_auto_config.fbo_threshold if product_auto_config.fbo_threshold is not None else threshold
                            individual_minimum = product_auto_config.fbs_minimum if product_auto_config.fbs_minimum is not None else minimum
                            
                            if fixed_amount is not None:
                                amount_to_send = fixed_amount
                                reason = 'fixed_amount_tag_with_individual_config'
                            else:
                                if product.total_quantity < individual_threshold:
                                    amount_to_send = individual_minimum
                                    reason = 'below_individual_threshold'
                                else:
                                    amount_to_send = 0
                                    reason = 'above_individual_threshold_clear_fbs'
                            
                            log_auto_replenishment_debug('individual_config_applied', {
                                'nm_id': product.nm_id,
                                'individual_threshold': individual_threshold,
                                'individual_minimum': individual_minimum,
                                'current_stock': product.total_quantity,
                                'amount_to_send': amount_to_send,
                                'reason': reason
                            })
                        else:
                            if fixed_amount is not None:
                                amount_to_send = fixed_amount
                                reason = 'fixed_amount_tag'
                            else:
                                if product.total_quantity < threshold:
                                    amount_to_send = minimum
                                    reason = 'below_threshold'
                                else:
                                    amount_to_send = 0
                                    reason = 'above_threshold_clear_fbs'
                        
                        if amount_to_send > 0 or reason in ['above_threshold_clear_fbs', 'above_individual_threshold_clear_fbs']:
                            products_to_update.append({
                                'barcode': product.barcode,
                                'chrt_id': product.chrt_id,
                                'amount': amount_to_send,
                                'nm_id': product.nm_id,
                                'reason': reason,
                                'current_stock': product.total_quantity,
                                'threshold': product_auto_config.fbo_threshold if product_auto_config and product_auto_config.fbo_threshold is not None else threshold,
                                'has_individual_config': product_auto_config is not None
                            })
                    
                    except Exception as e:
                        log_event('ERROR', method_name, f'Ошибка обработки товара {product.nm_id}',
                                 {'nm_id': product.nm_id, 'error': str(e)})
                        continue
                
                log_auto_replenishment_debug('products_queued', {
                    'warehouse_id': warehouse.warehouse_id,
                    'products_to_update': len(products_to_update)
                })
                
                if not products_to_update:
                    log_event('INFO', method_name, f'Нет товаров для обновления на складе {warehouse.name}')
                    continue
                
                individual_config_used = len([p for p in products_to_update if p['has_individual_config']])
                log_event('INFO', method_name, f'Статистика индивидуальных конфигураций для склада {warehouse.name}',
                         {
                             'total_products': len(products_to_update),
                             'with_individual_config': individual_config_used,
                             'without_individual_config': len(products_to_update) - individual_config_used
                         })
                
                log_event('INFO', method_name, f'Начало обновления {len(products_to_update)} товаров на складе {warehouse.name}')
                
                updated_count = _update_stocks_via_api(
                    api_key, 
                    warehouse.warehouse_id, 
                    products_to_update, 
                    method_name
                )
                
                warehouse_updated = updated_count
                total_updated += updated_count
                
                warehouse_duration = (time.time() - warehouse_start) * 1000
                
                warehouse_details.append({
                    'warehouse_id': warehouse.warehouse_id,
                    'name': warehouse.name,
                    'products_processed': len(products_to_update),
                    'products_updated': updated_count,
                    'individual_configs_used': individual_config_used,
                    'duration_ms': warehouse_duration
                })
                
                log_event('INFO', method_name, f'Обновлено {updated_count} товаров на складе {warehouse.name}')
                
            except Exception as e:
                warehouse_duration = (time.time() - warehouse_start) * 1000
                log_event('ERROR', method_name, f'Ошибка обработки склада {warehouse.warehouse_id}',
                         {'warehouse_id': warehouse.warehouse_id, 'error': str(e)})
                warehouse_details.append({
                    'warehouse_id': warehouse.warehouse_id,
                    'name': warehouse.name,
                    'error': str(e),
                    'duration_ms': warehouse_duration
                })
                continue
        
        # Обновление времени последнего запуска
        config.last_run = datetime.utcnow()
        db.session.commit()
        
        duration = (time.time() - start_time) * 1000
        
        performance_info = {
            'total_warehouses': len(active_warehouses),
            'total_updated': total_updated,
            'duration_ms': duration,
            'warehouse_details': warehouse_details,
            'individual_configs_total': len(product_auto_configs)
        }
        
        log_event('INFO', method_name, 'ЗАВЕРШЕНИЕ автообновления остатков с учетом индивидуальной конфигурации',
                 performance_info,
                 duration_ms=duration,
                 records_processed=total_updated)
        
        print(f"✅ Автообновление завершено: обновлено {total_updated} товаров на {len(active_warehouses)} складах")
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'КРИТИЧЕСКАЯ ОШИБКА автообновления остатков',
                 {'error': str(e), 'traceback': traceback.format_exc()},
                 duration_ms=duration)
        raise