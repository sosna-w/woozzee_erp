from .db import db
from datetime import datetime
import json

class UnifiedProduct(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    nm_id = db.Column(db.Integer, nullable=False)
    vendor_code = db.Column(db.String(100))
    barcode = db.Column(db.String(30))
    chrt_id = db.Column(db.Integer, nullable=True)  # ← НОВОЕ ПОЛЕ! Может быть NULL
    title = db.Column(db.Text)
    tags = db.Column(db.Text)
    total_quantity = db.Column(db.Integer, default=0)
    fbs_quantity = db.Column(db.Integer, default=0)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'nm_id': self.nm_id,
            'vendor_code': self.vendor_code,
            'barcode': self.barcode,
            'chrt_id': self.chrt_id,  # ← добавляем в вывод
            'title': self.title,
            'tags': json.loads(self.tags) if self.tags else [],
            'total_quantity': self.total_quantity,
            'fbs_quantity': self.fbs_quantity,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }