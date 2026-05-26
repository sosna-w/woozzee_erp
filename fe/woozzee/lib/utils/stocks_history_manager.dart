import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/stocks_history_data.dart';
import 'token_manager.dart';

class StocksHistoryManager {
  static final StocksHistoryManager _instance = StocksHistoryManager._internal();
  factory StocksHistoryManager() => _instance;
  StocksHistoryManager._internal();

  final String _baseUrl = 'http://hide_domain.com';

  // Кэш для данных истории остатков
  final Map<String, List<StocksHistoryData>> _cache = {};
  final Map<String, DateTime> _cacheTimestamp = {};
  final Duration _cacheDuration = Duration(minutes: 5);

  Future<List<StocksHistoryData>> getStocksHistory({
    required int nmId,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool forceRefresh = false,
  }) async {
    final cacheKey = _generateCacheKey(nmId, dateFrom, dateTo);

    // Проверяем кэш
    if (!forceRefresh &&
        _cache.containsKey(cacheKey) &&
        _cacheTimestamp.containsKey(cacheKey)) {

      final cachedTime = _cacheTimestamp[cacheKey]!;
      if (DateTime.now().difference(cachedTime) < _cacheDuration) {
        return _cache[cacheKey]!;
      }
    }

    try {
      final token = TokenManager().getToken();
      if (token == null) {
        throw Exception('Токен не найден');
      }

      String url = '$_baseUrl/stocks-history?nm_id=$nmId&per_page=530';

      if (dateFrom != null) {
        final dateFromStr = dateFrom.toIso8601String().split('T')[0];
        url += '&date_from=$dateFromStr';
      }

      if (dateTo != null) {
        final dateToStr = dateTo.toIso8601String().split('T')[0];
        url += '&date_to=$dateToStr';
      }


      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final responseData = StocksHistoryResponse.fromJson(data);

        // Сортируем по дате (старые -> новые)
        final sortedHistory = responseData.history.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        // Кэшируем результат
        _cache[cacheKey] = sortedHistory;
        _cacheTimestamp[cacheKey] = DateTime.now();

        return sortedHistory;
      } else {
        throw Exception('Ошибка загрузки истории остатков: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Ошибка получения истории остатков: $e');
      throw e;
    }
  }

  Future<void> clearCache({int? nmId}) async {
    if (nmId != null) {
      // Удаляем кэш для конкретного товара
      final keysToRemove = _cache.keys.where((key) => key.contains('nmId=$nmId')).toList();
      for (final key in keysToRemove) {
        _cache.remove(key);
        _cacheTimestamp.remove(key);
      }
    } else {
      // Очищаем весь кэш
      _cache.clear();
      _cacheTimestamp.clear();
    }
  }

  String _generateCacheKey(int nmId, DateTime? dateFrom, DateTime? dateTo) {
    final dateFromStr = dateFrom?.toIso8601String() ?? 'null';
    final dateToStr = dateTo?.toIso8601String() ?? 'null';
    return 'nmId=$nmId|from=$dateFromStr|to=$dateToStr';
  }
}