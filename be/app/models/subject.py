from .db import db
from datetime import datetime

class Subject(db.Model):
    """Модель для хранения предметов и родительских категорий"""
    __tablename__ = 'subjects'
    
    id = db.Column(db.Integer, primary_key=True)
    subject_id = db.Column(db.Integer, unique=True, nullable=False)  # ID предмета
    parent_id = db.Column(db.Integer, nullable=False)  # ID родительской категории
    subject_name = db.Column(db.String(200), nullable=False)  # Название предмета
    parent_name = db.Column(db.String(200), nullable=False)  # Название родительской категории
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'subject_id': self.subject_id,
            'parent_id': self.parent_id,
            'subject_name': self.subject_name,
            'parent_name': self.parent_name,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }