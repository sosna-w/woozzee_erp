from .db import db
from datetime import datetime

class TagConfig(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    tag_name = db.Column(db.String(100), nullable=False, unique=True)
    behavior = db.Column(db.String(20), nullable=False, default='as_warehouse')
    fixed_amount = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'tag_name': self.tag_name,
            'behavior': self.behavior,
            'fixed_amount': self.fixed_amount,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }