from .db import db
from datetime import datetime
import json

class UserActivity(db.Model):
    """Модель для хранения активности пользователей (онлайн)"""
    __tablename__ = 'user_activity'
    
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(100), nullable=False)  # Имя пользователя
    activity_datetime = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)  # Дата и время активности
    activity_type = db.Column(db.String(50), default='login')  # Тип активности: login, logout, action, etc.
    ip_address = db.Column(db.String(50))  # IP адрес пользователя
    user_agent = db.Column(db.String(500))  # User Agent браузера
    details = db.Column(db.Text)  # Дополнительные детали в JSON формате
    
    # Индексы для быстрого поиска
    __table_args__ = (
        db.Index('idx_username_activity', 'username', 'activity_datetime'),
        db.Index('idx_activity_datetime', 'activity_datetime'),
    )
    
    def to_dict(self):
        return {
            'id': self.id,
            'username': self.username,
            'activity_datetime': self.activity_datetime.isoformat() if self.activity_datetime else None,
            'activity_type': self.activity_type,
            'ip_address': self.ip_address,
            'user_agent': self.user_agent,
            'details': json.loads(self.details) if self.details else {},
            'created_at': self.activity_datetime.isoformat() if self.activity_datetime else None
        }