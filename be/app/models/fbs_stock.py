from .db import db
from datetime import datetime

class FBSStock(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    nm_id = db.Column(db.Integer, nullable=False)
    warehouse_id = db.Column(db.Integer, nullable=False)
    barcode = db.Column(db.String(30))
    quantity = db.Column(db.Integer, default=0)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'nm_id': self.nm_id,
            'warehouse_id': self.warehouse_id,
            'barcode': self.barcode,
            'quantity': self.quantity,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }