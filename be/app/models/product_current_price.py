from .db import db
from datetime import datetime

class ProductCurrentPrice(db.Model):
    """Актуальная цена товара, полученная через публичное API карточек"""
    __tablename__ = 'product_current_prices'

    id = db.Column(db.Integer, primary_key=True)
    nm_id = db.Column(db.Integer, nullable=False, unique=True, index=True)
    price = db.Column(db.Float, nullable=False)          # конечная цена (поле product из ответа)
    last_updated = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    def to_dict(self):
        return {
            'nm_id': self.nm_id,
            'price': self.price,
            'last_updated': self.last_updated.isoformat() if self.last_updated else None
        }