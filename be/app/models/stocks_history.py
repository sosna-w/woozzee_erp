from .db import db
from datetime import datetime

class StocksHistory(db.Model):
    """Модель для хранения исторических снимков остатков"""
    __tablename__ = 'stocks_history'
    
    id = db.Column(db.Integer, primary_key=True)
    nm_id = db.Column(db.Integer, nullable=False, index=True)  # ID товара
    total_quantity = db.Column(db.Integer, default=0)  # Общее количество FBO
    fbs_quantity = db.Column(db.Integer, default=0)    # Количество FBS
    created_at = db.Column(db.DateTime, default=datetime.utcnow, index=True)  # Дата снимка
    
    def to_dict(self):
        return {
            'id': self.id,
            'nm_id': self.nm_id,
            'total_quantity': self.total_quantity,
            'fbs_quantity': self.fbs_quantity,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }