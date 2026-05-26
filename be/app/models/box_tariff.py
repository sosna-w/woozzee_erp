from .db import db
from datetime import datetime

class BoxTariff(db.Model):
    __tablename__ = 'box_tariffs'
    
    id = db.Column(db.Integer, primary_key=True)
    date = db.Column(db.String(10), nullable=False, index=True)  # Дата в формате ГГГГ-ММ-ДД
    warehouse_name = db.Column(db.String(200), nullable=False, index=True)
    geo_name = db.Column(db.String(100), nullable=False)
    box_delivery_base = db.Column(db.String(50))  # Логистика, первый литр, ₽
    box_delivery_coef_expr = db.Column(db.String(50))  # Коэффициент Логистика, %
    box_delivery_liter = db.Column(db.String(50))  # Логистика, дополнительный литр, ₽
    box_delivery_marketplace_base = db.Column(db.String(50))  # Логистика FBS, первый литр, ₽
    box_delivery_marketplace_coef_expr = db.Column(db.String(50))  # Коэффициент FBS, %
    box_delivery_marketplace_liter = db.Column(db.String(50))  # Логистика FBS, дополнительный литр, ₽
    box_storage_base = db.Column(db.String(50))  # Хранение в день, первый литр, ₽
    box_storage_coef_expr = db.Column(db.String(50))  # Коэффициент Хранение, %
    box_storage_liter = db.Column(db.String(50))  # Хранение в день, дополнительный литр, ₽
    dt_next_box = db.Column(db.String(10))  # Дата начала следующего тарифа
    dt_till_max = db.Column(db.String(10))  # Дата окончания последнего установленного тарифа
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'date': self.date,
            'warehouse_name': self.warehouse_name,
            'geo_name': self.geo_name,
            'box_delivery_base': self.box_delivery_base,
            'box_delivery_coef_expr': self.box_delivery_coef_expr,
            'box_delivery_liter': self.box_delivery_liter,
            'box_delivery_marketplace_base': self.box_delivery_marketplace_base,
            'box_delivery_marketplace_coef_expr': self.box_delivery_marketplace_coef_expr,
            'box_delivery_marketplace_liter': self.box_delivery_marketplace_liter,
            'box_storage_base': self.box_storage_base,
            'box_storage_coef_expr': self.box_storage_coef_expr,
            'box_storage_liter': self.box_storage_liter,
            'dt_next_box': self.dt_next_box,
            'dt_till_max': self.dt_till_max,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }