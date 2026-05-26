from .db import db
from datetime import datetime

class AppVersion(db.Model):
    """Модель для хранения информации о версиях приложения"""
    __tablename__ = 'app_versions'
    
    id = db.Column(db.Integer, primary_key=True)
    version = db.Column(db.String(20), nullable=False, unique=True)  # Версия, например "1.0.0"
    filename = db.Column(db.String(255), nullable=False)  # Имя файла, например "sosna_app_1.0.0.exe"
    title = db.Column(db.String(200), nullable=False)  # Заголовок описания
    description = db.Column(db.Text, nullable=False)  # Текст описания
    download_count = db.Column(db.Integer, default=0)  # Кол-во скачиваний
    release_date = db.Column(db.DateTime, default=datetime.utcnow)  # Дата публикации
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'version': self.version,
            'filename': self.filename,
            'title': self.title,
            'description': self.description,
            'download_count': self.download_count,
            'release_date': self.release_date.isoformat() if self.release_date else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }