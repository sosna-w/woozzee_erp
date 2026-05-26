import time
from datetime import datetime, timedelta
from io import BytesIO
from flask import Blueprint, request, jsonify, send_file
from flask_jwt_extended import jwt_required
from sqlalchemy import func
import pandas as pd

from models import db, ProductPrice, ProductCurrentPrice, CurrentPriceHistory, UnifiedProduct
from utils.logger import log_event
from services.price_service import fetch_product_prices

price_bp = Blueprint('price', __name__)


# ========== РУЧНОЕ ОБНОВЛЕНИЕ ЦЕН ==========

@price_bp.route('/update-prices', methods=['GET'])
@jwt_required()
def update_prices_endpoint():
    """Ручной запуск обновления цен товаров"""
    try:
        log_event('INFO', 'update_prices_endpoint', 'Ручной запуск обновления цен')
        fetch_product_prices()
        return jsonify({"status": "Product prices update started"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ========== ЦЕНЫ ТОВАРОВ (ProductPrice) ==========

@price_bp.route('/product-prices', methods=['GET'])
@jwt_required()
def get_product_prices():
    """
    Получение цен товаров.
    Параметры:
    - latest=true (по умолчанию) – только последние цены для каждой пары (nm_id, size_id)
    - latest=false – все исторические записи
    - nm_id, vendor_code, size_id – фильтры
    """
    start_time = time.time()
    method_name = "get_product_prices"

    try:
        log_event('INFO', method_name, 'Запрос цен товаров')

        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 100, type=int)
        nm_id = request.args.get('nm_id', type=int)
        vendor_code = request.args.get('vendor_code')
        size_id = request.args.get('size_id', type=int)
        latest = request.args.get('latest', 'true').lower() == 'true'

        if latest:
            subquery = db.session.query(
                ProductPrice.nm_id,
                ProductPrice.size_id,
                db.func.max(ProductPrice.updated_at).label('max_updated')
            ).group_by(ProductPrice.nm_id, ProductPrice.size_id).subquery()

            query = db.session.query(ProductPrice).join(
                subquery,
                db.and_(
                    ProductPrice.nm_id == subquery.c.nm_id,
                    ProductPrice.size_id == subquery.c.size_id,
                    ProductPrice.updated_at == subquery.c.max_updated
                )
            )
        else:
            query = ProductPrice.query

        if nm_id:
            query = query.filter(ProductPrice.nm_id == nm_id)
        if vendor_code:
            query = query.filter(ProductPrice.vendor_code.ilike(f'%{vendor_code}%'))
        if size_id:
            query = query.filter(ProductPrice.size_id == size_id)

        query = query.order_by(ProductPrice.nm_id, ProductPrice.size_id, ProductPrice.updated_at.desc())

        pagination = query.paginate(page=page, per_page=per_page, error_out=False)

        result = {
            'data': [price.to_dict() for price in pagination.items],
            'pagination': {
                'page': pagination.page,
                'per_page': pagination.per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            },
            'mode': 'latest' if latest else 'all'
        }

        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат цен',
                 {'records': len(pagination.items), 'duration_ms': duration, 'latest': latest})
        return jsonify(result)

    except Exception as e:
        log_event('ERROR', method_name, 'Ошибка при получении цен', {'error': str(e)})
        return jsonify({"error": str(e)}), 500


@price_bp.route('/product-prices/history/<int:nm_id>', methods=['GET'])
@jwt_required()
def get_product_price_history(nm_id):
    """
    История цен для конкретного товара.
    Параметры:
    - size_id (опционально) – если не указан, возвращает все размеры.
    - limit (по умолчанию 100) – количество последних записей.
    """
    try:
        size_id = request.args.get('size_id', type=int)
        limit = request.args.get('limit', 100, type=int)

        query = ProductPrice.query.filter(ProductPrice.nm_id == nm_id)
        if size_id:
            query = query.filter(ProductPrice.size_id == size_id)

        records = query.order_by(ProductPrice.updated_at.desc()).limit(limit).all()

        return jsonify({
            'nm_id': nm_id,
            'size_id': size_id,
            'history': [r.to_dict() for r in records],
            'total': len(records)
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@price_bp.route('/product-prices/parquet', methods=['GET'])
@jwt_required()
def export_product_prices_parquet():
    """
    Экспорт цен товаров в Parquet.
    Параметры: nm_id, vendor_code, latest (по умолчанию true)
    """
    start_time = time.time()
    method_name = "export_product_prices_parquet"

    try:
        nm_id = request.args.get('nm_id', type=int)
        vendor_code = request.args.get('vendor_code')
        latest = request.args.get('latest', 'true').lower() == 'true'

        if latest:
            subquery = db.session.query(
                ProductPrice.nm_id,
                ProductPrice.size_id,
                db.func.max(ProductPrice.updated_at).label('max_updated')
            ).group_by(ProductPrice.nm_id, ProductPrice.size_id).subquery()

            query = db.session.query(ProductPrice).join(
                subquery,
                db.and_(
                    ProductPrice.nm_id == subquery.c.nm_id,
                    ProductPrice.size_id == subquery.c.size_id,
                    ProductPrice.updated_at == subquery.c.max_updated
                )
            )
        else:
            query = ProductPrice.query

        if nm_id:
            query = query.filter(ProductPrice.nm_id == nm_id)
        if vendor_code:
            query = query.filter(ProductPrice.vendor_code.ilike(f'%{vendor_code}%'))

        records = query.all()
        if not records:
            return jsonify({"error": "Нет данных для экспорта"}), 404

        data = [r.to_dict() for r in records]
        df = pd.DataFrame(data)

        for col in ['price', 'discounted_price', 'club_discounted_price']:
            df[col] = pd.to_numeric(df[col], errors='coerce')
        for col in ['discount', 'club_discount']:
            df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0).astype(int)

        buffer = BytesIO()
        df.to_parquet(buffer, index=False, compression='snappy')
        buffer.seek(0)

        filename = f"product_prices_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.parquet"

        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Экспорт цен в Parquet',
                 {'records': len(records), 'duration_ms': duration})

        return send_file(
            buffer,
            as_attachment=True,
            download_name=filename,
            mimetype='application/octet-stream'
        )

    except Exception as e:
        log_event('ERROR', method_name, 'Ошибка экспорта Parquet', {'error': str(e)})
        return jsonify({"error": str(e)}), 500


@price_bp.route('/product-prices/history/parquet', methods=['GET'])
@jwt_required()
def export_product_price_history_parquet():
    """
    Экспорт исторических данных скидок в Parquet.
    Возвращает колонки: nm_id, discount, updated_at
    Параметр опциональный: nm_id (фильтр по товару)
    """
    start_time = time.time()
    method_name = "export_product_price_history_parquet"
    
    try:
        nm_id = request.args.get('nm_id', type=int)
        
        query = db.session.query(
            ProductPrice.nm_id,
            ProductPrice.discount,
            ProductPrice.updated_at
        )
        
        if nm_id:
            query = query.filter(ProductPrice.nm_id == nm_id)
        
        query = query.order_by(ProductPrice.nm_id, ProductPrice.updated_at)
        
        records = query.all()
        if not records:
            return jsonify({"error": "Нет данных для экспорта"}), 404
        
        data = [{'nm_id': r.nm_id, 'discount': r.discount, 'updated_at': r.updated_at} for r in records]
        df = pd.DataFrame(data)
        
        df['nm_id'] = df['nm_id'].astype(int)
        df['discount'] = pd.to_numeric(df['discount'], errors='coerce').fillna(0).astype(int)
        df['updated_at'] = pd.to_datetime(df['updated_at'])
        
        buffer = BytesIO()
        df.to_parquet(buffer, index=False, compression='snappy')
        buffer.seek(0)
        
        filename = f"price_history_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.parquet"
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Экспорт истории скидок в Parquet',
                  {'records': len(records), 'nm_id': nm_id, 'duration_ms': duration})
        
        return send_file(
            buffer,
            as_attachment=True,
            download_name=filename,
            mimetype='application/octet-stream'
        )
        
    except Exception as e:
        log_event('ERROR', method_name, 'Ошибка экспорта истории скидок', {'error': str(e)})
        return jsonify({"error": str(e)}), 500


@price_bp.route('/product-prices/history/json', methods=['GET'])
@jwt_required()
def get_price_history_json():
    """
    Возвращает JSON-массив с историей скидок:
    [{"nm_id": 123, "discount": 5, "updated_at": "2026-04-29T10:00:00"}, ...]
    Параметры: ?nm_id=123 (опционально)
    """
    try:
        query = db.session.query(ProductPrice.nm_id, ProductPrice.discount, ProductPrice.updated_at)
        nm_id = request.args.get('nm_id', type=int)
        if nm_id:
            query = query.filter(ProductPrice.nm_id == nm_id)
        records = query.order_by(ProductPrice.updated_at).all()
        data = [{'nm_id': r.nm_id, 'discount': r.discount, 'updated_at': r.updated_at.isoformat()} for r in records]
        return jsonify(data)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@price_bp.route('/product-prices/discount-history/<int:nm_id>', methods=['GET'])
@jwt_required()
def get_discount_history(nm_id):
    """
    Возвращает историю скидок для товара за последние 21 день.
    Группировка по дням: для каждого дня берётся последняя запись (по updated_at)
    """
    try:
        subq = db.session.query(
            ProductPrice.nm_id,
            func.date(ProductPrice.updated_at).label('day'),
            func.max(ProductPrice.updated_at).label('max_updated')
        ).filter(ProductPrice.nm_id == nm_id).group_by(func.date(ProductPrice.updated_at)).subquery()

        query = db.session.query(ProductPrice).join(
            subq,
            db.and_(
                ProductPrice.nm_id == subq.c.nm_id,
                ProductPrice.updated_at == subq.c.max_updated
            )
        ).order_by(ProductPrice.updated_at.desc()).limit(21)

        records = query.all()
        history = []
        for r in records:
            if r.discount is not None:
                history.append({
                    'date': r.updated_at.date().isoformat(),
                    'discount': r.discount
                })
        history.reverse()
        return jsonify({'nm_id': nm_id, 'history': history})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@price_bp.route('/product-prices/csv', methods=['GET'])
@jwt_required()
def export_product_prices_csv():
    """
    Экспорт цен товаров в CSV.
    Параметры:
    - nm_id (опционально, int)
    - vendor_code (опционально, str, частичное совпадение)
    - size_id (опционально, int)
    - date_from (опционально, YYYY-MM-DD или ISO datetime)
    - date_to (опционально, YYYY-MM-DD или ISO datetime)
    - latest (по умолчанию false) – если true, только последние цены для пары (nm_id, size_id)
    - limit (по умолчанию 100000) – максимальное количество записей
    """
    start_time = time.time()
    method_name = "export_product_prices_csv"

    try:
        log_event('INFO', method_name, 'Экспорт цен товаров в CSV')

        nm_id = request.args.get('nm_id', type=int)
        vendor_code = request.args.get('vendor_code')
        size_id = request.args.get('size_id', type=int)
        date_from = request.args.get('date_from')
        date_to = request.args.get('date_to')
        latest = request.args.get('latest', 'false').lower() == 'true'
        limit = request.args.get('limit', 100000, type=int)

        if limit > 500000:
            limit = 500000

        if latest:
            subq = db.session.query(
                ProductPrice.nm_id,
                ProductPrice.size_id,
                db.func.max(ProductPrice.updated_at).label('max_updated')
            ).group_by(ProductPrice.nm_id, ProductPrice.size_id).subquery()

            query = db.session.query(ProductPrice).join(
                subq,
                db.and_(
                    ProductPrice.nm_id == subq.c.nm_id,
                    ProductPrice.size_id == subq.c.size_id,
                    ProductPrice.updated_at == subq.c.max_updated
                )
            )
        else:
            query = ProductPrice.query

        if nm_id:
            query = query.filter(ProductPrice.nm_id == nm_id)
        if vendor_code:
            query = query.filter(ProductPrice.vendor_code.ilike(f'%{vendor_code}%'))
        if size_id:
            query = query.filter(ProductPrice.size_id == size_id)
        if date_from:
            try:
                date_from_dt = datetime.fromisoformat(date_from.replace('Z', '+00:00'))
                query = query.filter(ProductPrice.updated_at >= date_from_dt)
            except:
                try:
                    date_from_dt = datetime.strptime(date_from, '%Y-%m-%d')
                    query = query.filter(ProductPrice.updated_at >= date_from_dt)
                except:
                    pass
        if date_to:
            try:
                date_to_dt = datetime.fromisoformat(date_to.replace('Z', '+00:00'))
                date_to_dt = date_to_dt.replace(hour=23, minute=59, second=59)
                query = query.filter(ProductPrice.updated_at <= date_to_dt)
            except:
                try:
                    date_to_dt = datetime.strptime(date_to, '%Y-%m-%d')
                    date_to_dt = date_to_dt.replace(hour=23, minute=59, second=59)
                    query = query.filter(ProductPrice.updated_at <= date_to_dt)
                except:
                    pass

        query = query.order_by(ProductPrice.nm_id, ProductPrice.size_id, ProductPrice.updated_at.desc())
        records = query.limit(limit).all()

        if not records:
            return jsonify({"error": "Нет данных для экспорта"}), 404

        data = [r.to_dict() for r in records]
        df = pd.DataFrame(data)

        for col in ['price', 'discounted_price', 'club_discounted_price']:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors='coerce')
        for col in ['discount', 'club_discount']:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0).astype(int)
        if 'updated_at' in df.columns:
            df['updated_at'] = pd.to_datetime(df['updated_at'])

        output = BytesIO()
        df.to_csv(output, index=False, encoding='utf-8-sig')
        output.seek(0)

        filename = f"product_prices_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.csv"

        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Экспорт цен в CSV завершён',
                  {'records': len(records), 'duration_ms': duration})

        return send_file(
            output,
            as_attachment=True,
            download_name=filename,
            mimetype='text/csv'
        )

    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка экспорта цен в CSV',
                  {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500


# ========== АКТУАЛЬНЫЕ ЦЕНЫ (ProductCurrentPrice) ==========

@price_bp.route('/current-prices', methods=['GET'])
@jwt_required()
def get_current_prices():
    """Возвращает актуальные цены товаров с пагинацией и фильтром по nm_id"""
    start_time = time.time()
    method_name = "get_current_prices"
    try:
        log_event('INFO', method_name, 'Запрос актуальных цен')
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 3000, type=int)
        nm_id = request.args.get('nm_id', type=int)

        query = ProductCurrentPrice.query
        if nm_id:
            query = query.filter(ProductCurrentPrice.nm_id == nm_id)

        query = query.order_by(ProductCurrentPrice.last_updated.desc())

        pagination = query.paginate(page=page, per_page=per_page, error_out=False)
        items = [item.to_dict() for item in pagination.items]

        result = {
            'data': items,
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            }
        }
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Возвращено {len(items)} записей', duration_ms=duration)
        return jsonify(result)
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, str(e), duration_ms=duration)
        return jsonify({'error': str(e)}), 500


# ========== ИСТОРИЯ ЦЕН (CurrentPriceHistory) ==========

@price_bp.route('/current-price-history', methods=['GET'])
@jwt_required()
def get_current_price_history():
    """
    Получить историю цен (снэпшоты) с пагинацией и фильтром по nm_id.
    Параметры: page, per_page, nm_id, date_from, date_to
    """
    start_time = time.time()
    method_name = "get_current_price_history"
    try:
        log_event('INFO', method_name, 'Запрос истории цен')
        
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 15000, type=int)
        nm_id = request.args.get('nm_id', type=int)
        date_from = request.args.get('date_from')
        date_to = request.args.get('date_to')
        
        query = CurrentPriceHistory.query
        
        if nm_id:
            query = query.filter(CurrentPriceHistory.nm_id == nm_id)
        if date_from:
            try:
                date_from_dt = datetime.fromisoformat(date_from.replace('Z', '+00:00'))
                query = query.filter(CurrentPriceHistory.created_at >= date_from_dt)
            except:
                pass
        if date_to:
            try:
                date_to_dt = datetime.fromisoformat(date_to.replace('Z', '+00:00'))
                query = query.filter(CurrentPriceHistory.created_at <= date_to_dt)
            except:
                pass
        
        query = query.order_by(CurrentPriceHistory.created_at.desc())
        pagination = query.paginate(page=page, per_page=per_page, error_out=False)
        items = [item.to_dict() for item in pagination.items]
        
        result = {
            'data': items,
            'pagination': {
                'page': pagination.page,
                'per_page': pagination.per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            },
            'filters': {
                'nm_id': nm_id,
                'date_from': date_from,
                'date_to': date_to
            }
        }
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Возвращено {len(items)} записей', duration_ms=duration)
        return jsonify(result)
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, str(e), duration_ms=duration)
        return jsonify({'error': str(e)}), 500


@price_bp.route('/current-price-history/csv', methods=['GET'])
@jwt_required()
def export_current_price_history_csv():
    """
    Экспорт истории цен в CSV с агрегацией по дням (минимальная цена за день).
    Параметры:
        nm_id (опционально) – фильтр по товару
        days (опционально, по умолчанию 21) – сколько последних дней включительно
        date_from, date_to (опционально) – явный диапазон (YYYY-MM-DD)
    Возвращает CSV с колонками: nm_id, date, min_price
    """
    start_time = time.time()
    method_name = "export_current_price_history_csv_aggregated"
    try:
        log_event('INFO', method_name, 'Экспорт агрегированной истории цен в CSV')

        nm_id = request.args.get('nm_id', type=int)
        days = request.args.get('days', 21, type=int)
        date_from = request.args.get('date_from')
        date_to = request.args.get('date_to')

        query = db.session.query(
            CurrentPriceHistory.nm_id,
            func.date(CurrentPriceHistory.created_at).label('date'),
            func.min(CurrentPriceHistory.price).label('min_price')
        )

        if nm_id:
            query = query.filter(CurrentPriceHistory.nm_id == nm_id)

        if date_from and date_to:
            try:
                from_dt = datetime.strptime(date_from, '%Y-%m-%d')
                to_dt = datetime.strptime(date_to, '%Y-%m-%d')
                query = query.filter(
                    CurrentPriceHistory.created_at >= from_dt,
                    CurrentPriceHistory.created_at <= to_dt + timedelta(days=1)
                )
            except:
                log_event('WARNING', method_name, 'Неверный формат date_from/date_to, используем days')
                days = 21
                date_from = None
                date_to = None

        if not date_from and days:
            cutoff = datetime.utcnow() - timedelta(days=days-1)
            query = query.filter(CurrentPriceHistory.created_at >= cutoff)

        query = query.group_by(
            CurrentPriceHistory.nm_id,
            func.date(CurrentPriceHistory.created_at)
        ).order_by(
            CurrentPriceHistory.nm_id,
            func.date(CurrentPriceHistory.created_at)
        )

        records = query.all()
        if not records:
            return jsonify({"error": "Нет данных для экспорта"}), 404

        data = [{'nm_id': r.nm_id, 'date': r.date.isoformat(), 'min_price': r.min_price} for r in records]
        df = pd.DataFrame(data)
        df['nm_id'] = df['nm_id'].astype(int)
        df['min_price'] = pd.to_numeric(df['min_price'])

        output = BytesIO()
        df.to_csv(output, index=False, encoding='utf-8-sig')
        output.seek(0)

        filename = f"price_history_aggregated_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.csv"

        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Экспортировано {len(records)} записей (агрегированных по дням)',
                  duration_ms=duration)

        return send_file(
            output,
            as_attachment=True,
            download_name=filename,
            mimetype='text/csv'
        )

    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, str(e), duration_ms=duration)
        return jsonify({'error': str(e)}), 500


@price_bp.route('/current-price-history/parquet', methods=['GET'])
@jwt_required()
def export_current_price_history_parquet():
    """
    Экспорт всей истории цен в формате Parquet.
    Параметры: nm_id (опционально), date_from, date_to
    """
    start_time = time.time()
    method_name = "export_current_price_history_parquet"
    try:
        log_event('INFO', method_name, 'Экспорт истории цен в Parquet')
        
        nm_id = request.args.get('nm_id', type=int)
        date_from = request.args.get('date_from')
        date_to = request.args.get('date_to')
        
        query = CurrentPriceHistory.query
        
        if nm_id:
            query = query.filter(CurrentPriceHistory.nm_id == nm_id)
        if date_from:
            try:
                date_from_dt = datetime.fromisoformat(date_from.replace('Z', '+00:00'))
                query = query.filter(CurrentPriceHistory.created_at >= date_from_dt)
            except:
                pass
        if date_to:
            try:
                date_to_dt = datetime.fromisoformat(date_to.replace('Z', '+00:00'))
                query = query.filter(CurrentPriceHistory.created_at <= date_to_dt)
            except:
                pass
        
        query = query.order_by(CurrentPriceHistory.created_at)
        records = query.all()
        
        if not records:
            return jsonify({"error": "Нет данных для экспорта"}), 404
        
        data = [{'nm_id': r.nm_id, 'price': r.price, 'created_at': r.created_at} for r in records]
        df = pd.DataFrame(data)
        df['nm_id'] = df['nm_id'].astype(int)
        df['price'] = pd.to_numeric(df['price'])
        df['created_at'] = pd.to_datetime(df['created_at'])
        
        buffer = BytesIO()
        df.to_parquet(buffer, index=False, compression='snappy')
        buffer.seek(0)
        
        filename = f"current_price_history_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.parquet"
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, f'Экспортировано {len(records)} записей', duration_ms=duration)
        
        return send_file(
            buffer,
            as_attachment=True,
            download_name=filename,
            mimetype='application/octet-stream'
        )
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, str(e), duration_ms=duration)
        return jsonify({'error': str(e)}), 500


# ========== ДИАГНОСТИКА СТАТУСА ОБНОВЛЕНИЯ ЦЕН ==========

@price_bp.route('/debug/price-updater-status', methods=['GET'])
@jwt_required()
def price_updater_status():
    from models import ProductCurrentPrice
    total = ProductCurrentPrice.query.count()
    last = ProductCurrentPrice.query.order_by(ProductCurrentPrice.last_updated.desc()).first()
    return jsonify({
        'table_exists': True,
        'total_records': total,
        'last_record': last.to_dict() if last else None,
        'thread_alive': hasattr(app, '_price_thread_started') and app._price_thread_started,
        'unified_products_count': UnifiedProduct.query.count()
    })