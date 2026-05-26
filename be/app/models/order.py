from .db import db
from datetime import datetime

class Order(db.Model):
    __tablename__ = 'orders'
    
    id = db.Column(db.Integer, primary_key=True)
    date = db.Column(db.DateTime, nullable=False)
    lastChangeDate = db.Column(db.DateTime, nullable=False)
    supplierArticle = db.Column(db.String(75))
    techSize = db.Column(db.String(30))
    barcode = db.Column(db.String(30))
    quantity = db.Column(db.Integer)
    totalPrice = db.Column(db.Float)
    discountPercent = db.Column(db.Float)
    warehouseName = db.Column(db.String(200))
    oblast = db.Column(db.String(200))
    incomeID = db.Column(db.Integer)
    odid = db.Column(db.BigInteger)
    nmId = db.Column(db.Integer)
    subject = db.Column(db.String(100))
    category = db.Column(db.String(100))
    brand = db.Column(db.String(100))
    isCancel = db.Column(db.Boolean, default=False)
    cancelDate = db.Column(db.DateTime)
    gNumber = db.Column(db.String(50))
    sticker = db.Column(db.String(100))
    srid = db.Column(db.String(100))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
