from .db import db
from datetime import datetime

class ProductPrice(db.Model):
    __tablename__ = 'product_prices'

    id = db.Column(db.Integer, primary_key=True)
    nm_id = db.Column(db.Integer, nullable=False, index=True)
    vendor_code = db.Column(db.String(100))
    size_id = db.Column(db.BigInteger, nullable=False, index=True)
    price = db.Column(db.Float, nullable=False)
    discounted_price = db.Column(db.Float, nullable=False)
    club_discounted_price = db.Column(db.Float, nullable=False)
    discount = db.Column(db.Integer)
    club_discount = db.Column(db.Integer)
    currency = db.Column(db.String(3), default='RUB')
    tech_size_name = db.Column(db.String(50))
    editable_size_price = db.Column(db.Boolean, default=False)
    is_bad_turnover = db.Column(db.Boolean, default=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Составной индекс для быстрого поиска последних цен
    __table_args__ = (
        db.Index('idx_nm_size_updated', 'nm_id', 'size_id', 'updated_at'),
    )

    def to_dict(self):
        return {
            'id': self.id,
            'nm_id': self.nm_id,
            'vendor_code': self.vendor_code,
            'size_id': self.size_id,
            'price': self.price,
            'discounted_price': self.discounted_price,
            'club_discounted_price': self.club_discounted_price,
            'discount': self.discount,
            'club_discount': self.club_discount,
            'currency': self.currency,
            'tech_size_name': self.tech_size_name,
            'editable_size_price': self.editable_size_price,
            'is_bad_turnover': self.is_bad_turnover,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }