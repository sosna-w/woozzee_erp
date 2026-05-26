from .db import db
from datetime import datetime

class WarehouseStockHistory(db.Model):
    """История остатков по складам (ежедневный снимок)"""
    __tablename__ = 'warehouse_stock_history'

    id = db.Column(db.Integer, primary_key=True)
    nm_id = db.Column(db.Integer, nullable=False, index=True)
    warehouse_name = db.Column(db.String(200), nullable=False, index=True)
    quantity = db.Column(db.Integer, nullable=False)
    date = db.Column(db.Date, nullable=False, index=True)          # дата остатков (report_date из warehouse_remains)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)   # когда сделан снимок

    __table_args__ = (
        db.UniqueConstraint('nm_id', 'warehouse_name', 'date', name='uq_stock_history_nm_warehouse_date'),
        db.Index('idx_stock_history_date_warehouse', 'date', 'warehouse_name'),
    )

    def to_dict(self):
        return {
            'id': self.id,
            'nm_id': self.nm_id,
            'warehouse_name': self.warehouse_name,
            'quantity': self.quantity,
            'date': self.date.isoformat(),
            'created_at': self.created_at.isoformat() if self.created_at else None
        }