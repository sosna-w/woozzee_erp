from .db import db
from datetime import datetime
import json

class ProductActualSearchText(db.Model):
    """Актуальные поисковые запросы по товарам за сегодняшний день (перезаписывается при каждом обновлении)"""
    __tablename__ = 'product_actual_search_text'

    id = db.Column(db.Integer, primary_key=True)
    nm_id = db.Column(db.Integer, nullable=False, index=True)
    total_frequency = db.Column(db.Integer, default=0)                 # сумма frequency.current
    search_texts = db.Column(db.Text)                                 # JSON {запрос: частота}
    report_date = db.Column(db.Date, nullable=False, index=True)      # дата отчёта (МСК)
    last_updated = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'nm_id': self.nm_id,
            'total_frequency': self.total_frequency,
            'search_texts': json.loads(self.search_texts) if self.search_texts else {},
            'report_date': self.report_date.isoformat() if self.report_date else None,
            'last_updated': self.last_updated.isoformat() if self.last_updated else None,
        }