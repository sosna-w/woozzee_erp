# config.py
import os
from datetime import datetime

class Config:
    # Основная база данных (PostgreSQL)
    SQLALCHEMY_DATABASE_URI = 'postgresql://wb_user:Fyukbqcrbq1@localhost/wildberries_app'
    
    # База данных для логов (PostgreSQL) - отдельная база для распределения нагрузки
    SQLALCHEMY_BINDS = {
        'logs': 'postgresql://wb_user:Fyukbqcrbq1@localhost/wildberries_logs'
    }
    
    # Отключаем отслеживание изменений для производительности
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    
    # Настройки пула соединений для PostgreSQL
    SQLALCHEMY_ENGINE_OPTIONS = {
        'pool_size': 20,
        'max_overflow': 30,
        'pool_recycle': 300,
        'pool_pre_ping': True,
        'pool_timeout': 30,
    }