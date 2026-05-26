# models/__init__.py

# Объект БД
from .db import db

# Модели (каждая из своего модуля)
from .token import Token
from .user import User
from .product import Product
from .stock import Stock
from .warehouse import Warehouse
from .warehouse_config import WarehouseConfig
from .unified_product import UnifiedProduct
from .fbs_stock import FBSStock
from .tag_config import TagConfig
from .auto_replenishment_config import AutoReplenishmentConfig
from .product_auto_config import ProductAutoConfig
from .commission import Commission
from .product_cost import ProductCost
from .box_tariff import BoxTariff
from .subject import Subject
from .order import Order
from .app_version import AppVersion
from .stocks_history import StocksHistory
from .user_activity import UserActivity
from .report_detail import ReportDetail
from .sales_funnel_report import SalesFunnelReport
from .product_price import ProductPrice
from .product_current_price import ProductCurrentPrice
from .current_price_history import CurrentPriceHistory
from .product_actual_search_text import ProductActualSearchText
from .online_activity import OnlineActivity
from .warehouse_remains import WarehouseRemains
from .warehouse_mapping import WarehouseMapping
from .warehouse_stock_history import WarehouseStockHistory
from .private_key import PrivateKey


# Лог-модель (из отдельного файла)
from .log_model import Log

__all__ = [
    'db',
    'Token',
    'User',
    'Log',
    'Product',
    'Stock',
    'Warehouse',
    'WarehouseConfig',
    'UnifiedProduct',
    'FBSStock',
    'TagConfig',
    'AutoReplenishmentConfig',
    'ProductAutoConfig',
    'Commission',
    'ProductCost',
    'BoxTariff',
    'Subject',
    'Order',
    'AppVersion',
    'StocksHistory',
    'UserActivity',
    'ReportDetail',
    'SalesFunnelReport',
    'ProductPrice',
    'ProductCurrentPrice',
    'CurrentPriceHistory',
    'ProductActualSearchText',
    'OnlineActivity',
    'WarehouseRemains',
    'WarehouseMapping',
    'WarehouseStockHistory',
    'PrivateKey'
]