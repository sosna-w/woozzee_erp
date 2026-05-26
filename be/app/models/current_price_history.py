from .db import db
from datetime import datetime

class CurrentPriceHistory(db.Model):
    """История цен для покупателя (снэпшоты из ProductCurrentPrice)"""
    __tablename__ = 'current_price_history'

    id = db.Column(db.Integer, primary_key=True)
    nm_id = db.Column(db.Integer, nullable=False, index=True)
    price = db.Column(db.Float, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, index=True)

    def to_dict(self):
        return {
            'id': self.id,
            'nm_id': self.nm_id,
            'price': self.price,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }