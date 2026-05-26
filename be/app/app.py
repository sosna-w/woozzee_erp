from flask import Flask, request, jsonify, send_file, make_response, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from apscheduler.schedulers.background import BackgroundScheduler
import requests
import time
import threading
from datetime import date, datetime, timedelta, timezone
import atexit
import json
import sys
import traceback
import pandas as pd
from io import BytesIO
from sqlalchemy import text, func
import os
import re
from pathlib import Path
import uuid
import zipfile
import io
from sqlalchemy import and_
import pyarrow as pa
import pyarrow.parquet as pq
import random
from threading import Thread, Event
import openpyxl
from flask_jwt_extended import JWTManager, create_access_token, jwt_required, get_jwt_identity

from report_fetcher import WBReportFetcher
from utils.logger import log_event
from utils.rate_limiter import RateLimiter, safe_json_response
from utils.token_manager import save_token, get_token, token_exists, delete_token, get_api_key
from services.wb_auto_promotion import WBAutoPromotionManager
from services.search_text_manager import SearchTextManager
from services.order_feed_api import OrderFeedPrivateAPI
from services.order_service import fetch_orders, update_orders_job
from services.commission_service import fetch_commissions
from services.box_tariff_service import fetch_box_tariffs, hourly_update_box_tariffs
from services.warehouse_remains_service import fetch_warehouse_remains
from services.product_service import fetch_all_products, fetch_all_stocks, fetch_warehouses
from services.product_service import fetch_fbs_stocks, _update_stocks_via_api
from services.unified_product_service import update_unified_products, create_stocks_snapshot
from services.unified_product_service import schedule_unified_update, fetch_all_products_with_unified, fetch_all_stocks_with_unified
from services.auto_replenishment_service import log_auto_replenishment_debug, auto_replenish_stocks
from services.sales_funnel_service import fetch_sales_funnel_period, scheduled_sales_funnel_update, enrich_all_existing_reports
from services.price_service import fetch_product_prices, create_current_price_snapshot, start_price_update_thread
from services.subject_service import fetch_all_subjects
from services.order_feed_service import fetch_and_save_order_feed_21_days
from services.order_export_service import create_export_task, get_export_task_status, get_export_task_result, get_export_task_dates
from routes.logs_routes import logs_bp
from routes.auth_routes import auth_bp
from routes.admin_routes import admin_bp
from routes.warehouse_routes import warehouse_bp
from routes.product_routes import product_bp
from routes.cost_routes import cost_bp
from routes.commission_routes import commission_bp
from routes.box_tariff_routes import box_tariff_bp
from routes.order_routes import order_bp
from routes.report_routes import report_bp
from routes.price_routes import price_bp
from routes.online_routes import online_bp
from routes.search_text_routes import search_text_bp, set_search_manager
from routes.auto_replenishment_routes import auto_replenishment_bp
from routes.app_version_routes import app_version_bp
from routes.subject_routes import subject_bp
from routes.export_routes import export_bp
from routes.stocks_history_routes import stocks_history_bp
from routes.db_routes import db_bp
from routes.auto_promotion_routes import auto_promo_bp
from routes.public_routes import public_bp
from routes.warehouse_remains_routes import warehouse_remains_bp
from routes.tags_routes import tags_bp
from routes.debug_routes import debug_bp
from routes.report_details_routes import report_details_bp


app = Flask(__name__)
app.config['JWT_SECRET_KEY'] = ''
app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(hours=24)
jwt = JWTManager(app)

try:
    from config import Config
    app.config.from_object(Config)
except ImportError:
    # Запасная конфигурация
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///sosna.db'
    app.config['SQLALCHEMY_BINDS'] = {
        'logs': 'postgresql://wb_user:Fyukbqcrbq1@localhost/wildberries_logs'
    }
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

from models import db, Log, Token, User, Product, Stock, Warehouse, WarehouseConfig, UnifiedProduct
from models import FBSStock, TagConfig, AutoReplenishmentConfig, ProductAutoConfig, Commission
from models import ProductCost, BoxTariff, Subject, Order, AppVersion, StocksHistory, UserActivity
from models import ReportDetail, SalesFunnelReport, ProductPrice, ProductCurrentPrice, CurrentPriceHistory
from models import ProductActualSearchText, OnlineActivity, WarehouseRemains, WarehouseMapping, WarehouseStockHistory, PrivateKey

db.init_app(app)
search_manager = SearchTextManager(app)
set_search_manager(search_manager)
limiter = RateLimiter()

app.register_blueprint(logs_bp)
app.register_blueprint(auth_bp)
app.register_blueprint(admin_bp)
app.register_blueprint(warehouse_bp)
app.register_blueprint(product_bp)
app.register_blueprint(cost_bp)
app.register_blueprint(commission_bp)
app.register_blueprint(box_tariff_bp)
app.register_blueprint(order_bp)
app.register_blueprint(report_bp)
app.register_blueprint(price_bp)
app.register_blueprint(online_bp)
app.register_blueprint(search_text_bp)
app.register_blueprint(auto_replenishment_bp)
app.register_blueprint(app_version_bp)
app.register_blueprint(subject_bp)
app.register_blueprint(export_bp)
app.register_blueprint(stocks_history_bp)
app.register_blueprint(db_bp)
app.register_blueprint(auto_promo_bp)
app.register_blueprint(public_bp)
app.register_blueprint(warehouse_remains_bp)
app.register_blueprint(tags_bp)
app.register_blueprint(debug_bp)
app.register_blueprint(report_details_bp)

scheduler = BackgroundScheduler()

def run_with_app_context(func):
    def wrapper():
        with app.app_context():
            func()
    return wrapper

def start_auto_replenishment_scheduler():
    def check_auto_replenishment():
        with app.app_context():
            try:
                log_auto_replenishment_debug('scheduler_check', {
                    'timestamp': datetime.utcnow().isoformat(),
                    'scheduler_running': scheduler.running
                })
                
                config = AutoReplenishmentConfig.query.first()
                if not config or not config.enabled:
                    log_auto_replenishment_debug('scheduler_skip', {'reason': 'config_disabled'})
                    return
                
                now = datetime.utcnow()
                if config.last_run:
                    time_diff = (now - config.last_run).total_seconds() / 60
                    log_auto_replenishment_debug('scheduler_timing', {
                        'last_run': config.last_run.isoformat(),
                        'time_diff_minutes': time_diff,
                        'interval_minutes': config.interval_minutes,
                        'should_run': time_diff >= config.interval_minutes
                    })
                    
                    if time_diff >= config.interval_minutes:
                        log_event('INFO', 'auto_replenishment_scheduler', 
                                 'Запуск автообновления по расписанию',
                                 {'time_diff_minutes': time_diff})
                        auto_replenish_stocks()
                    else:
                        log_auto_replenishment_debug('scheduler_wait', {
                            'minutes_until_next': config.interval_minutes - time_diff
                        })
                else:
                    log_event('INFO', 'auto_replenishment_scheduler', 
                             'Первый запуск автообновления')
                    auto_replenish_stocks()
                    
            except Exception as e:
                log_event('ERROR', 'auto_replenishment_scheduler', 
                         'Ошибка в планировщике автообновления',
                         {'error': str(e)})
    
    scheduler.add_job(func=check_auto_replenishment, trigger="interval", seconds=60)
    log_event('INFO', 'start_auto_replenishment_scheduler', 'Планировщик автообновления остатков запущен')
    print("✅ Планировщик автообновления остатков запущен (проверка каждые 60 секунд)")

