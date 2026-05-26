import json
import time
from flask import Blueprint, jsonify
from flask_jwt_extended import jwt_required
from models import Product
from utils.logger import log_event

tags_bp = Blueprint('tags', __name__)


@tags_bp.route('/tags', methods=['GET'])
@jwt_required()
def get_tags():
    start_time = time.time()
    method_name = "get_tags"
    
    try:
        log_event('INFO', method_name, 'Запрос уникальных тегов')
        
        products_with_tags = Product.query.filter(Product.tags.isnot(None)).filter(Product.tags != '').all()
        
        unique_tags = set()
        
        for product in products_with_tags:
            try:
                tags_data = json.loads(product.tags)
                for tag in tags_data:
                    if isinstance(tag, dict) and 'name' in tag:
                        unique_tags.add(json.dumps({
                            'name': tag['name'],
                            'color': tag.get('color', 'D1CFD7')
                        }, sort_keys=True))
            except json.JSONDecodeError:
                continue
        
        tags_list = [json.loads(tag_str) for tag_str in unique_tags]
        
        duration = (time.time() - start_time) * 1000
        log_event('INFO', method_name, 'Успешный возврат уникальных тегов',
                 {'tags_count': len(tags_list)}, duration_ms=duration)
        
        return jsonify(tags_list)
        
    except Exception as e:
        duration = (time.time() - start_time) * 1000
        log_event('ERROR', method_name, 'Ошибка при получении тегов',
                 {'error': str(e)}, duration_ms=duration)
        return jsonify({"error": str(e)}), 500