import time
import threading
import json
import requests
from pathlib import Path
from datetime import datetime, timedelta
import pyarrow as pa
import pyarrow.parquet as pq

from utils.logger import log_event
from utils.token_manager import get_api_key
from models import db, ProductActualSearchText, UnifiedProduct


class SearchTextRateLimiter:
    """Лимитер 3 запроса/мин (общий для всех вызовов)"""
    def __init__(self):
        self.lock = threading.Lock()
        self.request_count = 0
        self.first_request_time = 0

    def wait_if_needed(self):
        with self.lock:
            now = time.time()
            if self.first_request_time == 0:
                self.first_request_time = now
                self.request_count = 1
                return
            elapsed = now - self.first_request_time
            if self.request_count >= 3 and elapsed < 60:
                sleep_time = 60 - elapsed + 0.5
                log_event('DEBUG', 'SearchTextRateLimiter', f'Лимит, пауза {sleep_time:.2f}с')
                time.sleep(sleep_time)
                self.first_request_time = time.time()
                self.request_count = 1
            else:
                self.request_count += 1

    def handle_429(self, headers):
        retry_after = headers.get('X-Ratelimit-Retry')
        if retry_after:
            sleep_time = int(retry_after)
            log_event('WARNING', 'SearchTextRateLimiter', f'429, ждём {sleep_time}с')
            time.sleep(sleep_time)
            return True
        return False


class SearchTextManager:
    """Управляет фоновым циклом и массовыми загрузками"""
    def __init__(self, app):
        self.app = app
        self.background_paused = False
        self.pause_lock = threading.Lock()
        self.limiter = SearchTextRateLimiter()
        self.stop_event = threading.Event()
        self.background_thread = None
        self._started = False
        self._current_load_date = None      # str в формате YYYY-MM-DD
        self._current_load_completed = False

    def pause_background(self):
        with self.pause_lock:
            self.background_paused = True
            log_event('INFO', 'SearchTextManager', 'Фоновый цикл поставлен на паузу')

    def resume_background(self):
        with self.pause_lock:
            self.background_paused = False
            log_event('INFO', 'SearchTextManager', 'Фоновый цикл возобновлён')

    def is_paused(self):
        with self.pause_lock:
            return self.background_paused

    def start_background(self):
        if self._started:
            return
        self.background_thread = threading.Thread(target=self._background_loop, daemon=True)
        self.background_thread.start()
        self._started = True
        log_event('INFO', 'SearchTextManager', 'Фоновый цикл запущен')

    def stop_background(self):
        self.stop_event.set()
        if self.background_thread and self.background_thread.is_alive():
            self.background_thread.join(timeout=5)
        log_event('INFO', 'SearchTextManager', 'Фоновый цикл остановлен')

    def _background_loop(self):
        """Фоновое обновление актуальных данных за сегодня (низкий приоритет)"""
        while not self.stop_event.is_set():
            if self.is_paused():
                self.stop_event.wait(5)
                continue
            with self.app.app_context():
                try:
                    msk_now = datetime.utcnow() + timedelta(hours=3)
                    report_date = msk_now.date()
                    # Выбираем 50 товаров с самой старой last_updated
                    from sqlalchemy import nullsfirst
                    subq = db.session.query(
                        ProductActualSearchText.nm_id,
                        ProductActualSearchText.last_updated
                    ).subquery()
                    query = db.session.query(UnifiedProduct.nm_id).outerjoin(
                        subq, UnifiedProduct.nm_id == subq.c.nm_id
                    ).order_by(nullsfirst(subq.c.last_updated.asc())).limit(50)
                    nm_ids = [row[0] for row in query.all()]
                    if not nm_ids:
                        self.stop_event.wait(60)
                        continue

                    batch_data = self._fetch_batch(nm_ids, report_date.isoformat())
                    if not batch_data:
                        self.stop_event.wait(30)
                        continue

                    updated = 0
                    for nm_id, data in batch_data.items():
                        existing = ProductActualSearchText.query.filter_by(
                            nm_id=nm_id, report_date=report_date
                        ).first()
                        if existing:
                            existing.total_frequency = data['total_freq']
                            existing.search_texts = json.dumps(data['texts'], ensure_ascii=False)
                            existing.last_updated = datetime.utcnow()
                        else:
                            new_rec = ProductActualSearchText(
                                nm_id=nm_id,
                                total_frequency=data['total_freq'],
                                search_texts=json.dumps(data['texts'], ensure_ascii=False),
                                report_date=report_date
                            )
                            db.session.add(new_rec)
                        updated += 1
                    db.session.commit()
                    log_event('INFO', 'background_loop', f'Обновлено {updated} товаров')
                except Exception as e:
                    log_event('ERROR', 'background_loop', str(e), {'traceback': traceback.format_exc()})
                    self.stop_event.wait(60)
            self.stop_event.wait(20)   # пауза между батчами

    def _fetch_batch(self, nm_ids_batch, report_date):
        """Общий метод запроса, использует единый лимитер"""
        if not nm_ids_batch:
            return {}
        api_key = get_api_key()
        if not api_key:
            return {}
        url = "https://seller-analytics-api.wildberries.ru/api/v2/search-report/product/search-texts"
        headers = {'Authorization': api_key, 'Content-Type': 'application/json'}
        payload = {
            "currentPeriod": {"start": report_date, "end": report_date},
            "nmIds": nm_ids_batch,
            "topOrderBy": "openCard",
            "includeSubstitutedSKUs": True,
            "includeSearchTexts": True,
            "orderBy": {"field": "openCard", "mode": "desc"},
            "limit": 100
        }
        for attempt in range(3):
            self.limiter.wait_if_needed()
            try:
                resp = requests.post(url, json=payload, headers=headers, timeout=60)
                if resp.status_code == 200:
                    items = resp.json().get('data', {}).get('items', [])
                    result = {}
                    for item in items:
                        nm = item['nmId']
                        freq = item['frequency']['current']
                        text = item['text']
                        if nm not in result:
                            result[nm] = {'total_freq': 0, 'texts': {}}
                        result[nm]['total_freq'] += freq
                        result[nm]['texts'][text] = freq
                    return result
                elif resp.status_code == 429:
                    if self.limiter.handle_429(resp.headers):
                        continue
                    else:
                        time.sleep(60)
                else:
                    log_event('ERROR', '_fetch_batch', f'Ошибка {resp.status_code}', {'text': resp.text[:200]})
                    break
            except Exception as e:
                log_event('ERROR', '_fetch_batch', str(e))
                time.sleep(5)
        return {}

    def load_history_for_date(self, target_date):
        log_event('INFO', 'load_history', f'Начало массовой загрузки за {target_date}')
        self._current_load_date = target_date
        self._current_load_completed = False

        self.pause_background()
        try:
            api_key = get_api_key()
            if not api_key:
                raise Exception('Нет токена')
            
            all_nm_ids = [row[0] for row in db.session.query(UnifiedProduct.nm_id).all()]
            if not all_nm_ids:
                log_event('WARNING', 'load_history', 'Нет товаров в UnifiedProduct')
                return 0

            SEARCH_QUERIES_DIR = Path("uploads/search_queries")
            SEARCH_QUERIES_DIR.mkdir(parents=True, exist_ok=True)

            filepath = SEARCH_QUERIES_DIR / f"search_texts_{target_date}.parquet"
            tmp_path = filepath.with_suffix('.parquet.tmp')

            schema = pa.schema([
                ('nm_id', pa.int64()),
                ('total_frequency', pa.int64()),
                ('search_texts', pa.string()),
                ('created_at', pa.string())
            ])

            writer = None
            batch_size = 50
            total_updated = 0

            for i in range(0, len(all_nm_ids), batch_size):
                batch = all_nm_ids[i:i+batch_size]
                batch_data = self._fetch_batch(batch, target_date)
                if not batch_data:
                    log_event('WARNING', 'load_history', f'Нет данных для батча {i//batch_size+1}')
                    continue

                records = []
                for nm_id, data in batch_data.items():
                    records.append({
                        'nm_id': nm_id,
                        'total_frequency': data['total_freq'],
                        'search_texts': json.dumps(data['texts'], ensure_ascii=False),
                        'created_at': datetime.utcnow().isoformat()
                    })
                    total_updated += 1

                table = pa.Table.from_pylist(records, schema=schema)
                if writer is None:
                    writer = pq.ParquetWriter(tmp_path, schema, compression='snappy')
                writer.write_table(table)
                time.sleep(0.1)

            if writer:
                writer.close()
                tmp_path.replace(filepath)
                log_event('INFO', 'load_history', f'Создан Parquet: {filepath}, записей: {total_updated}')
            else:
                log_event('WARNING', 'load_history', f'Нет данных для даты {target_date}')

            self._current_load_completed = True
            log_event('INFO', 'load_history', f'Загрузка за {target_date} завершена, сохранено {total_updated} записей')
            return total_updated

        except Exception as e:
            log_event('ERROR', 'load_history', f'Ошибка загрузки за {target_date}', {'error': str(e), 'traceback': traceback.format_exc()})
            return 0
        finally:
            self.resume_background()