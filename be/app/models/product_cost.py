from .db import db
from datetime import datetime

class ProductCost(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    wb_article = db.Column(db.String(100))  # Артикул WB
    my_article = db.Column(db.String(100))  # Мой артикул (артикул продавца)
    cost_price = db.Column(db.Float)        # Себестоимость
    additional_expenses = db.Column(db.Float)  # Дополнительные расходы
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'wb_article': self.wb_article,
            'my_article': self.my_article,
            'cost_price': self.cost_price,
            'additional_expenses': self.additional_expenses,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
            'total_cost': (self.cost_price or 0) + (self.additional_expenses or 0) if self.cost_price else None
        }