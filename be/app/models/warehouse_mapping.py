from .db import db
from datetime import datetime

class WarehouseMapping(db.Model):
    """Маппинг названий складов между разными источниками"""
    __tablename__ = 'warehouse_mappings'

    id = db.Column(db.Integer, primary_key=True)
    wh_name_wb_api_warehouses = db.Column(db.String(300), nullable=False)       # имя из API складов WB
    wh_name_my_api_warehouse_remains = db.Column(db.String(300), nullable=False) # имя из /warehouse-remains
    wh_name_my_api_order_feed = db.Column(db.String(300), nullable=False)        # имя из фида заказов
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'wh_name_wb_api_warehouses': self.wh_name_wb_api_warehouses,
            'wh_name_my_api_warehouse_remains': self.wh_name_my_api_warehouse_remains,
            'wh_name_my_api_order_feed': self.wh_name_my_api_order_feed,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }