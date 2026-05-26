import 'dart:convert';
import 'package:http/http.dart' as http;

// Класс для записи истории скидок
class PriceHistoryEntry {
  final int nmId;
  final int discount;
  final DateTime updatedAt;

  PriceHistoryEntry({required this.nmId, required this.discount, required this.updatedAt});

  factory PriceHistoryEntry.fromJson(Map<String, dynamic> json) {
    final discountRaw = json['discount'];
    int discountInt;
    if (discountRaw is int) {
      discountInt = discountRaw;
    } else if (discountRaw is double) {
      discountInt = discountRaw.round();
    } else if (discountRaw is String) {
      discountInt = int.tryParse(discountRaw) ?? 0;
    } else {
      discountInt = 0;
    }
    return PriceHistoryEntry(
      nmId: json['nm_id'] as int,
      discount: discountInt,
      updatedAt: DateTime.parse(json['updated_at'] + 'Z'),
    );
  }
}

// Класс для хранения агрегированной истории цен (минимальная цена за день)
class CurrentPriceHistoryEntry {
  final int nmId;
  final int price;          // минимальная цена за день
  final DateTime createdAt; // дата (UTC, начало дня)

  CurrentPriceHistoryEntry({required this.nmId, required this.price, required this.createdAt});

  // Конструктор из CSV-строки
  factory CurrentPriceHistoryEntry.fromCsvRow(String nmIdStr, String dateStr, String minPriceStr) {
    final nmId = int.tryParse(nmIdStr) ?? 0;
    // 🔥 ИСПРАВЛЕНИЕ: парсим как double, затем округляем
    final price = (double.tryParse(minPriceStr) ?? 0.0).round();
    final createdAt = DateTime.parse('${dateStr.trim()}T00:00:00Z');
    return CurrentPriceHistoryEntry(
      nmId: nmId,
      price: price,
      createdAt: createdAt,
    );
  }
}

class PriceHistoryManager {
  static const String _baseUrl = 'https://hide_domain.com';

  final Map<int, List<PriceHistoryEntry>> _discountCache = {};
  final Map<int, List<CurrentPriceHistoryEntry>> _priceCache = {};

  // --- Загрузка истории скидок (без изменений) ---
  Future<void> loadAllHistory() async {
    final url = Uri.parse('$_baseUrl/product-prices/history/json');
    final response = await http.get(url).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Ошибка загрузки истории скидок: ${response.statusCode}');
    }
    final List<dynamic> jsonList = json.decode(response.body);
    final Map<int, List<PriceHistoryEntry>> temp = {};
    for (var item in jsonList) {
      final entry = PriceHistoryEntry.fromJson(item);
      temp.putIfAbsent(entry.nmId, () => []).add(entry);
    }
    for (var entry in temp.entries) {
      entry.value.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    }
    _discountCache.clear();
    _discountCache.addAll(temp);
  }

  // --- Загрузка истории цен из CSV (агрегированной по дням) ---
  Future<void> loadAllPriceHistory({
    int? nmId,
    int days = 90,
    String? dateFrom,
    String? dateTo,
  }) async {
    final params = <String, String>{};
    if (nmId != null) params['nm_id'] = nmId.toString();
    if (days > 0 && dateFrom == null && dateTo == null) {
      params['days'] = days.toString();
    }
    if (dateFrom != null) params['date_from'] = dateFrom;
    if (dateTo != null) params['date_to'] = dateTo;

    final uri = Uri.parse('$_baseUrl/current-price-history/csv').replace(queryParameters: params);
    final response = await http.get(uri).timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception('Ошибка загрузки CSV истории цен: ${response.statusCode}');
    }

    final String csvBody = utf8.decode(response.bodyBytes);
    final lines = csvBody.split('\n');
    if (lines.length < 2) {
      _priceCache.clear();
      return;
    }

    final Map<int, List<CurrentPriceHistoryEntry>> temp = {};
    // Пропускаем заголовок (первая строка)
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final columns = line.split(',');
      if (columns.length < 3) continue;

      final nmIdStr = columns[0];
      final dateStr = columns[1];
      final minPriceStr = columns[2];

      final entry = CurrentPriceHistoryEntry.fromCsvRow(nmIdStr, dateStr, minPriceStr);
      if (entry.nmId == 0) continue;

      temp.putIfAbsent(entry.nmId, () => []).add(entry);
    }

    for (var entry in temp.entries) {
      entry.value.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    _priceCache.clear();
    _priceCache.addAll(temp);
  }

  // --- Получение истории скидок за последние N дней ---
  List<int> getDiscountsForLastNDays(int nmId, int days) {
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, now.day - days + 1);
    final entries = _discountCache[nmId];
    return _aggregateForDays(
      startDate,
      days,
      entries,
          (e) => e.updatedAt,
          (e) => e.discount,
    );
  }

  // --- Получение истории цен за последние N дней ---
  List<int> getPricesForLastNDays(int nmId, int days) {
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, now.day - days + 1);
    final entries = _priceCache[nmId];
    return _aggregateForDays(
      startDate,
      days,
      entries,
          (e) => e.createdAt,
          (e) => e.price,
    );
  }

  // Обобщённый метод агрегации по дням
  List<int> _aggregateForDays<T>(
      DateTime startDate,
      int days,
      List<T>? entries,
      DateTime Function(T) dateGetter,
      int Function(T) valueGetter,
      ) {
    if (entries == null || entries.isEmpty) {
      return List.filled(days, 0);
    }

    final Map<DateTime, int> dayToValue = {};
    for (var e in entries) {
      final utcDate = dateGetter(e);
      final localDate = utcDate.toLocal();
      final day = DateTime(localDate.year, localDate.month, localDate.day);
      dayToValue[day] = valueGetter(e);
    }

    final List<int> result = [];
    for (int i = 0; i < days; i++) {
      final currentDay = DateTime(startDate.year, startDate.month, startDate.day + i);
      result.add(dayToValue[currentDay] ?? 0);
    }
    return result;
  }

  // --- Получение списка последних N дат ---
  List<DateTime> getLastNDates(int days) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - days + 1);
    return List.generate(days, (i) => DateTime(start.year, start.month, start.day + i));
  }
}