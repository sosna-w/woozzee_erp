# report_fetcher.py
import requests
import pandas as pd
from datetime import datetime, timedelta, date  # Добавлен date
import time
import numpy as np
from sqlalchemy import text, and_
from models.database_models import db
from models.database_models import ReportDetail
import traceback
import sys
import json
from models.log_model import Log
import pyarrow as pa
import pyarrow.parquet as pq
from pathlib import Path 

def log_event(level, method, event, details=None, duration_ms=None, nm_id=None, 
              request_url=None, response_status=None, records_processed=None):
    try:
        log = Log(
            level=level,
            method=method,
            event=event,
            details=json.dumps(details, ensure_ascii=False) if details else None,
            duration_ms=duration_ms,
            nm_id=nm_id,
            request_url=request_url,
            response_status=response_status,
            records_processed=records_processed
        )
        db.session.add(log)
        db.session.commit()
    except Exception as e:
        print(f"Ошибка при логировании в PostgreSQL: {e}", file=sys.stderr)
        # Запасной вариант - запись в файл
        try:
            with open('log_errors.txt', 'a') as f:
                f.write(f"{datetime.utcnow().isoformat()} - {level} - {method} - {event} - {str(e)[:200]}\n")
        except:
            pass

class WBReportFetcher:
    def __init__(self):
        """
        Инициализация класса для работы с API отчетов Wildberries
        Токен берется из базы данных
        """
        self.base_url = "https://statistics-api.wildberries.ru/api/v5/supplier/reportDetailByPeriod"
        self.costs_base_url = "http://sosna.tech/cost"
        
        # Желаемый порядок столбцов (добавлены новые столбцы)
        self.desired_column_order = [
            'srid', 'operation_quantity', 'shk_id', 'sticker_id', 'rrd_id', 'assembly_id', 'nm_id', 'sa_name', 
            'barcode', 'gi_id', 'ppvz_office_id', 'order_uid', 'trbx_id', 'seller_promo_id', 
            'loyalty_id', 'uuid_promocode', 'subject_name', 'brand_name', 'ts_name', 
            'doc_type_name', 'supplier_oper_name', 'bonus_type_name', 'payment_processing',
            'rr_dt', 'order_dt', 'sale_dt', 'delivery_time_hours', 'type_fb',
            'delivery_method', 'gi_box_type_name', 'site_country', 'office_name',
            'ppvz_office_name', 'dlv_prc', 'acquiring_percent', 'commission_percent',
            'base_comission', 'penalty_commission_percent', 'is_kgvp_v2', 'loyalty_discount',
            'ppvz_kvw_prc', 'ppvz_kvw_prc_base', 'ppvz_spp_prc', 'product_discount_for_report',
            'sale_percent', 'sale_price_promocode_discount_prc', 'seller_promo_discount',
            'sup_rating_prc_up', 'supplier_promo', 'wibes_wb_discount_percent',
            'quantity', 'delivery_amount', 'return_amount', 
            
            # Новые столбцы для возвратов
            'retail_price', 'retail_price_recovery',
            'retail_amount', 'retail_amount_refunded',
            'ppvz_for_pay', 'ppvz_for_recovery',
            'cost_price', 'cost_price_recovered',
            'additional_expenses', 'additional_expenses_recovered',
            'commission_amount', 'commission_amount_reversed',
            'commission_normal', 'commission_normal_reversed',
            'penalty_commission_rub', 'penalty_commission_reversed',
            'delivery_rub',
            'ppvz_reward', 'ppvz_reward_reversed',
            'acquiring_fee', 'acquiring_fee_reversed',
            'acceptance',
            'cashback_amount', 'cashback_amount_reversed',
            'cashback_commission_change', 'cashback_commission_change_reversed',
            'storage_fee', 'penalty', 'deduction', 'installment_cofinancing_amount', 
            'additional_payment', 'payment_schedule'
        ]

    IGNORED_EXTRA_FIELDS = {
        'sale_price_wholesale_discount_prc',
        'article_substitution',
        'sale_price_affiliated_discount_prc',
        # При необходимости можно добавить другие поля, которые не нужно логировать
    }
    
    def _get_api_key(self):
        """Получение API токена из базы данных"""
        start_time = time.time()
        try:
            from app import get_token
            token = get_token()
            if not token:
                log_event('ERROR', '_get_api_key', 'Токен не найден в базе данных')
                raise ValueError("Токен не найден в базе данных")
            
            duration_ms = (time.time() - start_time) * 1000
            log_event('INFO', '_get_api_key', 'Токен успешно получен', 
                     {'token_length': len(token) if token else 0}, duration_ms)
            return token
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', '_get_api_key', f'Ошибка получения токена: {str(e)}', 
                     {'error_details': str(e)}, duration_ms)
            raise
    
    def _get_headers(self):
        """Получение заголовков с токеном"""
        start_time = time.time()
        try:
            headers = {
                "Authorization": self._get_api_key()
            }
            duration_ms = (time.time() - start_time) * 1000
            log_event('DEBUG', '_get_headers', 'Заголовки сформированы', 
                     {'headers_keys': list(headers.keys())}, duration_ms)
            return headers
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', '_get_headers', f'Ошибка формирования заголовков: {str(e)}', 
                     {'error_details': str(e)}, duration_ms)
            raise
    
    def fill_bonus_type_name(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Заполняет пустые значения bonus_type_name значениями из supplier_oper_name
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'fill_bonus_type_name', 'DataFrame пустой, пропускаем заполнение bonus_type_name')
                return df
            
            # Проверяем наличие необходимых столбцов
            required_columns = ['bonus_type_name', 'supplier_oper_name']
            missing_columns = [col for col in required_columns if col not in df.columns]
            
            if missing_columns:
                log_event('WARNING', 'fill_bonus_type_name', 'Отсутствуют необходимые столбцы', 
                         {'missing_columns': missing_columns})
                return df
            
            # Подсчитываем пустые значения до заполнения
            null_bonus_before = df['bonus_type_name'].isna().sum()
            
            # Заполняем NULL значения bonus_type_name значениями из supplier_oper_name
            mask = df['bonus_type_name'].isna() & df['supplier_oper_name'].notna()
            df.loc[mask, 'bonus_type_name'] = df.loc[mask, 'supplier_oper_name']
            
            # Подсчитываем пустые значения после заполнения
            null_bonus_after = df['bonus_type_name'].isna().sum()
            filled_count = null_bonus_before - null_bonus_after
            
            duration_ms = (time.time() - start_time) * 1000
            log_event('INFO', 'fill_bonus_type_name', 'Заполнение bonus_type_name завершено', 
                     {'total_rows': len(df), 'filled_count': filled_count,
                      'null_before': null_bonus_before, 'null_after': null_bonus_after,
                      'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'fill_bonus_type_name', 'Ошибка при заполнении bonus_type_name', 
                     {'error_details': str(e), 'duration_ms': duration_ms})
            return df

    def add_recovery_columns(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Добавляет столбцы для возвратов согласно требованиям
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'add_recovery_columns', 'DataFrame пустой, пропускаем добавление столбцов возвратов')
                return df
            
            initial_rows = len(df)
            
            # 1. retail_price_recovery
            if 'retail_price' in df.columns:
                mask_negative = df['retail_price'] < 0
                df['retail_price_recovery'] = pd.NA
                df.loc[mask_negative, 'retail_price_recovery'] = df.loc[mask_negative, 'retail_price']
                df.loc[mask_negative, 'retail_price'] = pd.NA
            
            # 2. retail_amount_refunded
            if 'retail_amount' in df.columns:
                mask_negative = df['retail_amount'] < 0
                df['retail_amount_refunded'] = pd.NA
                df.loc[mask_negative, 'retail_amount_refunded'] = df.loc[mask_negative, 'retail_amount']
                df.loc[mask_negative, 'retail_amount'] = pd.NA
            
            # 3. ppvz_for_recovery
            if 'ppvz_for_pay' in df.columns:
                mask_negative = df['ppvz_for_pay'] < 0
                df['ppvz_for_recovery'] = pd.NA
                df.loc[mask_negative, 'ppvz_for_recovery'] = df.loc[mask_negative, 'ppvz_for_pay']
                df.loc[mask_negative, 'ppvz_for_pay'] = pd.NA
            
            # 4. cost_price_recovered
            if 'cost_price' in df.columns:
                mask_positive = df['cost_price'] > 0
                df['cost_price_recovered'] = pd.NA
                df.loc[mask_positive, 'cost_price_recovered'] = df.loc[mask_positive, 'cost_price']
                df.loc[mask_positive, 'cost_price'] = pd.NA
            
            # 5. additional_expenses_recovered
            if 'additional_expenses' in df.columns:
                mask_positive = df['additional_expenses'] > 0
                df['additional_expenses_recovered'] = pd.NA
                df.loc[mask_positive, 'additional_expenses_recovered'] = df.loc[mask_positive, 'additional_expenses']
                df.loc[mask_positive, 'additional_expenses'] = pd.NA
            
            # 6. commission_amount_reversed
            if 'commission_amount' in df.columns:
                mask_positive = df['commission_amount'] > 0
                df['commission_amount_reversed'] = pd.NA
                df.loc[mask_positive, 'commission_amount_reversed'] = df.loc[mask_positive, 'commission_amount']
                df.loc[mask_positive, 'commission_amount'] = pd.NA
            
            # 7. commission_normal_reversed
            if 'commission_normal' in df.columns:
                mask_positive = df['commission_normal'] > 0
                df['commission_normal_reversed'] = pd.NA
                df.loc[mask_positive, 'commission_normal_reversed'] = df.loc[mask_positive, 'commission_normal']
                df.loc[mask_positive, 'commission_normal'] = pd.NA
            
            # 8. penalty_commission_reversed
            if 'penalty_commission_rub' in df.columns:
                mask_positive = df['penalty_commission_rub'] > 0
                df['penalty_commission_reversed'] = pd.NA
                df.loc[mask_positive, 'penalty_commission_reversed'] = df.loc[mask_positive, 'penalty_commission_rub']
                df.loc[mask_positive, 'penalty_commission_rub'] = pd.NA
            
            # 9. ppvz_reward_reversed
            if 'ppvz_reward' in df.columns:
                mask_positive = df['ppvz_reward'] > 0
                df['ppvz_reward_reversed'] = pd.NA
                df.loc[mask_positive, 'ppvz_reward_reversed'] = df.loc[mask_positive, 'ppvz_reward']
                df.loc[mask_positive, 'ppvz_reward'] = pd.NA
            
            # 10. acquiring_fee_reversed
            if 'acquiring_fee' in df.columns:
                mask_positive = df['acquiring_fee'] > 0
                df['acquiring_fee_reversed'] = pd.NA
                df.loc[mask_positive, 'acquiring_fee_reversed'] = df.loc[mask_positive, 'acquiring_fee']
                df.loc[mask_positive, 'acquiring_fee'] = pd.NA
            
            # 11. cashback_amount_reversed
            if 'cashback_amount' in df.columns:
                mask_positive = df['cashback_amount'] > 0
                df['cashback_amount_reversed'] = pd.NA
                df.loc[mask_positive, 'cashback_amount_reversed'] = df.loc[mask_positive, 'cashback_amount']
                df.loc[mask_positive, 'cashback_amount'] = pd.NA
            
            # 12. cashback_commission_change_reversed
            if 'cashback_commission_change' in df.columns:
                mask_positive = df['cashback_commission_change'] > 0
                df['cashback_commission_change_reversed'] = pd.NA
                df.loc[mask_positive, 'cashback_commission_change_reversed'] = df.loc[mask_positive, 'cashback_commission_change']
                df.loc[mask_positive, 'cashback_commission_change'] = pd.NA
            
            # Статистика
            stats = {
                'retail_price_recovery': (df['retail_price_recovery'] != 0).sum() if 'retail_price_recovery' in df.columns else 0,
                'retail_amount_refunded': (df['retail_amount_refunded'] != 0).sum() if 'retail_amount_refunded' in df.columns else 0,
                'ppvz_for_recovery': (df['ppvz_for_recovery'] != 0).sum() if 'ppvz_for_recovery' in df.columns else 0,
                'cost_price_recovered': (df['cost_price_recovered'] != 0).sum() if 'cost_price_recovered' in df.columns else 0,
                'additional_expenses_recovered': (df['additional_expenses_recovered'] != 0).sum() if 'additional_expenses_recovered' in df.columns else 0,
            }
            
            duration_ms = (time.time() - start_time) * 1000
            log_event('INFO', 'add_recovery_columns', 'Столбцы возвратов добавлены', 
                    {'total_rows': initial_rows, 'stats': stats, 'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'add_recovery_columns', 'Ошибка при добавлении столбцов возвратов', 
                    {'error_details': str(e), 'duration_ms': duration_ms})
            return df

    def calculate_return_delivery_rub(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Рассчитывает столбец return_delivery_rub (стоимость обратной логистики)
        Правило: Если return_amount == 1, то return_delivery_rub = delivery_rub, а delivery_rub = 0
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'calculate_return_delivery_rub', 'DataFrame пустой, пропускаем расчет return_delivery_rub')
                return df
            
            # Проверяем наличие необходимых столбцов
            if 'return_amount' not in df.columns or 'delivery_rub' not in df.columns:
                missing_cols = []
                if 'return_amount' not in df.columns:
                    missing_cols.append('return_amount')
                if 'delivery_rub' not in df.columns:
                    missing_cols.append('delivery_rub')
                
                duration_ms = (time.time() - start_time) * 1000
                log_event('WARNING', 'calculate_return_delivery_rub', 'Отсутствуют столбцы для расчета return_delivery_rub', 
                        {'missing_columns': missing_cols, 'duration_ms': duration_ms})
                return df
            
            # Инициализируем столбец со значением по умолчанию 0
            df['return_delivery_rub'] = pd.NA
            
            # Находим строки с возвратами (return_amount == 1)
            return_mask = df['return_amount'] == 1
            return_rows_count = return_mask.sum()
            
            if return_rows_count > 0:
                # Применяем правило: если return_amount == 1, то 
                # return_delivery_rub = delivery_rub, а delivery_rub = 0
                df.loc[return_mask, 'return_delivery_rub'] = df.loc[return_mask, 'delivery_rub']
                df.loc[return_mask, 'delivery_rub'] = pd.NA
            
            duration_ms = (time.time() - start_time) * 1000
            log_event('INFO', 'calculate_return_delivery_rub', 'Расчет return_delivery_rub завершен', 
                    {'total_rows': len(df), 'return_rows': return_rows_count,
                    'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'calculate_return_delivery_rub', 'Ошибка при расчете return_delivery_rub', 
                    {'error_details': str(e), 'duration_ms': duration_ms})
            return df

    def fetch_report_for_date(self, date_from: str, date_to: str) -> list:
        start_time = time.time()
        all_data = []
        rrdid = 0
        limit = 100000
        page = 1
        total_records = 0

        log_event('INFO', 'fetch_report_for_date', 'Начало получения отчета',
                {'date_from': date_from, 'date_to': date_to, 'limit': limit})

        session = requests.Session()
        headers = self._get_headers()
        
        while True:
            params = {
                "dateFrom": f"{date_from}T00:00:00",
                "dateTo": f"{date_to}T23:59:59",
                "limit": limit,
                "rrdid": rrdid,
                "period": "daily"
            }
            
            request_start = time.time()
            try:
                response = session.get(
                    self.base_url,
                    headers=headers,
                    params=params,
                    timeout=30
                )
                request_duration = (time.time() - request_start) * 1000

                # ---- Rate limiting обработка ----
                rate_limit_remaining = response.headers.get('X-Ratelimit-Remaining')
                rate_limit_reset = response.headers.get('X-Ratelimit-Reset')
                rate_limit_retry = response.headers.get('X-Ratelimit-Retry')
                
                if response.status_code == 200:
                    data = response.json()
                    records_on_page = len(data) if data else 0
                    total_records += records_on_page
                    
                    log_event('INFO', 'fetch_report_for_date', 'Получены данные со страницы',
                            {'page': page, 'records_on_page': records_on_page,
                            'total_records': total_records, 'status_code': response.status_code,
                            'response_time_ms': request_duration, 'rrdid': rrdid,
                            'rate_limit_remaining': rate_limit_remaining})
                    
                    if data:
                        all_data.extend(data)
                        if len(data) < limit:
                            log_event('INFO', 'fetch_report_for_date', 'Последняя страница получена',
                                    {'page': page, 'total_pages': page, 'total_records': total_records})
                            break
                        
                        # Обновляем rrdid для следующей страницы
                        rrdid = data[-1].get("rrd_id", rrdid + limit)
                        page += 1
                    else:
                        break
                    
                    # ---- Умная пауза на основе оставшихся лимитов ----
                    if rate_limit_remaining is not None:
                        try:
                            remaining = int(rate_limit_remaining)
                            if remaining == 0 and rate_limit_reset is not None:
                                wait = int(rate_limit_reset) + 1  # небольшой запас
                                log_event('INFO', 'fetch_report_for_date',
                                        f'Лимит исчерпан, пауза {wait} сек до восстановления burst',
                                        {'wait_seconds': wait, 'reset_after': rate_limit_reset})
                                time.sleep(wait)
                            elif remaining > 0:
                                # Можно продолжать без паузы (burst-режим)
                                pass
                        except ValueError:
                            pass
                            
                elif response.status_code == 204:
                    log_event('INFO', 'fetch_report_for_date', 'Нет данных за период',
                            {'date_from': date_from, 'date_to': date_to, 'status_code': response.status_code})
                    break
                    
                elif response.status_code == 429:
                    if rate_limit_retry is not None:
                        try:
                            wait = int(rate_limit_retry) + 1
                        except ValueError:
                            wait = 65  # fallback
                    else:
                        wait = 65
                    log_event('WARNING', 'fetch_report_for_date', 'Превышен лимит запросов',
                            {'page': page, 'status_code': response.status_code, 
                            'wait_time': wait, 'retry_after': rate_limit_retry})
                    time.sleep(wait)
                    continue  # повторяем этот же запрос
                    
                else:
                    log_event('ERROR', 'fetch_report_for_date', 'Ошибка при запросе к API',
                            {'page': page, 'status_code': response.status_code,
                            'response_text': response.text[:500] if response.text else '',
                            'response_time_ms': request_duration})
                    break
                    
            except requests.exceptions.RequestException as e:
                request_duration = (time.time() - request_start) * 1000
                log_event('ERROR', 'fetch_report_for_date', 'Исключение при запросе к API',
                        {'page': page, 'error_type': type(e).__name__, 'error_details': str(e),
                        'response_time_ms': request_duration})
                break

        total_duration = (time.time() - start_time) * 1000
        log_event('INFO', 'fetch_report_for_date', 'Завершение получения отчета',
                {'date_from': date_from, 'date_to': date_to, 'total_records': total_records,
                'total_pages': page, 'total_time_ms': total_duration})
        
        return all_data

    def fetch_data_by_date(self, date_str: str) -> pd.DataFrame:
        """
        Получение данных за указанную дату
        """
        start_time = time.time()
        try:
            log_event('INFO', 'fetch_data_by_date', 'Начало получения данных за дату', 
                     {'date': date_str})
            
            # Запрашиваем данные за указанную дату
            data = self.fetch_report_for_date(date_str, date_str)
            
            # Преобразуем в DataFrame
            if data:
                df = pd.DataFrame(data)
                duration_ms = (time.time() - start_time) * 1000
                log_event('INFO', 'fetch_data_by_date', 'Данные успешно получены и преобразованы', 
                         {'date': date_str, 'records_count': len(df), 'columns_count': len(df.columns),
                          'duration_ms': duration_ms})
                return df
            else:
                duration_ms = (time.time() - start_time) * 1000
                log_event('INFO', 'fetch_data_by_date', 'Нет данных за дату', 
                         {'date': date_str, 'duration_ms': duration_ms})
                return pd.DataFrame()
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'fetch_data_by_date', 'Ошибка при получении данных за дату', 
                     {'date': date_str, 'error_details': str(e), 'duration_ms': duration_ms})
            return pd.DataFrame()
    
    def filter_by_quantity(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Фильтрует данные по столбцу quantity, оставляя только значения 0 и 1
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'filter_by_quantity', 'DataFrame пустой, пропускаем фильтрацию')
                return df
                
            initial_count = len(df)
            
            if 'quantity' not in df.columns:
                log_event('WARNING', 'filter_by_quantity', 'Столбец quantity отсутствует')
                return df
            
            # Фильтруем только строки с quantity равным 0 или 1
            filtered_df = df[df['quantity'].isin([0, 1])].copy()
            
            filtered_count = len(filtered_df)
            removed_count = initial_count - filtered_count
            duration_ms = (time.time() - start_time) * 1000
            
            log_event('INFO', 'filter_by_quantity', 'Фильтрация по quantity завершена', 
                     {'initial_count': initial_count, 'filtered_count': filtered_count,
                      'removed_count': removed_count, 'duration_ms': duration_ms})
            
            return filtered_df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'filter_by_quantity', 'Ошибка при фильтрации по quantity', 
                     {'error_details': str(e), 'duration_ms': duration_ms})
            return df
    
    def remove_unused_columns(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Удаляет ненужные столбцы из DataFrame
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'remove_unused_columns', 'DataFrame пустой, пропускаем удаление столбцов')
                return df
            
            initial_columns = len(df.columns)
            
            # Список столбцов для удаления
            columns_to_remove = [
                'realizationreport_id',
                'date_from',
                'date_to',
                'create_dt',
                'currency_name',
                'suppliercontract_code',
                'fix_tariff_date_from',
                'fix_tariff_date_to',
                'ppvz_vw',
                'ppvz_vw_nds',
                'acquiring_bank',
                'ppvz_supplier_name',
                'ppvz_inn',
                'declaration_number',
                'ppvz_supplier_id',
                'srv_dbs',
                'is_legal_entity',
                'rebill_logistic_org',
                'report_type',
                'ppvz_sales_commission',
                'cashback_discount',
                'rebill_logistic_cost',
                'retail_price_withdisc_rub',
                'kiz'
            ]
            
            # Удаляем столбцы
            existing_columns = [col for col in columns_to_remove if col in df.columns]
            if existing_columns:
                df = df.drop(columns=existing_columns)
                remaining_columns = len(df.columns)
                removed_count = len(existing_columns)
                
                duration_ms = (time.time() - start_time) * 1000
                log_event('INFO', 'remove_unused_columns', 'Столбцы удалены', 
                         {'initial_columns': initial_columns, 'remaining_columns': remaining_columns,
                          'removed_columns': removed_count, 'removed_columns_list': existing_columns,
                          'duration_ms': duration_ms})
            else:
                duration_ms = (time.time() - start_time) * 1000
                log_event('INFO', 'remove_unused_columns', 'Нет столбцов для удаления', 
                         {'initial_columns': initial_columns, 'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'remove_unused_columns', 'Ошибка при удалении столбцов', 
                     {'error_details': str(e), 'duration_ms': duration_ms})
            return df
    
    def process_returns(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Обрабатывает строки с возвратами
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'process_returns', 'DataFrame пустой, пропускаем обработку возвратов')
                return df
            
            # Проверяем наличие необходимых столбцов
            required_columns = ['doc_type_name', 'quantity', 'retail_price', 'retail_amount', 
                            'ppvz_for_pay', 'acquiring_fee']
            
            missing_columns = [col for col in required_columns if col not in df.columns]
            
            if missing_columns:
                log_event('WARNING', 'process_returns', 'Отсутствуют необходимые столбцы', 
                         {'missing_columns': missing_columns})
                return df
            
            # Подсчет возвратов
            returns_count = len(df[df['doc_type_name'] == 'Возврат'])
            total_count = len(df)
            duration_ms = (time.time() - start_time) * 1000
            
            log_event('INFO', 'process_returns', 'Обработка возвратов завершена', 
                     {'total_records': total_count, 'returns_count': returns_count,
                      'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'process_returns', 'Ошибка при обработке возвратов', 
                     {'error_details': str(e), 'duration_ms': duration_ms})
            return df
    
    def calculate_commission_amount(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Рассчитывает столбец commission_amount как retail_price * commission_percent / 100
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'calculate_commission_amount', 'DataFrame пустой, пропускаем расчет комиссии')
                return df
            
            # Проверяем наличие необходимых столбцов
            if 'retail_price' in df.columns and 'commission_percent' in df.columns:
                # Подсчитываем строки с данными для расчета
                rows_with_data = df['retail_price'].notna() & df['commission_percent'].notna()
                rows_count = rows_with_data.sum()
                
                # Рассчитываем commission_amount
                df['commission_amount'] = df['retail_price'] * df['commission_percent'] / 100
                
                duration_ms = (time.time() - start_time) * 1000
                log_event('INFO', 'calculate_commission_amount', 'Комиссия рассчитана', 
                         {'total_rows': len(df), 'rows_with_calculation': rows_count,
                          'duration_ms': duration_ms})
            else:
                missing_cols = []
                if 'retail_price' not in df.columns:
                    missing_cols.append('retail_price')
                if 'commission_percent' not in df.columns:
                    missing_cols.append('commission_percent')
                
                duration_ms = (time.time() - start_time) * 1000
                log_event('WARNING', 'calculate_commission_amount', 'Отсутствуют столбцы для расчета', 
                         {'missing_columns': missing_cols, 'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'calculate_commission_amount', 'Ошибка при расчете комиссии', 
                     {'error_details': str(e), 'duration_ms': duration_ms})
            return df
    
    def add_commission_normal_column(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Добавляет столбец commission_normal как base_comission * retail_price / 100
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'add_commission_normal_column', 'DataFrame пустой, пропускаем добавление commission_normal')
                return df
            
            # Проверяем наличие необходимых столбцов
            if 'base_comission' in df.columns and 'retail_price' in df.columns:
                # Подсчитываем строки с данными для расчета
                rows_with_data = df['base_comission'].notna() & df['retail_price'].notna()
                rows_count = rows_with_data.sum()
                
                # Рассчитываем commission_normal
                df['commission_normal'] = df['base_comission'] * df['retail_price'] / 100
                
                duration_ms = (time.time() - start_time) * 1000
                log_event('INFO', 'add_commission_normal_column', 'Commission_normal добавлен', 
                         {'total_rows': len(df), 'rows_with_calculation': rows_count,
                          'duration_ms': duration_ms})
            else:
                missing_cols = []
                if 'base_comission' not in df.columns:
                    missing_cols.append('base_comission')
                if 'retail_price' not in df.columns:
                    missing_cols.append('retail_price')
                
                duration_ms = (time.time() - start_time) * 1000
                log_event('WARNING', 'add_commission_normal_column', 'Отсутствуют столбцы для расчета commission_normal', 
                         {'missing_columns': missing_cols, 'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'add_commission_normal_column', 'Ошибка при добавлении commission_normal', 
                     {'error_details': str(e), 'duration_ms': duration_ms})
            return df

    def add_delivery_time_column(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Добавляет столбец "Время доставки (в часах)" как разницу между sale_dt и order_dt
        ТОЛЬКО для строк, где bonus_type_name = "К клиенту при продаже"
        В остальных случаях значение будет NULL
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'add_delivery_time_column', 'DataFrame пустой, пропускаем добавление времени доставки')
                return df
            
            # Проверяем наличие необходимых столбцов
            if 'sale_dt' not in df.columns or 'order_dt' not in df.columns or 'bonus_type_name' not in df.columns:
                missing_cols = []
                if 'sale_dt' not in df.columns:
                    missing_cols.append('sale_dt')
                if 'order_dt' not in df.columns:
                    missing_cols.append('order_dt')
                if 'bonus_type_name' not in df.columns:
                    missing_cols.append('bonus_type_name')
                
                log_event('WARNING', 'add_delivery_time_column', 'Отсутствуют столбцы для расчета времени доставки', 
                        {'missing_columns': missing_cols})
                return df
            
            # Создаем столбец delivery_time_hours с NULL значениями по умолчанию
            df['delivery_time_hours'] = pd.NA
            
            # Преобразуем строки в datetime и удаляем временные зоны
            df['order_dt'] = pd.to_datetime(df['order_dt'], errors='coerce').dt.tz_localize(None)
            df['sale_dt'] = pd.to_datetime(df['sale_dt'], errors='coerce').dt.tz_localize(None)
            
            # Создаем маску для строк, где bonus_type_name = "К клиенту при продаже"
            condition_mask = df['bonus_type_name'] == 'К клиенту при продаже'
            condition_rows_count = condition_mask.sum()
            
            if condition_rows_count > 0:
                # Рассчитываем разницу в часах только для строк, удовлетворяющих условию
                time_difference = (df.loc[condition_mask, 'sale_dt'] - df.loc[condition_mask, 'order_dt']).dt.total_seconds() / 3600
                
                # Округляем до целого и преобразуем в Int64
                df.loc[condition_mask, 'delivery_time_hours'] = time_difference.round().astype('Int64')
                
                # Статистика по времени доставки (только для строк с условием)
                avg_delivery_time = df.loc[condition_mask, 'delivery_time_hours'].mean()
                min_delivery_time = df.loc[condition_mask, 'delivery_time_hours'].min()
                max_delivery_time = df.loc[condition_mask, 'delivery_time_hours'].max()
            else:
                avg_delivery_time = min_delivery_time = max_delivery_time = None
            
            # Общая статистика
            rows_with_bonus = condition_rows_count
            rows_without_bonus = len(df) - condition_rows_count
            rows_with_time = df['delivery_time_hours'].notna().sum()
            
            duration_ms = (time.time() - start_time) * 1000
            log_event('INFO', 'add_delivery_time_column', 'Время доставки добавлено (только для bonus_type_name="К клиенту при продаже")', 
                    {'total_rows': len(df),
                    'rows_with_bonus': rows_with_bonus,
                    'rows_without_bonus': rows_without_bonus,
                    'rows_with_time': rows_with_time,
                    'avg_delivery_hours': avg_delivery_time, 
                    'min_delivery_hours': min_delivery_time,
                    'max_delivery_hours': max_delivery_time,
                    'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'add_delivery_time_column', 'Ошибка при добавлении времени доставки', 
                    {'error_details': str(e), 'duration_ms': duration_ms})
            return df


    def add_type_fb_column(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Добавляет столбец type_fb:
        - Если в office_name есть слово "МП", то type_fb = "FBS"
        - В остальных случаях type_fb = "FBO"
        БЕЗ условия на delivery_time_hours
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'add_type_fb_column', 'DataFrame пустой, пропускаем добавление type_fb')
                return df
                
            # Проверяем наличие необходимого столбца
            if 'office_name' not in df.columns:
                log_event('WARNING', 'add_type_fb_column', 'Отсутствует столбец office_name')
                return df
            
            # Создаем столбец type_fb с NULL значениями по умолчанию
            df['type_fb'] = pd.NA
            
            # Определяем type_fb для всех строк
            def determine_type_fb(office_name):
                if pd.isna(office_name):
                    return pd.NA
                if isinstance(office_name, str) and 'МП' in office_name:
                    return 'FBS'
                return 'FBO'
            
            # Применяем функцию к каждой строке
            df['type_fb'] = df['office_name'].apply(determine_type_fb)
            
            # Статистика по типам
            fbs_count = (df['type_fb'] == 'FBS').sum()
            fbo_count = (df['type_fb'] == 'FBO').sum()
            null_count = (df['type_fb'].isna()).sum()
            
            duration_ms = (time.time() - start_time) * 1000
            log_event('INFO', 'add_type_fb_column', 'Type_fb добавлен (без условия на delivery_time_hours)', 
                    {'total_rows': len(df),
                    'fbs_count': fbs_count,
                    'fbo_count': fbo_count,
                    'null_count': null_count,
                    'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'add_type_fb_column', 'Ошибка при добавлении type_fb', 
                    {'error_details': str(e), 'duration_ms': duration_ms})
            return df

    def add_base_commission_column(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Добавляет столбец base_comission путем поиска комиссий на сервере sosna.tech
        по subject_name с ТОЧНЫМ совпадением
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'add_base_commission_column', 'DataFrame пустой, пропускаем добавление базовой комиссии')
                return df
            
            # Проверяем наличие необходимых столбцов
            if 'subject_name' not in df.columns or 'type_fb' not in df.columns:
                missing_cols = []
                if 'subject_name' not in df.columns:
                    missing_cols.append('subject_name')
                if 'type_fb' not in df.columns:
                    missing_cols.append('type_fb')
                
                log_event('WARNING', 'add_base_commission_column', 'Отсутствуют столбцы для расчета базовой комиссии', 
                        {'missing_columns': missing_cols})
                return df
            
            # Логируем статистику по столбцам
            subject_stats = {
                'total_rows': len(df),
                'subject_name_not_null': df['subject_name'].notna().sum(),
                'type_fb_not_null': df['type_fb'].notna().sum(),
                'unique_subjects': df['subject_name'].nunique()
            }
            
            log_event('DEBUG', 'add_base_commission_column', 'Статистика по данным', {'stats': subject_stats})
            
            # Инициализируем столбец со значением по умолчанию 0
            df['base_comission'] = 0
            
            # Получаем уникальные subject_name
            unique_subjects = df['subject_name'].dropna().unique()
            subjects_count = len(unique_subjects)
            
            if subjects_count == 0:
                log_event('INFO', 'add_base_commission_column', 'Нет уникальных предметов для поиска комиссий')
                return df
            
            # Словарь для хранения комиссий
            commissions_dict = {}
            api_calls = 0
            exact_matches = 0
            not_found_count = 0
            
            log_event('INFO', 'add_base_commission_column', 'Начало поиска комиссий с ТОЧНЫМ совпадением', 
                    {'unique_subjects_count': subjects_count})
            
            base_url = "http://sosna.tech"
            
            for subject in unique_subjects:
                try:
                    subject_str = str(subject).strip()
                    subject_key = subject_str.lower()
                    
                    # Пропускаем пустые строки
                    if not subject_str:
                        commissions_dict[subject_key] = {'kgvpMarketplace': 0, 'paidStorageKgvp': 0}
                        continue
                    
                    log_event('DEBUG', 'add_base_commission_column', 'Поиск точной комиссии для subject', 
                            {'subject': subject_str})
                    
                    # Запрос с ТОЧНЫМ поиском по названию
                    response = requests.get(
                        f"{base_url}/commissions",
                        params={
                            "search": subject_str,  # ТОЧНОЕ название
                            "per_page": 50
                        },
                        timeout=15
                    )
                    
                    api_calls += 1
                    
                    if response.status_code == 200:
                        data = response.json()
                        commissions = data.get('commissions', [])
                        total_found = data.get('pagination', {}).get('total', 0)
                        
                        log_event('DEBUG', 'add_base_commission_column', 'Ответ API для точного поиска', 
                                {'subject': subject_str, 'total_found': total_found, 'commissions_count': len(commissions)})
                        
                        # Ищем ТОЧНОЕ совпадение в результатах
                        exact_match_found = False
                        commission_data = None
                        
                        for commission in commissions:
                            api_subject_name = commission.get('subjectName')
                            if api_subject_name:
                                # Сравниваем ТОЧНО, с учетом регистра и пробелов
                                if str(api_subject_name).strip() == subject_str:
                                    commission_data = {
                                        'kgvpMarketplace': commission.get('kgvpMarketplace', 0),
                                        'paidStorageKgvp': commission.get('paidStorageKgvp', 0),
                                        'found_via': 'exact_match'
                                    }
                                    exact_match_found = True
                                    exact_matches += 1
                                    
                                    log_event('DEBUG', 'add_base_commission_column', 'Найдено ТОЧНОЕ совпадение', 
                                            {'subject': subject_str, 
                                            'api_subject': api_subject_name,
                                            'kgvpMarketplace': commission.get('kgvpMarketplace'),
                                            'paidStorageKgvp': commission.get('paidStorageKgvp')})
                                    break
                        
                        if exact_match_found and commission_data:
                            commissions_dict[subject_key] = commission_data
                        else:
                            # Если точное совпадение не найдено, логируем все доступные варианты для отладки
                            available_subjects = [c.get('subjectName', 'N/A') for c in commissions if c.get('subjectName')]
                            log_event('WARNING', 'add_base_commission_column', 'ТОЧНОЕ совпадение не найдено', 
                                    {'subject': subject_str,
                                    'available_subjects_in_response': available_subjects[:10],
                                    'total_available': len(available_subjects)})
                            
                            # Ставим 0 как значение по умолчанию
                            commissions_dict[subject_key] = {'kgvpMarketplace': 0, 'paidStorageKgvp': 0}
                            not_found_count += 1
                    else:
                        log_event('ERROR', 'add_base_commission_column', 'Ошибка API при поиске комиссии', 
                                {'subject': subject_str, 'status_code': response.status_code})
                        commissions_dict[subject_key] = {'kgvpMarketplace': 0, 'paidStorageKgvp': 0}
                        not_found_count += 1
                
                except Exception as e:
                    log_event('ERROR', 'add_base_commission_column', 'Исключение при поиске комиссии', 
                            {'subject': str(subject), 'error': str(e)[:200]})
                    commissions_dict[str(subject).strip().lower()] = {'kgvpMarketplace': 0, 'paidStorageKgvp': 0}
                    not_found_count += 1
            
            # Логируем результаты поиска
            found_subjects = [k for k, v in commissions_dict.items() 
                            if v.get('kgvpMarketplace', 0) != 0 or v.get('paidStorageKgvp', 0) != 0]
            
            log_event('INFO', 'add_base_commission_column', 'Результаты точного поиска', 
                    {'total_subjects': subjects_count,
                    'exact_matches': exact_matches,
                    'not_found': not_found_count,
                    'found_examples': found_subjects[:5] if found_subjects else [],
                    'api_calls': api_calls})
            
            # Логируем примеры НЕ найденных комиссий для отладки
            if not_found_count > 0:
                not_found_examples = [k for k, v in commissions_dict.items() 
                                    if v.get('kgvpMarketplace', 0) == 0 and v.get('paidStorageKgvp', 0) == 0]
                log_event('WARNING', 'add_base_commission_column', 'Примеры не найденных комиссий', 
                        {'not_found_examples': not_found_examples[:10]})
            
            # Добавляем столбец base_comission
            def get_base_commission(row):
                subject = row['subject_name']
                type_fb = row['type_fb']
                
                if pd.isna(subject) or pd.isna(type_fb):
                    return 0
                
                subject_key = str(subject).strip().lower()
                
                if subject_key in commissions_dict:
                    commission_data = commissions_dict[subject_key]
                    
                    if type_fb == 'FBS':
                        return commission_data['kgvpMarketplace']
                    elif type_fb == 'FBO':
                        return commission_data['paidStorageKgvp']
                    else:
                        # Если type_fb не FBS и не FBO, возвращаем 0
                        log_event('DEBUG', 'add_base_commission_column', 'Некорректный type_fb', 
                                {'subject': subject, 'type_fb': type_fb})
                        return 0
                
                return 0
            
            # Применяем функцию к каждой строке
            df['base_comission'] = df.apply(get_base_commission, axis=1)
            
            # Статистика по комиссиям
            non_zero_commission = (df['base_comission'] != 0).sum()
            zero_commission_count = (df['base_comission'] == 0).sum()
            total_rows = len(df)
            
            # Примеры строк для отладки
            sample_data = []
            for idx, row in df.head(10).iterrows():
                subject_key = str(row['subject_name']).strip().lower() if not pd.isna(row['subject_name']) else 'N/A'
                commission_data = commissions_dict.get(subject_key, {})
                sample_data.append({
                    'subject': row['subject_name'],
                    'type_fb': row['type_fb'],
                    'base_comission': row['base_comission'],
                    'kgvpMarketplace': commission_data.get('kgvpMarketplace', 0),
                    'paidStorageKgvp': commission_data.get('paidStorageKgvp', 0)
                })
            
            duration_ms = (time.time() - start_time) * 1000
            
            log_event('INFO', 'add_base_commission_column', 'Точный поиск комиссий завершен', 
                    {'total_rows': total_rows,
                    'non_zero_commissions': non_zero_commission,
                    'zero_commissions': zero_commission_count,
                    'success_rate_percent': (non_zero_commission / total_rows * 100) if total_rows > 0 else 0,
                    'exact_matches_found': exact_matches,
                    'api_calls_made': api_calls,
                    'sample_results': sample_data[:3],
                    'duration_ms': duration_ms})
            
            return df
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'add_base_commission_column', 'Критическая ошибка при точном поиске комиссий', 
                    {'error_details': str(e), 'traceback': traceback.format_exc(), 'duration_ms': duration_ms})
            return df

    def add_penalty_commission_columns(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Добавляет два столбца:
        1. penalty_commission_percent - Штрафная комиссия, которая равна commission_percent - base_comission.
        2. penalty_commission_rub - Переплата в рублях, равная penalty_commission_percent * retail_price
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'add_penalty_commission_columns', 'DataFrame пустой, пропускаем добавление штрафных комиссий')
                return df
            
            # Проверяем наличие необходимых столбцов
            required_columns = ['commission_percent', 'base_comission', 'retail_price']
            missing_columns = [col for col in required_columns if col not in df.columns]
            
            if missing_columns:
                log_event('WARNING', 'add_penalty_commission_columns', 'Отсутствуют столбцы для расчета штрафных комиссий', 
                         {'missing_columns': missing_columns})
                return df
            
            # Подсчитываем строки с нулевой комиссией
            zero_commission_rows = (df['commission_percent'] == 0).sum()
            
            # ПРАВИЛО 1: Если commission_percent = 0, то base_comission = 0
            df.loc[df['commission_percent'] == 0, 'base_comission'] = 0
            
            # Рассчитываем штрафную комиссию в процентах
            df['penalty_commission_percent'] = df.apply(
                lambda row: 0 if row['commission_percent'] == 0 else row['commission_percent'] - row['base_comission'],
                axis=1
            )
            
            # Рассчитываем переплату в рублях
            df['penalty_commission_rub'] = df['penalty_commission_percent'] * df['retail_price'] / 100
            
            # Статистика по штрафным комиссиям
            avg_penalty_percent = df['penalty_commission_percent'].mean()
            avg_penalty_rub = df['penalty_commission_rub'].mean()
            positive_penalty_rows = (df['penalty_commission_percent'] > 0).sum()
            
            duration_ms = (time.time() - start_time) * 1000
            log_event('INFO', 'add_penalty_commission_columns', 'Штрафные комиссии добавлены', 
                     {'total_rows': len(df), 'zero_commission_rows': zero_commission_rows,
                      'positive_penalty_rows': positive_penalty_rows,
                      'avg_penalty_percent': avg_penalty_percent, 'avg_penalty_rub': avg_penalty_rub,
                      'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'add_penalty_commission_columns', 'Ошибка при добавлении штрафных комиссий', 
                     {'error_details': str(e), 'duration_ms': duration_ms})
            return df
    
    def add_cost_columns(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Добавляет столбцы себестоимости и дополнительных расходов,
        полученные с сервера sosna.tech по артикулу продавца (sa_name)
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'add_cost_columns', 'DataFrame пустой, пропускаем добавление себестоимости')
                return df
            
            # Проверяем наличие необходимых столбцов
            if 'sa_name' not in df.columns:
                log_event('WARNING', 'add_cost_columns', 'Отсутствует столбец sa_name')
                return df
            
            # Проверяем наличие столбца retail_price для применения правил
            if 'retail_price' not in df.columns:
                log_event('WARNING', 'add_cost_columns', 'Отсутствует столбец retail_price')
                return df
            
            # Получаем уникальные артикулы продавца
            unique_articles = df['sa_name'].dropna().unique()
            articles_count = len(unique_articles)
            
            if articles_count == 0:
                df['cost_price'] = None
                df['additional_expenses'] = None
                log_event('INFO', 'add_cost_columns', 'Нет уникальных артикулов для поиска себестоимости')
                return df
            
            # Разбиваем на пакеты по 50 артикулов
            batch_size = 50
            costs_dict = {}
            api_calls = 0
            successful_calls = 0
            total_costs_found = 0
            
            log_event('INFO', 'add_cost_columns', 'Начало получения себестоимостей с сервера', 
                     {'unique_articles_count': articles_count, 'batch_size': batch_size})
            
            for i in range(0, len(unique_articles), batch_size):
                batch = unique_articles[i:i + batch_size]
                batch_str = ','.join(str(article) for article in batch if pd.notna(article))
                
                try:
                    api_calls += 1
                    # Используем GET с параметром my_articles
                    response = requests.get(
                        self.costs_base_url,
                        params={
                            "my_articles": batch_str,
                            "per_page": len(batch) * 2
                        },
                        timeout=30
                    )
                    
                    if response.status_code == 200:
                        data = response.json()
                        if data.get('costs') and len(data['costs']) > 0:
                            for cost_data in data['costs']:
                                article = cost_data.get('my_article')
                                if article:
                                    # Ключом делаем строку в ВЕРХНЕМ регистре для единообразия
                                    article_key = str(article).strip().upper()
                                    costs_dict[article_key] = {
                                        'cost_price': cost_data.get('cost_price'),
                                        'additional_expenses': cost_data.get('additional_expenses')
                                    }
                                    total_costs_found += 1
                            successful_calls += 1
                    elif response.status_code == 414:
                        # Уменьшаем размер следующего пакета
                        batch_size = max(10, batch_size // 2)
                        i -= batch_size  # Вернемся назад
                        log_event('WARNING', 'add_cost_columns', 'URI слишком длинный, уменьшаем размер пакета', 
                                 {'new_batch_size': batch_size})
                        continue
                    else:
                        log_event('WARNING', 'add_cost_columns', 'Ошибка API при получении себестоимости', 
                                 {'batch_index': i, 'status_code': response.status_code})
                        
                except Exception as e:
                    log_event('WARNING', 'add_cost_columns', 'Исключение при получении себестоимости', 
                             {'batch_index': i, 'error': str(e)})
                    continue
            
            # Добавляем столбцы в DataFrame
            def get_cost_price(row):
                article = row['sa_name']
                retail_price = row['retail_price']
                
                # ПРАВИЛО 1: Если retail_price = 0, то cost_price = 0
                if retail_price == 0:
                    return 0
                
                if pd.isna(article):
                    return None
                
                # Приводим артикул к ВЕРХНЕМУ регистру для поиска
                article_upper = str(article).strip().upper()
                return costs_dict.get(article_upper, {}).get('cost_price')
            
            def get_additional_expenses(row):
                article = row['sa_name']
                retail_price = row['retail_price']
                
                # ПРАВИЛО 2: Если retail_price = 0, то additional_expenses = 0
                if retail_price == 0:
                    return 0
                
                if pd.isna(article):
                    return None
                
                # Приводим артикул к ВЕРХНЕМУ регистру для поиска
                article_upper = str(article).strip().upper()
                return costs_dict.get(article_upper, {}).get('additional_expenses')
            
            # Применяем функции к каждой строке DataFrame
            df['cost_price'] = df.apply(get_cost_price, axis=1)
            df['additional_expenses'] = df.apply(get_additional_expenses, axis=1)
            
            # Статистика по себестоимости
            rows_with_cost = df['cost_price'].notna().sum()
            rows_with_expenses = df['additional_expenses'].notna().sum()
            zero_cost_rows = (df['cost_price'] == 0).sum()
            
            duration_ms = (time.time() - start_time) * 1000
            log_event('INFO', 'add_cost_columns', 'Себестоимости добавлены', 
                     {'total_rows': len(df), 'unique_articles': articles_count,
                      'api_calls': api_calls, 'successful_calls': successful_calls,
                      'costs_found': total_costs_found, 'rows_with_cost': rows_with_cost,
                      'rows_with_expenses': rows_with_expenses, 'zero_cost_rows': zero_cost_rows,
                      'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'add_cost_columns', 'Ошибка при добавлении себестоимостей', 
                     {'error_details': str(e), 'duration_ms': duration_ms})
            return df
    
    def invert_values_for_returns(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Умножает указанные столбцы на -1 для всех строк
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'invert_values_for_returns', 'DataFrame пустой, пропускаем инвертирование значений')
                return df
            
            # Столбцы для умножения на -1
            columns_to_invert = [
                'cost_price',
                'additional_expenses',
                'commission_amount',
                'commission_normal',
                'penalty_commission_rub',
                'delivery_rub',
                'ppvz_reward',
                'acquiring_fee',
                'acceptance',
                'cashback_amount',
                'cashback_commission_change',
                'storage_fee',
                'penalty',
                'deduction',
                'installment_cofinancing_amount',
                'additional_payment',
                'payment_schedule'
            ]
            
            # Проверяем наличие столбцов в DataFrame
            existing_columns = [col for col in columns_to_invert if col in df.columns]
            inverted_columns_count = len(existing_columns)
            
            if not existing_columns:
                log_event('INFO', 'invert_values_for_returns', 'Нет столбцов для инвертирования')
                return df
            
            for col in existing_columns:
                # Проверяем тип данных столбца
                if pd.api.types.is_numeric_dtype(df[col]):
                    df[col] = df[col] * -1
            
            duration_ms = (time.time() - start_time) * 1000
            log_event('INFO', 'invert_values_for_returns', 'Значения инвертированы', 
                     {'total_rows': len(df), 'inverted_columns': inverted_columns_count,
                      'inverted_columns_list': existing_columns, 'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'invert_values_for_returns', 'Ошибка при инвертировании значений', 
                     {'error_details': str(e), 'duration_ms': duration_ms})
            return df
    
    def invert_values_for_return_docs(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Умножает указанные столбцы на -1 для строк с doc_type_name = "Возврат"
        (повторное умножение на -1, что приведет к возврату исходных значений)
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'invert_values_for_return_docs', 'DataFrame пустой, пропускаем инвертирование для возвратов')
                return df
            
            # Проверяем наличие столбца doc_type_name
            if 'doc_type_name' not in df.columns:
                log_event('WARNING', 'invert_values_for_return_docs', 'Отсутствует столбец doc_type_name')
                return df
            
            # Столбцы для умножение на -1 для возвратов (повторное умножение)
            columns_to_invert_for_returns = [
                'retail_price',
                'retail_amount',
                'ppvz_for_pay',
                'cost_price',
                'additional_expenses',
                'commission_amount',
                'commission_normal',
                'penalty_commission_rub',
                'acquiring_fee',
                'cashback_amount',
                'cashback_commission_change',
                'ppvz_reward'
            ]
            
            # Проверяем наличие столбцов в DataFrame
            existing_columns = [col for col in columns_to_invert_for_returns if col in df.columns]
            inverted_columns_count = len(existing_columns)
            
            if not existing_columns:
                log_event('INFO', 'invert_values_for_return_docs', 'Нет столбцов для инвертирования для возвратов')
                return df
            
            # Находим строки с возвратами
            return_mask = df['doc_type_name'] == 'Возврат'
            return_rows_count = return_mask.sum()
            
            if return_rows_count == 0:
                log_event('INFO', 'invert_values_for_return_docs', 'Нет строк с возвратами для инвертирования')
                return df
            
            for col in existing_columns:
                # Умножаем на -1 только для строк с возвратами
                if pd.api.types.is_numeric_dtype(df[col]):
                    df.loc[return_mask, col] = df.loc[return_mask, col] * -1
            
            duration_ms = (time.time() - start_time) * 1000
            log_event('INFO', 'invert_values_for_return_docs', 'Значения для возвратов инвертированы', 
                     {'total_rows': len(df), 'return_rows': return_rows_count,
                      'inverted_columns': inverted_columns_count, 'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'invert_values_for_return_docs', 'Ошибка при инвертировании значений для возвратов', 
                     {'error_details': str(e), 'duration_ms': duration_ms})
            return df
    
    def remove_timezones_from_dates(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Удаляет временные зоны из всех datetime столбцов в DataFrame
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'remove_timezones_from_dates', 'DataFrame пустой, пропускаем удаление временных зон')
                return df
            
            # Создаем копию DataFrame для безопасной модификации
            df = df.copy()
            
            # Список возможных datetime столбцов
            datetime_columns = []
            
            # Проверяем каждый столбец на наличие типа datetime с временной зоной
            for col in df.columns:
                if pd.api.types.is_datetime64_any_dtype(df[col]):
                    # Проверяем, есть ли временная зона
                    if hasattr(df[col].dtype, 'tz') and df[col].dtype.tz is not None:
                        datetime_columns.append(col)
            
            columns_processed = len(datetime_columns)
            
            # Удаляем временные зоны
            for col in datetime_columns:
                try:
                    df[col] = df[col].dt.tz_localize(None)
                except Exception as e:
                    # Если не удалось удалить временную зону, преобразуем в строку
                    df[col] = df[col].astype(str)
                    log_event('WARNING', 'remove_timezones_from_dates', 'Столбец преобразован в строку из-за ошибки', 
                             {'column': col, 'error': str(e)})
            
            duration_ms = (time.time() - start_time) * 1000
            log_event('INFO', 'remove_timezones_from_dates', 'Временные зоны удалены', 
                     {'total_columns': len(df.columns), 'datetime_columns_processed': columns_processed,
                      'datetime_columns_list': datetime_columns, 'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'remove_timezones_from_dates', 'Ошибка при удалении временных зон', 
                     {'error_details': str(e), 'duration_ms': duration_ms})
            return df
    
    def enrich_empty_values_from_db(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Обогащает пустые значения в столбцах sa_name и nm_id путем поиска
        по ключу srid во всей таблице ReportDetail в базе данных.
        
        Использует самый быстрый способ с помощью словарей.
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'enrich_empty_values_from_db', 'DataFrame пустой, пропускаем обогащение из БД')
                return df
            
            # Проверяем наличие необходимых столбцов
            required_columns = ['srid', 'sa_name', 'nm_id']
            missing_columns = [col for col in required_columns if col not in df.columns]
            
            if missing_columns:
                log_event('WARNING', 'enrich_empty_values_from_db', 'Отсутствуют необходимые столбцы', 
                         {'missing_columns': missing_columns})
                return df
            
            # Получаем все уникальные srid из DataFrame
            unique_srids = df['srid'].dropna().unique()
            unique_srids_count = len(unique_srids)
            
            if unique_srids_count == 0:
                log_event('INFO', 'enrich_empty_values_from_db', 'Нет уникальных srid для обогащения')
                return df
            
            # Создаем словарь для быстрого поиска srid -> (sa_name, nm_id)
            srid_to_data = {}
            db_queries = 0
            db_records_found = 0
            
            log_event('INFO', 'enrich_empty_values_from_db', 'Начало обогащения из БД', 
                     {'unique_srids_count': unique_srids_count})
            
            try:
                # Используем один запрос для получения всех данных за раз
                # Используем batch запрос для избежания проблемы с большим количеством параметров
                batch_size = 1000
                for i in range(0, len(unique_srids), batch_size):
                    batch = unique_srids[i:i + batch_size]
                    db_queries += 1
                    
                    # Запрос к базе данных для получения sa_name и nm_id по srid
                    results = db.session.query(
                        ReportDetail.srid,
                        ReportDetail.sa_name,
                        ReportDetail.nm_id
                    ).filter(
                        ReportDetail.srid.in_(batch),
                        ReportDetail.sa_name.isnot(None),
                        ReportDetail.nm_id.isnot(None)
                    ).all()
                    
                    db_records_found += len(results)
                    
                    # Заполняем словарь
                    for result in results:
                        srid_to_data[result.srid] = (result.sa_name, result.nm_id)
            
            except Exception as e:
                log_event('ERROR', 'enrich_empty_values_from_db', 'Ошибка при запросе к базе данных', 
                         {'error_details': str(e), 'db_queries': db_queries})
                return df
            
            # Функция для проверки пустых значений
            def is_empty_sa_name(value):
                if pd.isna(value):
                    return True
                if isinstance(value, (int, float)) and value == 0:
                    return True
                if isinstance(value, str) and value.strip() == '':
                    return True
                if value is None:
                    return True
                return False
            
            def is_empty_nm_id(value):
                if pd.isna(value):
                    return True
                if isinstance(value, (int, float)) and value == 0:
                    return True
                if isinstance(value, str):
                    if value.strip() == '':
                        return True
                    if value.strip() == '0':
                        return True
                if value is None:
                    return True
                return False
            
            # Статистика до обогащения
            empty_sa_name_before = df['sa_name'].apply(is_empty_sa_name).sum()
            empty_nm_id_before = df['nm_id'].apply(is_empty_nm_id).sum()
            
            # Применяем обогащение
            enriched_sa_name = 0
            enriched_nm_id = 0
            
            for idx, row in df.iterrows():
                srid = row['srid']
                
                if srid in srid_to_data:
                    sa_name, nm_id = srid_to_data[srid]
                    
                    # Обогащаем sa_name, если он пустой
                    if is_empty_sa_name(row['sa_name']) and not is_empty_sa_name(sa_name):
                        df.at[idx, 'sa_name'] = sa_name
                        enriched_sa_name += 1
                    
                    # Обогащаем nm_id, если он пустой
                    if is_empty_nm_id(row['nm_id']) and not is_empty_nm_id(nm_id):
                        df.at[idx, 'nm_id'] = nm_id
                        enriched_nm_id += 1
            
            duration_ms = (time.time() - start_time) * 1000
            log_event('INFO', 'enrich_empty_values_from_db', 'Обогащение из БД завершено', 
                     {'total_rows': len(df), 'unique_srids': unique_srids_count,
                      'db_queries': db_queries, 'db_records_found': db_records_found,
                      'empty_sa_name_before': empty_sa_name_before, 'empty_nm_id_before': empty_nm_id_before,
                      'enriched_sa_name': enriched_sa_name, 'enriched_nm_id': enriched_nm_id,
                      'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'enrich_empty_values_from_db', 'Ошибка при обогащении из БД', 
                     {'error_details': str(e), 'duration_ms': duration_ms})
            return df
    
    def reorder_columns(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Переупорядочивает столбцы в соответствии с желаемым порядком
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'reorder_columns', 'DataFrame пустой, пропускаем переупорядочивание столбцов')
                return df
            
            initial_columns = list(df.columns)
            initial_count = len(initial_columns)
            
            # Создаем список для окончательного порядка столбцов
            final_order = []
            
            # Добавляем столбцы из желаемого порядка, которые есть в DataFrame
            for col in self.desired_column_order:
                if col in df.columns:
                    final_order.append(col)
            
            # Добавляем остальные столбцы, которые есть в DataFrame, но нет в желаемом порядке
            additional_columns = []
            for col in df.columns:
                if col not in final_order:
                    final_order.append(col)
                    additional_columns.append(col)
            
            # Переупорядочиваем DataFrame
            df = df[final_order]
            
            final_count = len(final_order)
            additional_count = len(additional_columns)
            matched_count = final_count - additional_count
            
            duration_ms = (time.time() - start_time) * 1000
            log_event('INFO', 'reorder_columns', 'Столбцы переупорядочены', 
                     {'initial_columns': initial_count, 'final_columns': final_count,
                      'matched_columns': matched_count, 'additional_columns': additional_count,
                      'additional_columns_list': additional_columns, 'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'reorder_columns', 'Ошибка при переупорядочивании столбцов', 
                     {'error_details': str(e), 'duration_ms': duration_ms})
            return df

    def convert_zeros_to_null(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Преобразует все нулевые значения (0) в NULL (None) для всех столбцов DataFrame
        """
        start_time = time.time()
        try:
            if df.empty:
                log_event('INFO', 'convert_zeros_to_null', 'DataFrame пустой, пропускаем преобразование 0 в NULL')
                return df
            
            # ПРОСТОЕ РЕШЕНИЕ: Используем replace для всех столбцов
            df = df.replace({0: None, 0.0: None, '0': None})
            
            duration_ms = (time.time() - start_time) * 1000
            log_event('INFO', 'convert_zeros_to_null', 'Преобразование 0 в NULL завершено',
                    {'total_columns': len(df.columns), 'duration_ms': duration_ms})
            
            return df
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'convert_zeros_to_null', 'Ошибка при преобразовании 0 в NULL',
                    {'error_details': str(e), 'duration_ms': duration_ms})
            return df

    def process_dataframe(self, df: pd.DataFrame, report_date: str) -> pd.DataFrame:
        """
        Обработка DataFrame (фильтрация, добавление столбцов и т.д.)
        """
        start_time = time.time()
        log_event('INFO', 'process_dataframe', 'Начало обработки DataFrame', 
                 {'report_date': report_date, 'initial_rows': len(df), 'initial_columns': len(df.columns)})
        
        try:
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пустой, пропускаем обработку')
                return df
            
            # Применяем фильтрация по столбцу quantity
            log_event('INFO', 'process_dataframe', 'Шаг 1/15: Фильтрация по quantity')
            df = self.filter_by_quantity(df)
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пуст после фильтрации по quantity')
                return df
            
            # Удаляем ненужные столбцы
            log_event('INFO', 'process_dataframe', 'Шаг 2/15: Удаление неиспользуемых столбцов')
            df = self.remove_unused_columns(df)
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пуст после удаления столбцов')
                return df
            
            # Обрабатываем возвраты
            log_event('INFO', 'process_dataframe', 'Шаг 3/15: Обработка возвратов')
            df = self.process_returns(df)
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пуст после обработки возвратов')
                return df
            
            # Рассчитываем commission_amount
            log_event('INFO', 'process_dataframe', 'Шаг 4/15: Расчет commission_amount')
            df = self.calculate_commission_amount(df)
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пуст после расчета commission_amount')
                return df
            
            # Добавляем столбец времени доставки
            log_event('INFO', 'process_dataframe', 'Шаг 5/15: Добавление времени доставки')
            df = self.add_delivery_time_column(df)
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пуст после добавления времени доставки')
                return df
            
            # Заполняем пустые значения bonus_type_name
            log_event('INFO', 'process_dataframe', 'Шаг 5.1/15: Заполнение bonus_type_name')
            df = self.fill_bonus_type_name(df)
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пуст после заполнения bonus_type_name')
                return df

            # Добавляем столбец type_fb
            log_event('INFO', 'process_dataframe', 'Шаг 6/15: Добавление type_fb')
            df = self.add_type_fb_column(df)
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пуст после добавления type_fb')
                return df
            
            # Добавляем столбец base_comission
            log_event('INFO', 'process_dataframe', 'Шаг 7/15: Добавление базовой комиссии')
            df = self.add_base_commission_column(df)
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пуст после добавления базовой комиссии')
                return df
            
            # Добавляем столбец commission_normal
            log_event('INFO', 'process_dataframe', 'Шаг 8/15: Добавление commission_normal')
            df = self.add_commission_normal_column(df)
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пуст после добавления commission_normal')
                return df
            
            # Добавляем столбцы штрафной комиссии
            log_event('INFO', 'process_dataframe', 'Шаг 9/15: Добавление штрафных комиссий')
            df = self.add_penalty_commission_columns(df)
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пуст после добавления штрафных комиссий')
                return df
            
            # Добавляем столбцы себестоимости и дополнительных расходов
            log_event('INFO', 'process_dataframe', 'Шаг 10/15: Добавление себестоимости')
            df = self.add_cost_columns(df)
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пуст после добавления себестоимости')
                return df
            
            # Умножаем указанные столбцы на -1
            log_event('INFO', 'process_dataframe', 'Шаг 11/15: Инвертирование значений')
            df = self.invert_values_for_returns(df)
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пуст после инвертирования значений')
                return df
            
            # ПОВТОРНОЕ УМНОЖЕНИЕ НА -1 для возвратов
            log_event('INFO', 'process_dataframe', 'Шаг 12/15: Инвертирование значений для возвратов')
            df = self.invert_values_for_return_docs(df)
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пуст после инвертирования значений для возвратов')
                return df
            
            log_event('INFO', 'process_dataframe', 'Шаг 13/16: Добавление столбцов возвратов')
            df = self.add_recovery_columns(df)
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пуст после добавления столбцов возвратов')
                return df
            
            log_event('INFO', 'process_dataframe', 'Шаг 13/16: Расчет стоимости обратной логистики')
            df = self.calculate_return_delivery_rub(df)
            if df.empty:
                log_event('INFO', 'process_dataframe', 'DataFrame пуст после расчета return_delivery_rub')
                return df
            
            # Удаляем временные зоны из дат
            log_event('INFO', 'process_dataframe', 'Шаг 14/17: Удаление временных зон')
            df = self.remove_timezones_from_dates(df)
            
            # Обогащаем пустые значения sa_name и nm_id из базы данных
            log_event('INFO', 'process_dataframe', 'Шаг 15/17: Обогащение из БД')
            df = self.enrich_empty_values_from_db(df)
            
            # Преобразуем все 0 в NULL
            log_event('INFO', 'process_dataframe', 'Шаг 16/17: Преобразование 0 в NULL')
            df = self.convert_zeros_to_null(df)

            # Переупорядочиваем столбцы
            log_event('INFO', 'process_dataframe', 'Шаг 15/17: Переупорядочивание столбцов')
            df = self.reorder_columns(df)
            
            # Добавляем столбец с датой отчета
            df['report_date'] = report_date
            
            total_duration = (time.time() - start_time) * 1000
            log_event('INFO', 'process_dataframe', 'Обработка DataFrame завершена', 
                     {'report_date': report_date, 'final_rows': len(df), 'final_columns': len(df.columns),
                      'total_duration_ms': total_duration})
            
            return df
        except Exception as e:
            total_duration = (time.time() - start_time) * 1000
            log_event('ERROR', 'process_dataframe', 'Ошибка при обработке DataFrame', 
                     {'report_date': report_date, 'error_details': str(e), 
                      'traceback': traceback.format_exc(), 'total_duration_ms': total_duration})
            return pd.DataFrame()


    def save_to_database(self, df: pd.DataFrame, report_date: str, batch_size: int = 1000):
        """
        Сохранение данных в базу данных со СТРОГОЙ проверкой по rrd_id
        """
        start_time = time.time()
        log_event('INFO', 'save_to_database', 'Начало сохранения в базу данных', 
                {'report_date': report_date, 'records_to_save': len(df), 'batch_size': batch_size})
        
        try:
            if df.empty:
                log_event('INFO', 'save_to_database', 'Нет данных для сохранения')
                return 0
            
            # Получаем список допустимых полей модели ReportDetail
            from sqlalchemy.inspection import inspect
            model_columns = [column.name for column in inspect(ReportDetail).columns]
            # Преобразуем в set для быстрой проверки
            valid_fields = set(model_columns)
            log_event('DEBUG', 'save_to_database', 'Допустимые поля модели ReportDetail', 
                    {'valid_fields_count': len(valid_fields)})
            
            # ПРЕОБРАЗУЕМ rrd_id В СТРОКИ ДО ВСЕХ ОПЕРАЦИЙ
            if 'rrd_id' in df.columns:
                # Преобразуем все значения rrd_id в строки, заменяя NaN на None
                df['rrd_id'] = df['rrd_id'].apply(
                    lambda x: str(int(x)) if pd.notna(x) and str(x).isdigit() else 
                            str(x) if pd.notna(x) else None
                )
            
            # Преобразуем DataFrame в список словарей
            data_list = df.replace({np.nan: None}).to_dict('records')
            total_records = len(data_list)
            
            saved_count = 0
            updated_count = 0
            error_count = 0
            
            try:
                # Получаем все существующие rrd_id за эту дату для быстрой проверки
                existing_rrd_ids = set()
                try:
                    # Запрашиваем только rrd_id для указанной даты
                    existing_records = db.session.query(ReportDetail.rrd_id).filter(
                        ReportDetail.report_date == report_date,
                        ReportDetail.rrd_id.isnot(None)
                    ).all()
                    # Преобразуем в строки для сравнения
                    existing_rrd_ids = {str(record[0]) if record[0] is not None else None 
                                    for record in existing_records if record[0] is not None}
                    log_event('INFO', 'save_to_database', 'Получены существующие rrd_id', 
                            {'report_date': report_date, 'existing_count': len(existing_rrd_ids)})
                except Exception as e:
                    log_event('WARNING', 'save_to_database', 'Ошибка получения существующих rrd_id', 
                            {'error': str(e), 'report_date': report_date})
                
                # Сохраняем пачками
                for i in range(0, len(data_list), batch_size):
                    batch_start = i
                    batch_end = min(i + batch_size, len(data_list))
                    batch = data_list[batch_start:batch_end]
                    
                    batch_saved = 0
                    batch_updated = 0
                    batch_errors = 0
                    
                    for record in batch:
                        try:
                            # --- НОВЫЙ БЛОК: фильтрация неизвестных полей ---
                            # Удаляем из record все ключи, которых нет в модели
                            invalid_keys = set(record.keys()) - valid_fields
                            if invalid_keys:
                                # Проверяем, все ли неизвестные ключи - игнорируемые
                                if not invalid_keys.issubset(self.IGNORED_EXTRA_FIELDS):
                                    log_event('DEBUG', 'save_to_database', 
                                            'Удалены неизвестные поля из записи', 
                                            {'rrd_id': record.get('rrd_id'), 
                                            'invalid_keys': list(invalid_keys)})
                                # Удаляем их (всегда)
                                for key in invalid_keys:
                                    del record[key]
                            # --------------------------------------------------
                            
                            rrd_id = record.get('rrd_id')
                            
                            # ПРЕОБРАЗУЕМ rrd_id В СТРОКУ ДЛЯ СРАВНЕНИЯ
                            if rrd_id is not None:
                                rrd_id = str(rrd_id)
                                record['rrd_id'] = rrd_id  # Обновляем запись
                            
                            if not rrd_id:
                                # Если нет rrd_id, пропускаем запись (или используем альтернативный ключ)
                                log_event('WARNING', 'save_to_database', 'Запись без rrd_id пропущена', 
                                        {'srid': record.get('srid')})
                                continue
                            
                            # ПРОВЕРКА 1: Быстрая проверка по множеству rrd_id
                            if rrd_id in existing_rrd_ids:
                                # Обновляем существующую запись
                                existing = ReportDetail.query.filter(
                                    db.cast(ReportDetail.rrd_id, db.String) == rrd_id
                                ).first()
                                
                                if existing:
                                    for key, value in record.items():
                                        if hasattr(existing, key) and value is not None:
                                            setattr(existing, key, value)
                                    existing.updated_at = datetime.utcnow()
                                    existing.report_date = report_date
                                    updated_count += 1
                                    batch_updated += 1
                                else:
                                    # Удаляем из множества, так как записи нет в БД
                                    existing_rrd_ids.remove(rrd_id)
                                    # Создаем новую запись
                                    record['report_date'] = report_date
                                    new_record = ReportDetail(**record)
                                    db.session.add(new_record)
                                    existing_rrd_ids.add(rrd_id)  # Добавляем обратно
                                    saved_count += 1
                                    batch_saved += 1
                            else:
                                # ПРОВЕРКА 2: Детальная проверка в БД (на случай рассинхронизации)
                                existing = ReportDetail.query.filter(
                                    db.cast(ReportDetail.rrd_id, db.String) == rrd_id
                                ).first()
                                
                                if existing:
                                    # Запись существует, обновляем
                                    for key, value in record.items():
                                        if hasattr(existing, key) and value is not None:
                                            setattr(existing, key, value)
                                    existing.updated_at = datetime.utcnow()
                                    existing.report_date = report_date
                                    updated_count += 1
                                    batch_updated += 1
                                    existing_rrd_ids.add(rrd_id)  # Добавляем в множество
                                else:
                                    # Создаем новую запись
                                    record['report_date'] = report_date
                                    new_record = ReportDetail(**record)
                                    db.session.add(new_record)
                                    existing_rrd_ids.add(rrd_id)
                                    saved_count += 1
                                    batch_saved += 1
                                        
                        except Exception as e:
                            error_count += 1
                            batch_errors += 1
                            log_event('ERROR', 'save_to_database', 'Ошибка при обработке записи', 
                                    {'rrd_id': record.get('rrd_id'), 'error': str(e)[:200]})
                            continue
                    
                    # Коммитим каждую пачку
                    try:
                        db.session.commit()
                        log_event('DEBUG', 'save_to_database', 'Пачка сохранена', 
                                {'batch': i // batch_size + 1, 'saved': batch_saved, 
                                'updated': batch_updated, 'errors': batch_errors})
                    except Exception as e:
                        db.session.rollback()
                        
                        # При ошибке уникальности rrd_id, пробуем обновить существующие
                        if 'duplicate key value violates unique constraint' in str(e).lower() and 'rrd_id' in str(e).lower():
                            log_event('WARNING', 'save_to_database', 'Обнаружен конфликт rrd_id, пробуем обновить', 
                                    {'batch': i // batch_size + 1})
                            
                            # Пробуем обработать каждую запись отдельно
                            for record in batch:
                                try:
                                    # Снова фильтруем поля
                                    invalid_keys = set(record.keys()) - valid_fields
                                    if invalid_keys:
                                        for key in invalid_keys:
                                            del record[key]
                                    
                                    rrd_id = record.get('rrd_id')
                                    if rrd_id:
                                        # Преобразуем в строку
                                        rrd_id = str(rrd_id) if rrd_id is not None else None
                                        
                                        existing = ReportDetail.query.filter(
                                            db.cast(ReportDetail.rrd_id, db.String) == rrd_id
                                        ).first()
                                        
                                        if existing:
                                            for key, value in record.items():
                                                if hasattr(existing, key) and value is not None:
                                                    setattr(existing, key, value)
                                            existing.updated_at = datetime.utcnow()
                                            existing.report_date = report_date
                                            db.session.add(existing)
                                        else:
                                            record['report_date'] = report_date
                                            # Убедимся, что rrd_id строка
                                            if 'rrd_id' in record and record['rrd_id'] is not None:
                                                record['rrd_id'] = str(record['rrd_id'])
                                            new_record = ReportDetail(**record)
                                            db.session.add(new_record)
                                except Exception as e2:
                                    log_event('ERROR', 'save_to_database', 
                                            'Ошибка при повторной обработке записи', 
                                            {'rrd_id': record.get('rrd_id'), 'error': str(e2)})
                                    pass
                            
                            try:
                                db.session.commit()
                                log_event('INFO', 'save_to_database', 'Пачка сохранена после конфликта', 
                                        {'batch': i // batch_size + 1})
                            except Exception as e2:
                                db.session.rollback()
                                log_event('ERROR', 'save_to_database', 'Ошибка при повторном сохранении пачки', 
                                        {'batch': i // batch_size + 1, 'error': str(e2)})
                        else:
                            log_event('ERROR', 'save_to_database', 'Ошибка коммита пачки', 
                                    {'batch': i // batch_size + 1, 'error': str(e)})
                
                total_duration = (time.time() - start_time) * 1000
                log_event('INFO', 'save_to_database', 'Сохранение завершено', 
                        {'report_date': report_date, 'total_records': total_records,
                        'saved': saved_count, 'updated': updated_count, 'errors': error_count,
                        'duration_ms': total_duration, 'records_processed': saved_count + updated_count})
                
                return saved_count + updated_count
                
            except Exception as e:
                db.session.rollback()
                total_duration = (time.time() - start_time) * 1000
                log_event('ERROR', 'save_to_database', 'Общая ошибка сохранения', 
                        {'report_date': report_date, 'error': str(e), 'duration_ms': total_duration})
                return 0
        
        except Exception as e:
            total_duration = (time.time() - start_time) * 1000
            log_event('ERROR', 'save_to_database', 'Критическая ошибка', 
                    {'report_date': report_date, 'error': str(e), 'duration_ms': total_duration})
            return 0


    def load_reports_for_period(self, date_from: str, date_to: str) -> dict:
        """
        Загрузка отчетов за указанный период с последующей агрегацией всей базы
        """
        start_time = time.time()
        log_event('INFO', 'load_reports_for_period', 'Начало загрузки отчетов за период', 
                 {'date_from': date_from, 'date_to': date_to})
        
        result = {
            'status': 'success',
            'total_dates': 0,
            'processed_dates': 0,
            'total_records': 0,
            'saved_records': 0,
            'errors': [],
            'aggregation': None
        }
        
        try:
            # Генерируем список дат
            start_date = datetime.strptime(date_from, "%Y-%m-%d")
            end_date = datetime.strptime(date_to, "%Y-%m-%d")
            
            current_date = start_date
            while current_date <= end_date:
                date_str = current_date.strftime("%Y-%m-%d")
                result['total_dates'] += 1
                
                date_start_time = time.time()
                log_event('INFO', 'load_reports_for_period', 'Обработка даты', {'date': date_str})
                
                try:
                    # Получаем данные за дату
                    df = self.fetch_data_by_date(date_str)
                    
                    if not df.empty:
                        # Обрабатываем данные
                        processed_df = self.process_dataframe(df, date_str)
                        
                        if not processed_df.empty:
                            # Сохраняем в базу данных
                            saved = self.save_to_database(processed_df, date_str)
                            
                            result['processed_dates'] += 1
                            result['total_records'] += len(processed_df)
                            result['saved_records'] += saved
                            
                            date_duration = (time.time() - date_start_time) * 1000
                            log_event('INFO', 'load_reports_for_period', 'Дата успешно обработана', 
                                     {'date': date_str, 'records': len(processed_df), 
                                      'saved': saved, 'duration_ms': date_duration})
                        else:
                            date_duration = (time.time() - date_start_time) * 1000
                            log_event('INFO', 'load_reports_for_period', 'Нет обработанных данных для даты', 
                                     {'date': date_str, 'duration_ms': date_duration})
                    else:
                        date_duration = (time.time() - date_start_time) * 1000
                        log_event('INFO', 'load_reports_for_period', 'Нет данных для даты', 
                                 {'date': date_str, 'duration_ms': date_duration})
                    
                    # Пауза между запросами
                    time.sleep(2)
                    
                except Exception as e:
                    date_duration = (time.time() - date_start_time) * 1000
                    error_msg = f"Ошибка при обработке даты {date_str}: {str(e)}"
                    result['errors'].append(error_msg)
                    
                    log_event('ERROR', 'load_reports_for_period', 'Ошибка обработки даты', 
                             {'date': date_str, 'error_details': str(e), 
                              'traceback': traceback.format_exc(), 'duration_ms': date_duration})
                
                current_date += timedelta(days=1)
            
            # ЗАКОММЕНТИРОВАН: Шаг 2: Агрегируем ВСЮ базу данных после загрузки
            # if result['saved_records'] > 0:
            #     log_event('INFO', 'load_reports_for_period', 
            #              'Запуск агрегации всей базы данных после загрузки',
            #              {'saved_records': result['saved_records']})
            #     
            #     try:
            #         aggregation_start = time.time()
            #         aggregation_result = self.aggregate_entire_database()
            #         aggregation_duration = (time.time() - aggregation_start) * 1000
            #         
            #         result['aggregation'] = {
            #             'status': aggregation_result.get('status'),
            #             'total_srids': aggregation_result.get('total_srids', 0),
            #             'processed_srids': aggregation_result.get('processed_srids', 0),
            #             'aggregated_records': aggregation_result.get('aggregated_records', 0),
            #             'duration_ms': aggregation_duration
            #         }
            #         
            #         if aggregation_result.get('status') == 'success':
            #             log_event('INFO', 'load_reports_for_period', 'Агрегация базы завершена успешно',
            #                      result['aggregation'])
            #         else:
            #             log_event('WARNING', 'load_reports_for_period', 'Агрегация базы завершилась с ошибками',
            #                      result['aggregation'])
            #             
            #     except Exception as e:
            #         aggregation_duration = (time.time() - aggregation_start) * 1000
            #         result['aggregation'] = {
            #             'status': 'error',
            #             'error': str(e),
            #             'duration_ms': aggregation_duration
            #         }
            #         log_event('ERROR', 'load_reports_for_period', 'Ошибка при агрегации базы данных',
            #                  {'error_details': str(e), 'duration_ms': aggregation_duration})
            # else:
            #     log_event('INFO', 'load_reports_for_period', 
            #              'Нет сохраненных записей, пропускаем агрегацию')


            # === ВСТАВЬТЕ ЗДЕСЬ: Шаг 3 - Создание копии базы для клиента ===
            # ДОБАВЛЕНО: Создание копии всей базы в Parquet файл для клиента
            log_event('INFO', 'load_reports_for_period', 
                     'Создание копии базы данных для клиента в Parquet')
            
            try:
                export_start = time.time()
                export_result = self.create_client_database_copy()
                export_duration = (time.time() - export_start) * 1000
                
                result['client_export'] = {
                    'status': export_result.get('status'),
                    'filename': export_result.get('filename'),
                    'timestamp': export_result.get('timestamp'),
                    'records_exported': export_result.get('records_exported', 0),
                    'file_size_mb': export_result.get('file_size_mb', 0),
                    'symlink_path': export_result.get('symlink_path'),
                    'duration_ms': export_duration
                }
                
                if export_result.get('status') == 'success':
                    log_event('INFO', 'load_reports_for_period', 'Экспорт для клиента успешно завершен',
                             result['client_export'])
                else:
                    log_event('WARNING', 'load_reports_for_period', 'Экспорт для клиента завершился с ошибками',
                             result['client_export'])
                    

            except Exception as e:
                export_duration = (time.time() - export_start) * 1000
                result['client_export'] = {
                    'status': 'error',
                    'error': str(e),
                    'duration_ms': export_duration
                }
                log_event('ERROR', 'load_reports_for_period', 'Ошибка при экспорте для клиента',
                         {'error_details': str(e), 'duration_ms': export_duration})
            # === КОНЕЦ ВСТАВКИ ===
            
            total_duration = (time.time() - start_time) * 1000
            log_event('INFO', 'load_reports_for_period', 'Загрузка отчетов за период завершена', 
                     {'date_from': date_from, 'date_to': date_to,
                      'total_dates': result['total_dates'], 'processed_dates': result['processed_dates'],
                      'total_records': result['total_records'], 'saved_records': result['saved_records'],
                      'error_count': len(result['errors']), 'has_aggregation': result['aggregation'] is not None,
                      'total_duration_ms': total_duration, 'records_processed': result['total_records']})
            
            return result
            
        except Exception as e:
            total_duration = (time.time() - start_time) * 1000
            log_event('ERROR', 'load_reports_for_period', 'Общая ошибка загрузки отчетов', 
                     {'date_from': date_from, 'date_to': date_to,
                      'error_details': str(e), 'total_duration_ms': total_duration})
            
            result['status'] = 'error'
            result['errors'].append(f"Общая ошибка: {str(e)}")
            return result


    def aggregate_entire_database(self):
        """
        Агрегирует ВСЮ базу данных ReportDetail по ключу srid
        с использованием обычной таблицы с уникальным именем
        """
        start_time = time.time()
        # Генерируем уникальное имя таблицы
        import secrets
        random_suffix = secrets.token_hex(8)
        temp_table_name = f"report_details_agg_{int(time.time())}_{random_suffix}"
        
        try:
            log_event('INFO', 'aggregate_entire_database', 
                    'Начало агрегации с временной таблицей',
                    {'temp_table_name': temp_table_name})
            
            # Шаг 1: Создаем ОБЫЧНУЮ таблицу (не TEMPORARY)
            create_table_sql = text(f"""
                CREATE TABLE {temp_table_name} (
                    id SERIAL PRIMARY KEY,
                    srid VARCHAR(50),
                    operation_quantity INTEGER DEFAULT 1,
                    shk_id VARCHAR(50),
                    sticker_id VARCHAR(50),
                    rrd_id VARCHAR(300),
                    assembly_id VARCHAR(50),
                    nm_id INTEGER,
                    sa_name VARCHAR(100),
                    barcode VARCHAR(50),
                    gi_id VARCHAR(50),
                    ppvz_office_id VARCHAR(50),
                    order_uid VARCHAR(100),
                    trbx_id VARCHAR(50),
                    seller_promo_id VARCHAR(50),
                    loyalty_id VARCHAR(50),
                    uuid_promocode VARCHAR(100),
                    subject_name VARCHAR(200),
                    brand_name VARCHAR(200),
                    ts_name VARCHAR(100),
                    doc_type_name VARCHAR(500),
                    supplier_oper_name VARCHAR(500),
                    bonus_type_name VARCHAR(500),
                    payment_processing VARCHAR(500),
                    rr_dt TIMESTAMP,
                    order_dt TIMESTAMP,
                    sale_dt TIMESTAMP,
                    delivery_time_hours INTEGER,
                    type_fb VARCHAR(10),
                    delivery_method VARCHAR(100),
                    gi_box_type_name VARCHAR(100),
                    site_country VARCHAR(100),
                    office_name VARCHAR(200),
                    ppvz_office_name VARCHAR(200),
                    dlv_prc FLOAT,
                    acquiring_percent FLOAT,
                    commission_percent FLOAT,
                    base_comission FLOAT,
                    penalty_commission_percent FLOAT,
                    is_kgvp_v2 FLOAT,
                    loyalty_discount FLOAT,
                    ppvz_kvw_prc FLOAT,
                    ppvz_kvw_prc_base FLOAT,
                    ppvz_spp_prc FLOAT,
                    product_discount_for_report FLOAT,
                    sale_percent FLOAT,
                    sale_price_promocode_discount_prc FLOAT,
                    seller_promo_discount FLOAT,
                    sup_rating_prc_up FLOAT,
                    supplier_promo FLOAT,
                    wibes_wb_discount_percent FLOAT,
                    quantity INTEGER,
                    delivery_amount INTEGER,
                    return_amount INTEGER,
                    retail_price FLOAT,
                    retail_price_recovery FLOAT,
                    retail_amount FLOAT,
                    retail_amount_refunded FLOAT,
                    ppvz_for_pay FLOAT,
                    ppvz_for_recovery FLOAT,
                    cost_price FLOAT,
                    cost_price_recovered FLOAT,
                    additional_expenses FLOAT,
                    additional_expenses_recovered FLOAT,
                    commission_amount FLOAT,
                    commission_amount_reversed FLOAT,
                    commission_normal FLOAT,
                    commission_normal_reversed FLOAT,
                    penalty_commission_rub FLOAT,
                    penalty_commission_reversed FLOAT,
                    delivery_rub FLOAT,
                    return_delivery_rub FLOAT,
                    ppvz_reward FLOAT,
                    ppvz_reward_reversed FLOAT,
                    acquiring_fee FLOAT,
                    acquiring_fee_reversed FLOAT,
                    acceptance FLOAT,
                    cashback_amount FLOAT,
                    cashback_amount_reversed FLOAT,
                    cashback_commission_change FLOAT,
                    cashback_commission_change_reversed FLOAT,
                    storage_fee FLOAT,
                    penalty FLOAT,
                    deduction FLOAT,
                    installment_cofinancing_amount FLOAT,
                    additional_payment FLOAT,
                    payment_schedule FLOAT,
                    report_date DATE,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            # Удаляем таблицу, если она уже существует (для перестраховки)
            try:
                db.session.execute(text(f"DROP TABLE IF EXISTS {temp_table_name}"))
                db.session.commit()
            except:
                pass
            
            # Создаем новую таблицу
            db.session.execute(create_table_sql)
            db.session.commit()
            
            log_event('INFO', 'aggregate_entire_database', 
                    'Временная таблица создана (обычная таблица)')
            
            # Шаг 2: Получаем все уникальные srid из базы
            unique_srids = db.session.query(ReportDetail.srid).filter(
                ReportDetail.srid.isnot(None)
            ).distinct().all()
            
            unique_srids = [srid[0] for srid in unique_srids if srid[0]]
            total_srids = len(unique_srids)
            
            log_event('INFO', 'aggregate_entire_database', 
                    f'Найдено {total_srids} уникальных srid для агрегации')
            
            if total_srids == 0:
                log_event('INFO', 'aggregate_entire_database', 
                        'Нет данных для агрегации')
                # Удаляем таблицу
                db.session.execute(text(f"DROP TABLE IF EXISTS {temp_table_name}"))
                db.session.commit()
                return {'status': 'success', 'message': 'Нет данных для агрегации'}
            
            # Шаг 3: Обрабатываем каждую группу srid и записываем в таблицу
            processed_srids = 0
            aggregated_records = []
            
            for srid in unique_srids:
                try:
                    # Получаем все записи с текущим srid
                    records = ReportDetail.query.filter(
                        ReportDetail.srid == srid
                    ).all()
                    
                    if not records:
                        continue
                    
                    # Создаем словарь для агрегированных данных
                    aggregated = {
                        'srid': srid,
                        'operation_quantity': 0,
                        'report_date': None,
                        'created_at': datetime.utcnow(),
                        'updated_at': datetime.utcnow()
                    }
                    
                    # АГРЕГАЦИЯ ДАННЫХ (сохранен оригинальный алгоритм)
                    first_values = {}
                    concat_values = {}
                    sum_values = {}
                    
                    # Собираем значения для конкатенации
                    for record in records:
                        for field in ['doc_type_name', 'supplier_oper_name', 'bonus_type_name', 'payment_processing']:
                            if field not in concat_values:
                                concat_values[field] = set()
                            value = getattr(record, field, None)
                            if value and str(value).strip():
                                concat_values[field].add(str(value))
                    
                    # Собираем значения для суммирования
                    sum_fields = [
                        'quantity', 'delivery_amount', 'return_amount', 'retail_price',
                        'retail_price_recovery', 'retail_amount', 'retail_amount_refunded',
                        'ppvz_for_pay', 'ppvz_for_recovery', 'cost_price', 'cost_price_recovered',
                        'additional_expenses', 'additional_expenses_recovered', 'commission_amount',
                        'commission_amount_reversed', 'commission_normal', 'commission_normal_reversed',
                        'penalty_commission_rub', 'penalty_commission_reversed', 'delivery_rub',
                        'return_delivery_rub', 'ppvz_reward', 'ppvz_reward_reversed', 'acquiring_fee',
                        'acquiring_fee_reversed', 'acceptance', 'cashback_amount', 'cashback_amount_reversed',
                        'cashback_commission_change', 'cashback_commission_change_reversed', 'storage_fee',
                        'penalty', 'deduction', 'installment_cofinancing_amount', 'additional_payment',
                        'payment_schedule', 'operation_quantity'
                    ]
                    
                    for record in records:
                        for field in sum_fields:
                            if field not in sum_values:
                                sum_values[field] = 0
                            value = getattr(record, field, 0)
                            if value:
                                try:
                                    sum_values[field] += float(value)
                                except (ValueError, TypeError):
                                    pass
                        
                        # Собираем значения для первого непустого
                        first_fields = [
                            'shk_id', 'sticker_id', 'assembly_id', 'nm_id', 'sa_name',
                            'barcode', 'gi_id', 'ppvz_office_id', 'order_uid', 'trbx_id',
                            'seller_promo_id', 'loyalty_id', 'uuid_promocode', 'subject_name',
                            'brand_name', 'ts_name', 'rr_dt', 'order_dt', 'delivery_time_hours',
                            'type_fb', 'delivery_method', 'gi_box_type_name', 'site_country',
                            'office_name', 'ppvz_office_name', 'dlv_prc', 'acquiring_percent',
                            'commission_percent', 'base_comission', 'penalty_commission_percent',
                            'is_kgvp_v2', 'loyalty_discount', 'ppvz_kvw_prc', 'ppvz_kvw_prc_base',
                            'ppvz_spp_prc', 'product_discount_for_report', 'sale_percent',
                            'sale_price_promocode_discount_prc', 'seller_promo_discount',
                            'sup_rating_prc_up', 'supplier_promo', 'wibes_wb_discount_percent'
                        ]
                        
                        for field in first_fields:
                            if field not in first_values:
                                value = getattr(record, field, None)
                                if value is not None and str(value).strip():
                                    first_values[field] = value
                    
                    # Особые правила для некоторых полей
                    rrd_ids = set()
                    for record in records:
                        rrd_id = getattr(record, 'rrd_id', None)
                        if rrd_id and str(rrd_id).strip():
                            rrd_ids.add(str(rrd_id))
                    if rrd_ids:
                        aggregated['rrd_id'] = ','.join(rrd_ids)
                    
                    sale_dts = []
                    for record in records:
                        sale_dt = getattr(record, 'sale_dt', None)
                        if sale_dt:
                            sale_dts.append(sale_dt)
                    if sale_dts:
                        aggregated['sale_dt'] = min(sale_dts)
                    
                    report_dates = []
                    for record in records:
                        report_date = getattr(record, 'report_date', None)
                        if report_date:
                            report_dates.append(report_date)
                    if report_dates:
                        aggregated['report_date'] = min(report_dates)
                    
                    # Применяем агрегированные значения
                    for field, value in first_values.items():
                        aggregated[field] = value
                    
                    for field, values_set in concat_values.items():
                        if values_set:
                            aggregated[field] = ','.join(sorted(values_set))
                    
                    for field, sum_value in sum_values.items():
                        aggregated[field] = sum_value if sum_value != 0 else None
                    
                    # Добавляем во временный буфер
                    aggregated_records.append(aggregated)
                    processed_srids += 1
                    
                    # Записываем пачками по 100 записей в таблицу
                    if len(aggregated_records) >= 100:
                        self._insert_batch_to_temp_table(aggregated_records, temp_table_name)
                        aggregated_records = []
                    
                    # Логируем прогресс каждые 100 srid
                    if processed_srids % 100 == 0:
                        log_event('INFO', 'aggregate_entire_database', 
                                f'Обработано {processed_srids}/{total_srids} srid')
                        
                except Exception as e:
                    log_event('ERROR', 'aggregate_entire_database', 
                            f'Ошибка при обработке srid {srid}', 
                            {'srid': srid, 'error': str(e)})
                    continue
            
            # Записываем оставшиеся записи
            if aggregated_records:
                self._insert_batch_to_temp_table(aggregated_records, temp_table_name)
            
            log_event('INFO', 'aggregate_entire_database',
                    'Завершение сбора агрегированных данных',
                    {'total_srids': total_srids,
                    'processed_srids': processed_srids})
            
            # Шаг 4: Удаляем все старые записи из основной таблицы
            log_event('INFO', 'aggregate_entire_database',
                    'Начало удаления старых записей')
            
            deleted = db.session.query(ReportDetail).delete(synchronize_session=False)
            db.session.commit()
            
            log_event('INFO', 'aggregate_entire_database',
                    f'Удалено {deleted} старых записей')
            
            # Шаг 5: Копируем данные из временной таблицы в основную
            log_event('INFO', 'aggregate_entire_database',
                    'Копирование данных из временной таблицы в основную')
            
            copy_sql = text(f"""
                INSERT INTO report_details 
                SELECT * FROM {temp_table_name}
            """)
            db.session.execute(copy_sql)
            db.session.commit()
            
            # Шаг 6: Удаляем временную таблицу
            try:
                db.session.execute(text(f"DROP TABLE IF EXISTS {temp_table_name}"))
                db.session.commit()
                log_event('INFO', 'aggregate_entire_database',
                        'Временная таблица удалена')
            except Exception as e:
                log_event('WARNING', 'aggregate_entire_database',
                        'Не удалось удалить временную таблицу',
                        {'table_name': temp_table_name, 'error': str(e)})
            
            duration_ms = (time.time() - start_time) * 1000
            
            result = {
                'status': 'success',
                'total_srids': total_srids,
                'processed_srids': processed_srids,
                'aggregated_records': processed_srids,
                'duration_ms': duration_ms
            }
            
            log_event('INFO', 'aggregate_entire_database',
                    'Агрегация завершена', result)
            
            return result
            
        except Exception as e:
            db.session.rollback()
            # Пытаемся удалить таблицу в случае ошибки
            try:
                db.session.execute(text(f"DROP TABLE IF EXISTS {temp_table_name}"))
                db.session.commit()
            except:
                pass
            
            duration_ms = (time.time() - start_time) * 1000
            log_event('ERROR', 'aggregate_entire_database',
                    'Критическая ошибка при агрегации',
                    {'error': str(e), 'traceback': traceback.format_exc(), 
                    'duration_ms': duration_ms})
            
            return {
                'status': 'error',
                'error': str(e),
                'duration_ms': duration_ms
            }



    def _safe_drop_temp_table(self, temp_table_name):
        """
        Безопасно удаляет временную таблицу
        """
        try:
            drop_sql = text(f"DROP TABLE IF EXISTS {temp_table_name}")
            db.session.execute(drop_sql)
            db.session.commit()
            log_event('INFO', '_safe_drop_temp_table', 'Временная таблица удалена',
                    {'table_name': temp_table_name})
        except Exception as e:
            log_event('WARNING', '_safe_drop_temp_table', 'Не удалось удалить временную таблицу',
                    {'table_name': temp_table_name, 'error': str(e)})

    def _insert_batch_to_temp_table(self, batch_records, temp_table_name):
        """
        Вставляет пачку записей во временную таблицу
        """
        try:
            if not batch_records:
                return
            
            # Создаем SQL запрос для вставки
            columns = [
                'srid', 'operation_quantity', 'shk_id', 'sticker_id', 'rrd_id', 
                'assembly_id', 'nm_id', 'sa_name', 'barcode', 'gi_id', 
                'ppvz_office_id', 'order_uid', 'trbx_id', 'seller_promo_id', 
                'loyalty_id', 'uuid_promocode', 'subject_name', 'brand_name', 
                'ts_name', 'doc_type_name', 'supplier_oper_name', 'bonus_type_name', 
                'payment_processing', 'rr_dt', 'order_dt', 'sale_dt', 
                'delivery_time_hours', 'type_fb', 'delivery_method', 
                'gi_box_type_name', 'site_country', 'office_name', 
                'ppvz_office_name', 'dlv_prc', 'acquiring_percent', 
                'commission_percent', 'base_comission', 'penalty_commission_percent', 
                'is_kgvp_v2', 'loyalty_discount', 'ppvz_kvw_prc', 
                'ppvz_kvw_prc_base', 'ppvz_spp_prc', 'product_discount_for_report', 
                'sale_percent', 'sale_price_promocode_discount_prc', 
                'seller_promo_discount', 'sup_rating_prc_up', 'supplier_promo', 
                'wibes_wb_discount_percent', 'quantity', 'delivery_amount', 
                'return_amount', 'retail_price', 'retail_price_recovery', 
                'retail_amount', 'retail_amount_refunded', 'ppvz_for_pay', 
                'ppvz_for_recovery', 'cost_price', 'cost_price_recovered', 
                'additional_expenses', 'additional_expenses_recovered', 
                'commission_amount', 'commission_amount_reversed', 
                'commission_normal', 'commission_normal_reversed', 
                'penalty_commission_rub', 'penalty_commission_reversed', 
                'delivery_rub', 'return_delivery_rub', 'ppvz_reward', 
                'ppvz_reward_reversed', 'acquiring_fee', 'acquiring_fee_reversed', 
                'acceptance', 'cashback_amount', 'cashback_amount_reversed', 
                'cashback_commission_change', 'cashback_commission_change_reversed', 
                'storage_fee', 'penalty', 'deduction', 
                'installment_cofinancing_amount', 'additional_payment', 
                'payment_schedule', 'report_date', 'created_at', 'updated_at'
            ]
            
            values_list = []
            for record in batch_records:
                values = []
                for col in columns:
                    value = record.get(col)
                    if value is None:
                        values.append('NULL')
                    elif isinstance(value, (int, float)):
                        values.append(str(value))
                    elif isinstance(value, datetime):
                        values.append(f"'{value.isoformat()}'")
                    elif isinstance(value, date):
                        values.append(f"'{value.isoformat()}'")
                    else:
                        # Экранируем кавычки для строк
                        escaped = str(value).replace("'", "''")
                        values.append(f"'{escaped}'")
                values_list.append(f"({', '.join(values)})")
            
            if values_list:
                sql = f"""
                    INSERT INTO {temp_table_name} 
                    ({', '.join(columns)})
                    VALUES {', '.join(values_list)}
                """
                db.session.execute(text(sql))
                db.session.commit()
                
                log_event('DEBUG', '_insert_batch_to_temp_table', 
                        f'Вставлено {len(batch_records)} записей во временную таблицу')
                
        except Exception as e:
            db.session.rollback()
            log_event('ERROR', '_insert_batch_to_temp_table', 
                    'Ошибка при вставке во временную таблицу',
                    {'error': str(e), 'batch_size': len(batch_records)})
            raise


    def create_client_database_copy(self, output_dir: str = "/home/flaskapp/app/uploads/db") -> dict:
        """
        Создает Parquet файл со всей таблицей ReportDetail для передачи клиенту.
        Каждый раз создается новый файл с timestamp.
        Использует типы данных из модели SQLAlchemy для создания стабильной схемы.
        """
        start_time = time.time()
        log_event('INFO', 'create_client_database_copy', 'Начало создания копии базы для клиента',
                {'output_dir': output_dir})
        
        try:
            # Создаем директорию, если её нет
            Path(output_dir).mkdir(parents=True, exist_ok=True)
            
            # Генерируем уникальное имя файла с timestamp
            timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
            filename = f"db_to_client_{timestamp}.parquet"
            filepath = Path(output_dir) / filename
            
            # Шаг 1: Получаем ВСЕ данные из таблицы ReportDetail
            log_event('INFO', 'create_client_database_copy', 'Начало загрузки данных из базы')
            
            # Используем прямой SQL запрос для максимальной скорости
            query = text("SELECT COUNT(*) FROM report_details")
            total_count = db.session.execute(query).scalar() or 0
            
            log_event('INFO', 'create_client_database_copy', 
                    f'Всего записей в базе: {total_count:,}',
                    {'total_records': total_count})
            
            if total_count == 0:
                log_event('WARNING', 'create_client_database_copy', 'База данных пуста')
                return {
                    'status': 'success',
                    'message': 'База данных пуста',
                    'filepath': None,
                    'records_exported': 0,
                    'file_size_mb': 0
                }
            
            # Шаг 2: Создаем схему PyArrow на основе модели SQLAlchemy
            log_event('INFO', 'create_client_database_copy', 
                    'Создание схемы PyArrow на основе модели SQLAlchemy')
            
            # Создаем схему из модели ReportDetail
            target_schema = self._create_pyarrow_schema_from_model(ReportDetail)
            schema_columns = target_schema.names
            
            log_event('INFO', 'create_client_database_copy', 
                    'Схема PyArrow создана',
                    {'total_columns': len(schema_columns), 
                    'columns': schema_columns[:10]})  # Логируем только первые 10 столбцов
            
            # Шаг 3: Используем пагинацию по возрастающему ID
            batch_size = 100000
            total_records_exported = 0
            writer = None
            
            log_event('INFO', 'create_client_database_copy', 
                    'Начало экспорта данных пачками в Parquet',
                    {'batch_size': batch_size, 'total_count': total_count})
            
            # Получаем минимальный и максимальный ID для пагинации
            id_query = text("SELECT MIN(id) as min_id, MAX(id) as max_id FROM report_details")
            id_result = db.session.execute(id_query).fetchone()
            min_id = id_result.min_id if id_result else 0
            max_id = id_result.max_id if id_result else 0
            
            if min_id is None or max_id is None:
                log_event('INFO', 'create_client_database_copy', 'В таблице нет данных')
                return {
                    'status': 'success',
                    'message': 'База данных пуста',
                    'filepath': None,
                    'records_exported': 0,
                    'file_size_mb': 0
                }
            
            # Итерация по ID для более эффективной пагинации
            current_id = min_id - 1
            iteration = 0
            
            while True:
                try:
                    iteration += 1
                    # Читаем пачку данных по диапазону ID
                    batch_query = text(f"""
                        SELECT * FROM report_details 
                        WHERE id > :current_id AND id <= :max_id
                        ORDER BY id 
                        LIMIT :limit
                    """)
                    
                    result = db.session.execute(
                        batch_query, 
                        {'current_id': current_id, 'max_id': max_id, 'limit': batch_size}
                    )
                    
                    # Преобразуем в DataFrame
                    columns = result.keys()
                    batch_data = [dict(zip(columns, row)) for row in result]
                    
                    if not batch_data:
                        log_event('INFO', 'create_client_database_copy', 'Данные закончились')
                        break
                    
                    batch_records = len(batch_data)
                    total_records_exported += batch_records
                    current_id = batch_data[-1]['id']  # Обновляем текущий ID
                    
                    # Преобразуем в pandas DataFrame
                    df_batch = pd.DataFrame(batch_data)
                    
                    # Убедимся, что все столбцы из схемы присутствуют в DataFrame
                    # Если каких-то столбцов нет, добавляем их с значениями None
                    for col in schema_columns:
                        if col not in df_batch.columns:
                            df_batch[col] = None
                    
                    # Упорядочиваем столбцы в соответствии со схемой
                    df_batch = df_batch[schema_columns]
                    
                    # Преобразуем DataFrame в Arrow Table с явным указанием схемы
                    table = pa.Table.from_pandas(df_batch, schema=target_schema, preserve_index=False)
                    
                    # Если это первая пачка, создаем writer с этой схемой
                    if writer is None:
                        writer = pq.ParquetWriter(
                            filepath, 
                            target_schema, 
                            compression='snappy',
                            use_dictionary=True
                        )
                        log_event('INFO', 'create_client_database_copy', 
                                'Создан Parquet writer со схемой из модели',
                                {'schema_fields': len(target_schema)})
                    
                    # Записываем пачку
                    writer.write_table(table)
                    
                    # Рассчитываем прогресс
                    progress_pct = (current_id - min_id) / (max_id - min_id) * 100 if (max_id - min_id) > 0 else 0
                    
                    # Логируем прогресс каждые 10 пачек или каждые 100000 записей
                    if iteration % 10 == 0 or total_records_exported % 100000 == 0:
                        log_event('INFO', 'create_client_database_copy', 'Прогресс экспорта',
                                {
                                    'iteration': iteration,
                                    'processed': total_records_exported, 
                                    'total': total_count,
                                    'progress': f'{progress_pct:.1f}%',
                                    'current_batch': batch_records,
                                    'current_id': current_id,
                                    'total_exported': total_records_exported
                                })
                    
                    # Если получили меньше записей, чем batch_size, значит это последняя пачка
                    if batch_records < batch_size:
                        log_event('INFO', 'create_client_database_copy', 'Получена последняя пачка',
                                {'batch_size': batch_records, 'expected_batch_size': batch_size})
                        break
                    
                    # Освобождаем память
                    del df_batch
                    del table
                    del batch_data
                    
                except Exception as e:
                    log_event('ERROR', 'create_client_database_copy', 
                            f'Ошибка при обработке пачки данных (iteration={iteration})',
                            {'error_details': str(e), 'traceback': traceback.format_exc()})
                    # Пытаемся закрыть writer и удалить файл
                    if writer:
                        writer.close()
                    if filepath.exists():
                        filepath.unlink()
                    raise
            
            # Закрываем writer
            if writer:
                writer.close()
                log_event('INFO', 'create_client_database_copy', 
                        'Parquet writer закрыт', {'filepath': str(filepath)})
            
            # Проверяем, что экспортировали все записи
            if total_records_exported != total_count:
                log_event('WARNING', 'create_client_database_copy', 
                        'Количество экспортированных записей не совпадает с общим количеством',
                        {'exported': total_records_exported, 'total': total_count})
            
            # Шаг 4: Создаем симлинк на последний файл для удобства
            latest_link = Path(output_dir) / "db_to_client_latest.parquet"
            try:
                # Удаляем старый симлинк, если существует
                if latest_link.exists():
                    latest_link.unlink()
                # Создаем новый симлинк
                latest_link.symlink_to(filepath)
                log_event('INFO', 'create_client_database_copy', 'Создан симлинк на последний файл',
                        {'symlink': str(latest_link), 'target': str(filepath)})
            except Exception as e:
                log_event('WARNING', 'create_client_database_copy', 
                        'Не удалось создать симлинк', {'error_details': str(e)})
            
            # Шаг 5: Рассчитываем статистику
            file_size_bytes = filepath.stat().st_size if filepath.exists() else 0
            file_size_mb = file_size_bytes / (1024 * 1024)
            
            total_duration = (time.time() - start_time) * 1000
            
            result = {
                'status': 'success',
                'message': f'Экспорт завершен. Экспортировано {total_records_exported:,} записей из {total_count:,}.',
                'filepath': str(filepath),
                'symlink_path': str(latest_link),
                'filename': filename,
                'timestamp': timestamp,
                'records_exported': total_records_exported,
                'total_in_db': total_count,
                'file_size_bytes': file_size_bytes,
                'file_size_mb': round(file_size_mb, 2),
                'compression': 'snappy',
                'format': 'parquet',
                'duration_ms': total_duration,
                'duration_seconds': round(total_duration / 1000, 2),
                'completion_percentage': round((total_records_exported / total_count * 100), 2) if total_count > 0 else 0
            }
            
            log_event('INFO', 'create_client_database_copy', 'Экспорт в Parquet успешно завершен', result)
            
            return result
            
        except Exception as e:
            total_duration = (time.time() - start_time) * 1000
            log_event('ERROR', 'create_client_database_copy', 'Критическая ошибка при экспорте',
                    {'error_details': str(e), 
                    'traceback': traceback.format_exc(),
                    'duration_ms': total_duration})
            
            return {
                'status': 'error',
                'message': f'Ошибка при экспорте: {str(e)}',
                'filepath': None,
                'records_exported': 0,
                'duration_ms': total_duration
            }

    def _create_pyarrow_schema_from_model(self, model_class):
        """
        Создает схему PyArrow на основе модели SQLAlchemy.
        
        Args:
            model_class: Класс модели SQLAlchemy (например, ReportDetail)
            
        Returns:
            pa.Schema: Схема PyArrow
        """
        from sqlalchemy import Integer, Float, String, DateTime, Date, Boolean, BigInteger, Numeric
        import pyarrow as pa
        
        fields = []
        
        # Проходим по всем столбцам модели
        for column_name, column in model_class.__table__.columns.items():
            column_type = column.type
            
            # Определяем тип PyArrow на основе типа SQLAlchemy
            if isinstance(column_type, (Integer, BigInteger)):
                pa_type = pa.int64()
            elif isinstance(column_type, (Float, Numeric)):
                pa_type = pa.float64()
            elif isinstance(column_type, String):
                # Используем максимальную длину из модели, если указана
                if hasattr(column_type, 'length') and column_type.length:
                    pa_type = pa.string()
                else:
                    pa_type = pa.string()
            elif isinstance(column_type, DateTime):
                pa_type = pa.timestamp('ns')
            elif isinstance(column_type, Date):
                pa_type = pa.date32()
            elif isinstance(column_type, Boolean):
                pa_type = pa.bool_()
            else:
                # По умолчанию используем строку
                pa_type = pa.string()
                log_event('WARNING', '_create_pyarrow_schema_from_model', 
                        f'Неизвестный тип столбца {column_name}: {type(column_type)}, используется string')
            
            # Определяем, может ли поле быть null
            nullable = column.nullable
            
            # Создаем поле PyArrow
            field = pa.field(column_name, pa_type, nullable=nullable)
            fields.append(field)
        
        # Создаем схему
        schema = pa.schema(fields)
        
        log_event('INFO', '_create_pyarrow_schema_from_model', 
                'Схема PyArrow создана из модели',
                {'model': model_class.__name__, 
                'total_fields': len(fields),
                'field_examples': [(f.name, str(f.type)) for f in fields[:5]]})
        
        return schema