from .db import db
from datetime import datetime

class Commission(db.Model):
    __tablename__ = 'commissions'
    
    id = db.Column(db.Integer, primary_key=True)
    kgvpBooking = db.Column(db.Float, nullable=False)
    kgvpMarketplace = db.Column(db.Float, nullable=False)
    kgvpPickup = db.Column(db.Float, nullable=False)
    kgvpSupplier = db.Column(db.Float, nullable=False)
    kgvpSupplierExpress = db.Column(db.Float, nullable=False)
    paidStorageKgvp = db.Column(db.Float, nullable=False)
    parentID = db.Column(db.Integer, nullable=False)
    parentName = db.Column(db.String(200), nullable=False)
    subjectID = db.Column(db.Integer, nullable=False)
    subjectName = db.Column(db.String(200), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'kgvpBooking': self.kgvpBooking,
            'kgvpMarketplace': self.kgvpMarketplace,
            'kgvpPickup': self.kgvpPickup,
            'kgvpSupplier': self.kgvpSupplier,
            'kgvpSupplierExpress': self.kgvpSupplierExpress,
            'paidStorageKgvp': self.paidStorageKgvp,
            'parentID': self.parentID,
            'parentName': self.parentName,
            'subjectID': self.subjectID,
            'subjectName': self.subjectName,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }