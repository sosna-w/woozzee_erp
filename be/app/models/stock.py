from .db import db
from datetime import datetime

class Stock(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    lastChangeDate = db.Column(db.DateTime)
    warehouseName = db.Column(db.String(50))
    supplierArticle = db.Column(db.String(75))
    nmId = db.Column(db.Integer)
    barcode = db.Column(db.String(30))
    quantity = db.Column(db.Integer)
    inWayToClient = db.Column(db.Integer)
    inWayFromClient = db.Column(db.Integer)
    quantityFull = db.Column(db.Integer)
    category = db.Column(db.String(50))
    subject = db.Column(db.String(50))
    brand = db.Column(db.String(50))
    techSize = db.Column(db.String(30))
    Price = db.Column(db.Float)
    Discount = db.Column(db.Float)
    isSupply = db.Column(db.Boolean)
    isRealization = db.Column(db.Boolean)
    SCCode = db.Column(db.String(50))