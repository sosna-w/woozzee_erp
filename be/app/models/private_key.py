from .db import db
from datetime import datetime

class PrivateKey(db.Model):
    """Модель для хранения приватных ключей продавца (singleton)"""
    __tablename__ = 'private_keys'

    id = db.Column(db.Integer, primary_key=True)
    authorize_v3 = db.Column(db.Text, nullable=False, default='')
    wb_seller_lk = db.Column(db.Text, nullable=False, default='')
    cookie = db.Column(db.Text, nullable=False, default='')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    @classmethod
    def get_instance(cls):
        """Возвращает единственную запись (создаёт пустую, если нет)"""
        inst = cls.query.first()
        if not inst:
            inst = cls(authorize_v3='', wb_seller_lk='', cookie='')
            db.session.add(inst)
            db.session.commit()
        return inst

    def to_dict(self):
        return {
            'authorize_v3': self.authorize_v3,
            'wb_seller_lk': self.wb_seller_lk,
            'cookie': self.cookie,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }