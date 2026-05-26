from .db import db
from datetime import datetime

class ProductAutoConfig(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    nm_id = db.Column(db.Integer, nullable=False, unique=True)
    fbo_threshold = db.Column(db.Integer, nullable=True)  # Изменено на NULL
    fbs_minimum = db.Column(db.Integer, nullable=True)    # Изменено на NULL
    ignore_auto_replenishment = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'nm_id': self.nm_id,
            'fbo_threshold': self.fbo_threshold,  # Будет None если NULL
            'fbs_minimum': self.fbs_minimum,      # Будет None если NULL
            'ignore_auto_replenishment': self.ignore_auto_replenishment,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }