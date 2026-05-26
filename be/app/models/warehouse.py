from .db import db
from datetime import datetime

class Warehouse(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(200), nullable=False)
    office_id = db.Column(db.Integer, nullable=False)
    warehouse_id = db.Column(db.Integer, nullable=False)
    cargo_type = db.Column(db.Integer)
    delivery_type = db.Column(db.Integer)
    is_deleting = db.Column(db.Boolean, default=False)
    is_processing = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.warehouse_id,
            'name': self.name,
            'officeId': self.office_id,
            'warehouse_id': self.warehouse_id,
            'cargoType': self.cargo_type,
            'deliveryType': self.delivery_type,
            'isDeleting': self.is_deleting,
            'isProcessing': self.is_processing,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }