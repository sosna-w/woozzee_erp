from .db import db
from datetime import datetime

class OnlineActivity(db.Model):
    __tablename__ = 'online_activity'
    id = db.Column(db.Integer, primary_key=True)
    uuid = db.Column(db.String(36), nullable=False, index=True)
    computer_name = db.Column(db.String(100))
    user_name = db.Column(db.String(100))
    os_version = db.Column(db.String(200))
    first_run = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'uuid': self.uuid,
            'computer_name': self.computer_name,
            'user_name': self.user_name,
            'os_version': self.os_version,
            'first_run': self.first_run.isoformat() if self.first_run else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }