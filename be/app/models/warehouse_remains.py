from .db import db
from datetime import datetime

class WarehouseRemains(db.Model):
    """Таблица для хранения остатков по складам (плоская структура)"""
    __tablename__ = 'warehouse_remains'

    id = db.Column(db.Integer, primary_key=True)
    brand = db.Column(db.String(200))
    subject_name = db.Column(db.String(200))
    vendor_code = db.Column(db.String(100))
    nm_id = db.Column(db.Integer, nullable=False, index=True)
    barcode = db.Column(db.String(50))
    tech_size = db.Column(db.String(50))
    volume = db.Column(db.Float)
    warehouse_name = db.Column(db.String(200), nullable=False)
    quantity = db.Column(db.Integer, nullable=False)
    report_date = db.Column(db.Date, nullable=False, index=True)   # дата, на которую сформирован отчёт
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'brand': self.brand,
            'subject_name': self.subject_name,
            'vendor_code': self.vendor_code,
            'nm_id': self.nm_id,
            'barcode': self.barcode,
            'tech_size': self.tech_size,
            'volume': float(self.volume) if self.volume is not None else None,
            'warehouse_name': self.warehouse_name,
            'quantity': self.quantity,
            'report_date': self.report_date.isoformat() if self.report_date else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }