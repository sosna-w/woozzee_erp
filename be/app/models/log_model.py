# models/log_model.py
from .db import db
from datetime import datetime
import json

class Log(db.Model):
    __bind_key__ = 'logs'  # Логи в отдельной базе для распределения нагрузки
    __tablename__ = 'logs'
    
    id = db.Column(db.Integer, primary_key=True)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    level = db.Column(db.String(20), nullable=False)
    method = db.Column(db.String(100), nullable=False)
    event = db.Column(db.Text, nullable=False)
    details = db.Column(db.Text)
    duration_ms = db.Column(db.Float)
    nm_id = db.Column(db.Integer)
    request_url = db.Column(db.String(500))
    response_status = db.Column(db.Integer)
    records_processed = db.Column(db.Integer)

    def to_dict(self):
        return {
            'id': self.id,
            'timestamp': self.timestamp.isoformat() if self.timestamp else None,
            'level': self.level,
            'method': self.method,
            'event': self.event,
            'details': json.loads(self.details) if self.details else None,
            'duration_ms': self.duration_ms,
            'nm_id': self.nm_id,
            'request_url': self.request_url,
            'response_status': self.response_status,
            'records_processed': self.records_processed
        }