def init_database():
    try:
        with app.app_context():
            # Создаем все таблицы в основной базе (PostgreSQL)
            db.create_all()
            search_manager.start_background()
            
            # Создаем таблицу логов в отдельной базе
            try:
                Log.__table__.create(bind=db.get_engine(app, bind='logs'), checkfirst=True)
                print("✅ База логов (PostgreSQL) создана/проверена")
            except Exception as e:
                print(f"⚠️ Ошибка при создании таблицы логов: {e}")

            try:
                PrivateKey.__table__.create(bind=db.engine, checkfirst=True)
                # Создаём пустую запись, если её нет
                PrivateKey.get_instance()
                print("✅ Таблица private_keys создана/проверена")
            except Exception as e:
                print(f"⚠️ Ошибка при создании таблицы private_keys: {e}")

            try:
                ReportDetail.__table__.create(bind=db.get_engine(app), checkfirst=True)
                print("✅ Таблица отчетов создана/проверена")
            except Exception as e:
                print(f"⚠️ Ошибка при создании таблицы отчетов: {e}")
            
            from sqlalchemy import inspect
            inspector = inspect(db.engine)
            tables = inspector.get_table_names()
            print(f"📊 Таблицы в основной базе (wildberries_app): {len(tables)} таблиц")
            
            # Статистика по таблицам
            stats = {
                'tokens': Token.query.count(),
                'products': Product.query.count(),
                'stocks': Stock.query.count(),
                'warehouses': Warehouse.query.count(),
                'unified_products': UnifiedProduct.query.count(),
                'fbs_stocks': FBSStock.query.count(),
                'orders': Order.query.count(),
                'commissions': Commission.query.count(),
                'subjects': Subject.query.count(),
                'box_tariffs': BoxTariff.query.count(),
                'product_costs': ProductCost.query.count(),
                'stocks_history': StocksHistory.query.count(),
                'user_activity': UserActivity.query.count(),
            }
            
            for table, count in stats.items():
                if count > 0:
                    print(f"   • {table}: {count}")
            
            # Проверяем, нужны ли первоначальные загрузки
            if Token.query.first() is None:
                print("ℹ️ Токен не найден, загрузка данных будет выполнена после его добавления")
            
            # Если таблицы пустые, запускаем первоначальную загрузку предметов
            if Subject.query.count() == 0:
                print("🔄 Таблица subjects пустая, запускаем первоначальную загрузку...")
                try:
                    fetch_all_subjects()
                    print("✅ Первоначальная загрузка предметов завершена")
                except Exception as e:
                    print(f"⚠️ Ошибка при первоначальной загрузке предметов: {e}")
            
            # Если таблица комиссий пустая
            if Commission.query.count() == 0:
                print("🔄 Таблица комиссий пустая, запускаем первоначальную загрузку...")
                try:
                    fetch_commissions()
                    print("✅ Первоначальная загрузка комиссий завершена")
                except Exception as e:
                    print(f"⚠️ Ошибка при первоначальной загрузке комиссий: {e}")
            
            # Если таблица тарифов коробов пустая
            if BoxTariff.query.count() == 0:
                print("🔄 Таблица тарифов коробов пустая, запускаем первоначальную загрузку...")
                try:
                    fetch_box_tariffs()
                    print("✅ Первоначальная загрузка тарифов коробов завершена")
                except Exception as e:
                    print(f"⚠️ Ошибка при первоначальной загрузке тарифов коробов: {e}")

            try:
                CurrentPriceHistory.__table__.create(bind=db.get_engine(app), checkfirst=True)
                print("✅ Таблица current_price_history создана/проверена")
            except Exception as e:
                print(f"⚠️ Ошибка при создании таблицы current_price_history: {e}")

            try:
                ProductActualSearchText.__table__.create(bind=db.engine, checkfirst=True)
                print("✅ Таблица product_actual_search_text создана/проверена")
            except Exception as e:
                print(f"⚠️ Ошибка при создании таблицы product_actual_search_text: {e}")


            try:
                WarehouseMapping.__table__.create(bind=db.get_engine(app), checkfirst=True)
                print("✅ Таблица warehouse_mappings создана/проверена")
            except Exception as e:
                print(f"⚠️ Ошибка при создании таблицы warehouse_mappings: {e}")

            # Запуск фонового обновления цен (только один раз)
            try:
                if not hasattr(app, '_price_thread_started'):
                    start_price_update_thread()
                    app._price_thread_started = True
            except Exception as e:
                print(f"⚠️ Ошибка запуска потока обновления цен: {e}")
            
            print("✅ Инициализация баз данных PostgreSQL завершена")
            
    except Exception as e:
        print(f"❌ Ошибка инициализации баз данных: {e}")
        import traceback
        traceback.print_exc()


def initial_orders_load():
    """Первоначальная загрузка заказов за 30 дней (безопасная версия)"""
    try:
        log_event('INFO', 'initial_orders_load', 'Начало первоначальной загрузки заказов за 30 дней')
        
        # Даем время на запуск сервера
        time.sleep(5)
        
        api_key = get_api_key()
        if not api_key:
            log_event('ERROR', 'initial_orders_load', 'Нет токена для загрузки заказов')
            return
        
        orders_count = fetch_orders(first_request=True)
        if orders_count > 0:
            log_event('INFO', 'initial_orders_load', 'Первоначальная загрузка заказов завершена',
                     {'orders_received': orders_count})
        else:
            log_event('WARNING', 'initial_orders_load', 'Не получено заказов при первоначальной загрузке')
            
    except Exception as e:
        log_event('ERROR', 'initial_orders_load', 'Ошибка при первоначальной загрузке заказов',
                 {'error': str(e)})


def schedule_daily_reports():
    try:
        with app.app_context():
            yesterday = datetime.now() - timedelta(days=1)
            date_str = yesterday.strftime("%Y-%m-%d")
            log_event('INFO', 'schedule_daily_reports', f'Автоматическая загрузка отчета за {date_str}')
            fetcher = WBReportFetcher()
            df = fetcher.fetch_data_by_date(date_str)
            if not df.empty:
                processed_df = fetcher.process_dataframe(df, date_str)
                if not processed_df.empty:
                    saved = fetcher.save_to_database(processed_df, date_str)
                    log_event('INFO', 'schedule_daily_reports', 
                              f'Автоматическая загрузка отчета за {date_str} завершена',
                              {'saved_records': saved, 'total_records': len(processed_df)})
                    # ✅ Создаем Parquet-файл после сохранения
                    fetcher.create_client_database_copy()
            else:
                log_event('INFO', 'schedule_daily_reports', 
                          f'Нет данных для отчета за {date_str}')
    except Exception as e:
        log_event('ERROR', 'schedule_daily_reports', 
                  f'Ошибка при автоматической загрузке отчета: {str(e)}')

# Запускаем первоначальную загрузку в отдельном потоке при старте
threading.Thread(target=initial_orders_load).start()

# Инициализация планировщика
scheduler.add_job(func=run_with_app_context(fetch_all_products_with_unified), trigger="interval", seconds=1200)
scheduler.add_job(func=run_with_app_context(fetch_all_stocks_with_unified), trigger="interval", seconds=1800)
scheduler.add_job(func=run_with_app_context(update_unified_products), trigger="interval", seconds=60)
scheduler.add_job(func=run_with_app_context(fetch_warehouses), trigger="interval", hours=24)
scheduler.add_job(func=run_with_app_context(fetch_fbs_stocks), trigger="interval", seconds=60)
scheduler.add_job(func=run_with_app_context(fetch_commissions), trigger="interval", seconds=86400)
scheduler.add_job(func=run_with_app_context(hourly_update_box_tariffs), trigger="interval", hours=1)
scheduler.add_job(func=run_with_app_context(fetch_all_subjects), trigger="interval", hours=24)
scheduler.add_job(func=run_with_app_context(update_orders_job), trigger="interval", seconds=180)
scheduler.add_job(
    func=run_with_app_context(create_stocks_snapshot),
    trigger='interval',
    hours=1,
    id='stocks_snapshot_hourly',
    name='Создание часового снимка остатков'
)
scheduler.add_job(
    func=run_with_app_context(schedule_daily_reports),
    trigger='cron',
    hour=7,  # В 7 утра по МСК
    minute=0,
    id='daily_reports_scheduler',
    name='Ежедневная загрузка отчетов'
)

# Обновление цен товаров каждые 12 часов
scheduler.add_job(
    func=run_with_app_context(fetch_product_prices),
    trigger="interval",
    hours=12,
    id='product_prices_update_12h',
    name='Обновление цен товаров'
)

scheduler.add_job(
    func=run_with_app_context(create_current_price_snapshot),
    trigger='cron',
    hour='*',
    minute=0,
    id='current_price_snapshot_hourly',
    name='Создание часового снэпшота цен для покупателя'
)
scheduler.add_job(
    func=run_with_app_context(fetch_warehouse_remains),
    trigger="interval",
    minutes=60,
    id='warehouse_remains_update_hourly',
    name='Обновление остатков по складам (раз в час)'
)
scheduler.add_job(
    func=run_with_app_context(create_warehouse_stock_snapshot),
    trigger='cron',
    hour=9,
    minute=0,
    id='warehouse_stock_snapshot_9am',
    name='Daily warehouse stock snapshot (per warehouse)',
    timezone='Europe/Moscow'
)
scheduler.add_job(
    func=run_with_app_context(fetch_and_save_order_feed_21_days),
    trigger="interval",
    minutes=60,
    id='order_feed_21_days',
    name='Обновление ленты заказов за 21 день'
)
scheduler.add_job(
    func=run_with_app_context(schedule_daily_search_texts),
    trigger='cron',
    hour=4,
    minute=0,
    timezone='Europe/Moscow',
    id='daily_search_texts_history',
    name='Загрузка истории поисковых запросов за вчерашний день'
)


scheduler.start()

# Запуск планировщика автообновления
start_auto_replenishment_scheduler()

# Завершение работы
atexit.register(lambda: scheduler.shutdown())

# Инициализация базы данных
init_database()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)