// unified_products_data_model.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Модель для хранения всех данных товаров в памяти
class UnifiedProductsDataModel {
  static final UnifiedProductsDataModel _instance = 
      UnifiedProductsDataModel._internal();
  
  factory UnifiedProductsDataModel() => _instance;
  UnifiedProductsDataModel._internal();

  // Основное хранилище данных в памяти
  final Map<int, Map<String, dynamic>> _productsData = {};
  
  // Флаг загрузки
  bool _isInitialized = false;
  
  // Базовый URL API
  static const String _baseUrl = 'https://hide_domain.com';

  /// Инициализация модели (загрузка всех данных)
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      print('🔄 Загрузка всех данных товаров для виджетов...');
      
      final response = await http.get(
        Uri.parse('$_baseUrl/unified-products?per_page=10000'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final products = data['unified_products'] as List<dynamic>?;

        if (products != null) {
          _productsData.clear();
          
          for (final product in products) {
            try {
              final productMap = product as Map<String, dynamic>;
              final nmId = _parseNmId(productMap['nm_id']);
              
              if (nmId > 0) {
                // Сохраняем теги как есть
                final tags = productMap['tags'] as List<dynamic>? ?? [];
                
                _productsData[nmId] = {
                  'nm_id': productMap['nm_id']?.toString() ?? '',
                  'vendor_code': productMap['vendor_code']?.toString() ?? '',
                  'barcode': productMap['barcode']?.toString() ?? '',
                  'title': productMap['title']?.toString() ?? '',
                  'total_quantity': productMap['total_quantity']?.toString() ?? '0',
                  'fbs_quantity': productMap['fbs_quantity']?.toString() ?? '0',
                  'tags': tags, // Добавляем теги
                };
              }
            } catch (e) {
              // Пропускаем некорректные записи
            }
          }
          
          _isInitialized = true;
          print('✅ Загружено ${_productsData.length} товаров для виджетов');
        }
      }
    } catch (e) {
      print('❌ Ошибка загрузки данных для виджетов: $e');
    }
  }

  /// Получить данные товара по nmId
  Map<String, dynamic> getProductData(int nmId) {
    return _productsData[nmId] ?? _getDefaultData();
  }

  /// Получить все загруженные данные
  Map<int, Map<String, dynamic>> getAllProductsData() {
    return Map.from(_productsData);
  }

  /// Обновить данные
  Future<void> refresh() async {
    _isInitialized = false;
    await initialize();
  }

  /// Проверить инициализацию
  bool get isInitialized => _isInitialized;

  /// Данные по умолчанию
  Map<String, dynamic> _getDefaultData() {
    return {
      'nm_id': '',
      'vendor_code': '',
      'barcode': '',
      'title': '',
      'total_quantity': '0',
      'fbs_quantity': '0',
      'tags': [], // Теги по умолчанию
    };
  }

  /// Парсинг nmId из различных форматов
  int _parseNmId(dynamic nmId) {
    if (nmId == null) return 0;
    
    if (nmId is String) {
      return int.tryParse(nmId) ?? 0;
    } else if (nmId is int) {
      return nmId;
    } else if (nmId is num) {
      return nmId.toInt();
    }
    
    return 0;
  }
}