import 'dart:convert';
import 'package:http/http.dart' as http;

class StocksManager {
  static final StocksManager _instance = StocksManager._internal();
  factory StocksManager() => _instance;
  StocksManager._internal();

  // Кэш: ключ = nmID, значение = { 'fbs': int, 'fbo': int }
  final Map<int, Map<String, int>> _cache = {};
  bool _isLoaded = false;

  /// Загружает все остатки с сервера
  Future<void> loadAllStocks() async {
    if (_isLoaded) return;

    try {
      final response = await http.get(
        Uri.parse('https://hide_domain.com/unified-products?per_page=10000'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> products = data['unified_products'] ?? [];

        _cache.clear();
        for (var item in products) {
          final nmId = item['nm_id'] as int?;
          final fbs = item['fbs_quantity'] as int? ?? 0;
          final fbo = item['total_quantity'] as int? ?? 0;
          if (nmId != null) {
            _cache[nmId] = {
              'fbs': fbs,
              'fbo': fbo,
            };
          }
        }
        _isLoaded = true;
        print('✅ StocksManager: загружено ${_cache.length} записей');
      } else {
        print('❌ StocksManager: ошибка ${response.statusCode}');
      }
    } catch (e) {
      print('❌ StocksManager: исключение $e');
    }
  }

  /// Получить остатки FBS для товара
  int getFBSQuantity(int nmId) {
    return _cache[nmId]?['fbs'] ?? 0;
  }

  /// Получить остатки FBO для товара
  int getFBOQuantity(int nmId) {
    return _cache[nmId]?['fbo'] ?? 0;
  }

  /// Проверка, загружены ли данные
  bool get isLoaded => _isLoaded;
}