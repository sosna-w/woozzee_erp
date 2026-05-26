from .db import db
from datetime import datetime
import json

class WarehouseConfig(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    mode = db.Column(db.String(20), nullable=False, default='uniform')
    uniform_threshold = db.Column(db.Integer, default=0)
    uniform_minimum = db.Column(db.Integer, default=0)
    individual_config = db.Column(db.Text)
    is_activate = db.Column(db.Boolean, default=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'mode': self.mode,
            'uniform_threshold': self.uniform_threshold,
            'uniform_minimum': self.uniform_minimum,
            'individual_config': json.loads(self.individual_config) if self.individual_config else {},
            'is_activate': self.is_activate,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }