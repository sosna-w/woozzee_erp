import sys
import json
from datetime import datetime
from models import db, Log

def log_event(level, method, event, details=None, duration_ms=None, nm_id=None,
              request_url=None, response_status=None, records_processed=None):
    try:
        log = Log(
            level=level,
            method=method,
            event=event,
            details=json.dumps(details, ensure_ascii=False) if details else None,
            duration_ms=duration_ms,
            nm_id=nm_id,
            request_url=request_url,
            response_status=response_status,
            records_processed=records_processed
        )
        db.session.add(log)
        db.session.commit()
    except Exception as e:
        print(f"Ошибка при логировании в PostgreSQL: {e}", file=sys.stderr)
        # Запасной вариант - запись в файл
        try:
            with open('log_errors.txt', 'a') as f:
                f.write(f"{datetime.utcnow().isoformat()} - {level} - {method} - {event} - {str(e)[:200]}\n")
        except:
            pass