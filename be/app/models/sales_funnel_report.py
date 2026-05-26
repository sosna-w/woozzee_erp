from .db import db
from datetime import datetime

class SalesFunnelReport(db.Model):
    """Агрегированная воронка продаж по дням/товарам"""
    __tablename__ = 'sales_funnel_reports'

    id = db.Column(db.Integer, primary_key=True)
    date = db.Column(db.Date, nullable=False, index=True)          # день отчёта
    nm_id = db.Column(db.Integer, nullable=False, index=True)      # артикул WB
    title = db.Column(db.String(500))                             # название товара (из ответа)
    vendor_code = db.Column(db.String(100))                       # артикул продавца
    brand_name = db.Column(db.String(200))                        # бренд
    open_count = db.Column(db.Integer, default=0)                 # переходы в карточку
    cart_count = db.Column(db.Integer, default=0)                 # добавления в корзину
    order_count = db.Column(db.Integer, default=0)                # заказы
    order_sum = db.Column(db.Float, default=0.0)                  # заказано (сумма)
    buyout_count = db.Column(db.Integer, default=0)               # выкупы
    buyout_sum = db.Column(db.Float, default=0.0)                 # выкуплено (сумма)
    buyout_percent = db.Column(db.Float, default=0.0)             # % выкупа
    add_to_cart_conversion = db.Column(db.Float, default=0.0)      # конверсия в корзину
    cart_to_order_conversion = db.Column(db.Float, default=0.0)    # конверсия в заказ
    add_to_wishlist_count = db.Column(db.Integer, default=0)       # добавления в отложенные
    currency = db.Column(db.String(3), default='RUB')              # валюта
    created_at = db.Column(db.DateTime, default=datetime.utcnow)   # время загрузки

    def to_dict(self):
        return {
            'id': self.id,
            'date': self.date.isoformat(),
            'nm_id': self.nm_id,
            'title': self.title,
            'vendor_code': self.vendor_code,
            'brand_name': self.brand_name,
            'open_count': self.open_count,
            'cart_count': self.cart_count,
            'order_count': self.order_count,
            'order_sum': self.order_sum,
            'buyout_count': self.buyout_count,
            'buyout_sum': self.buyout_sum,
            'buyout_percent': self.buyout_percent,
            'add_to_cart_conversion': self.add_to_cart_conversion,
            'cart_to_order_conversion': self.cart_to_order_conversion,
            'add_to_wishlist_count': self.add_to_wishlist_count,
            'currency': self.currency,
            'created_at': self.created_at.isoformat(),
        }