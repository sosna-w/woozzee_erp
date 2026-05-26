// lib/services/search_query_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Данные текущего дня (кэш в памяти)
class SearchQueryCurrent {
  final int totalFrequency;
  final Map<String, int> searchTexts;
  final DateTime reportDate;
  final DateTime lastUpdated;

  SearchQueryCurrent({
    required this.totalFrequency,
    required this.searchTexts,
    required this.reportDate,
    required this.lastUpdated,
  });
}

/// Сервис для работы с поисковыми запросами (отдельная DuckDB база)
class SearchQueryService {
  static final SearchQueryService _instance = SearchQueryService._internal();
  factory SearchQueryService() => _instance;
  SearchQueryService._internal();

  Database? _db;
  Connection? _conn;
  bool _initialized = false;

  // Кэш текущих данных (сегодня)
  final Map<int, SearchQueryCurrent> _currentCache = {};

  /// Инициализация (открывает БД, создаёт таблицу)
  Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = '${dir.path}/search_queries.duckdb';
      _db = await duckdb.open(dbPath);
      _conn = await duckdb.connect(_db!);
      await _conn!.execute('''
        CREATE TABLE IF NOT EXISTS search_history (
          nm_id INTEGER,
          report_date DATE,
          total_frequency INTEGER,
          search_texts JSON,
          PRIMARY KEY (nm_id, report_date)
        )
      ''');
      _initialized = true;
      print('✅ SearchQueryService инициализирован');
    } catch (e) {
      print('❌ Ошибка инициализации SearchQueryService: $e');
      rethrow;
    }
  }

  /// Загрузить историю из Parquet-файла с сервера (перезаписывает таблицу)
  /// Загрузить историю из Parquet-файла с сервера (всегда перезаписывает таблицу)
  /// Синхронизирует локальную базу с сервером.
  /// Если forceReload = true – полностью перезагружает все доступные даты (очищает таблицу).
  /// Иначе догружает только те даты, которых ещё нет локально.
  Future<void> loadHistory({bool forceReload = true}) async {
    if (!_initialized) await init();

    final serverDatesSet = await fetchAvailableDates();
    if (serverDatesSet.isEmpty) {
      print('⚠️ На сервере нет ни одной даты с данными.');
      return;
    }

    if (forceReload) {
      print('🔄 Полная перезагрузка истории (forceReload = true)');
      await _conn!.execute('DELETE FROM search_history');
      for (final date in serverDatesSet) {
        await downloadAndInsertParquetForDate(date);
      }
      print('✅ Полная перезагрузка завершена');
      return;
    }

    // Инкрементальная синхронизация
    final localDatesSet = await getLocalDates();
    final missingDates = serverDatesSet.difference(localDatesSet);
    if (missingDates.isEmpty) {
      print('✅ Локальные данные уже актуальны, новых дат нет');
      return;
    }

    print('🔄 Обнаружено ${missingDates.length} новых дат: $missingDates');
    for (final date in missingDates) {
      await downloadAndInsertParquetForDate(date);
    }
    print('✅ Инкрементальная синхронизация завершена');
  }

  /// Запрос доступных дат на сервере
  Future<Set<String>> fetchAvailableDates() async {
    try {
      final response = await http.get(
        Uri.parse('https://hide_domain.com/search-texts/available-dates'),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final datesList = data['dates'] as List<dynamic>?;
        if (datesList != null) {
          return datesList.map((e) => e['date'] as String).toSet();
        }
      } else {
        print('❌ Ошибка получения списка дат: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Исключение при получении списка дат: $e');
    }
    return {};
  }

  /// Получить даты, уже присутствующие в локальной таблице
  Future<Set<String>> getLocalDates() async {
    if (!_initialized) await init();
    final result = await _conn!.query('SELECT DISTINCT report_date FROM search_history');
    final rows = result.fetchAll();
    await result.dispose();
    return rows.map((row) => row[0].toString()).toSet();
  }

  /// Загрузить Parquet-файл для конкретной даты и вставить в таблицу
  Future<void> downloadAndInsertParquetForDate(String date) async {
    print('🔄 Загрузка данных за $date...');
    try {
      final response = await http.get(
        Uri.parse('https://hide_domain.com/search-texts/export-daily?date=$date'),
      ).timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        print('❌ Не удалось загрузить $date: ${response.statusCode}');
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/search_$date.parquet');
      await tempFile.writeAsBytes(response.bodyBytes);

      // Удаляем старые записи только за эту дату (date)
      await _conn!.execute('DELETE FROM search_history WHERE report_date = \'$date\'');

      // ✅ Исправленный INSERT: принудительно используем $date как report_date
      await _conn!.execute('''
      INSERT INTO search_history (nm_id, report_date, total_frequency, search_texts)
      SELECT 
        nm_id,
        '$date'::DATE AS report_date,
        total_frequency,
        search_texts::JSON
      FROM read_parquet('${tempFile.path.replaceAll('\\', '/')}')
    ''');
      await tempFile.delete();
      print('✅ Данные за $date загружены');
    } catch (e) {
      print('❌ Ошибка загрузки даты $date: $e');
    }
  }


  /// Загрузить текущие данные за сегодня (кэшируются)
  Future<void> loadCurrentData() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dateStr = today.toIso8601String().split('T')[0];
      final response = await http.get(
        Uri.parse('https://hide_domain.com/search-texts?date=$dateStr'),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['data'] as List<dynamic>?;
        if (items == null) {
          print('⚠️ Нет данных в поле "data"');
          return;
        }
        _currentCache.clear();
        for (var item in items) {
          final nmId = (item['nm_id'] as num).toInt();
          final totalFreq = (item['total_frequency'] as num).toInt();
          final rawTexts = item['search_texts'];
          Map<String, int> texts = {};
          if (rawTexts is Map) {
            rawTexts.forEach((k, v) {
              texts[k] = (v as num).toInt();
            });
          } else if (rawTexts is String && rawTexts.isNotEmpty) {
            try {
              final decoded = json.decode(rawTexts);
              if (decoded is Map) {
                decoded.forEach((k, v) {
                  texts[k] = (v as num).toInt();
                });
              }
            } catch (_) {}
          }
          _currentCache[nmId] = SearchQueryCurrent(
            totalFrequency: totalFreq,
            searchTexts: texts,
            reportDate: DateTime.parse(item['report_date']),
            lastUpdated: DateTime.now(),
          );
        }
        print('✅ Загружены текущие запросы для ${_currentCache.length} товаров');
      } else {
        print('❌ Ошибка загрузки текущих данных: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Исключение при загрузке текущих данных: $e');
    }
  }

  /// Получить массив суммарных частот за последние N дней (включая сегодня).
  /// Возвращает список длиной days в порядке: день1 (самый старый), день2, ..., сегодня.
  Future<List<int>> getTotalFrequenciesForLastNDays(int nmId, int days) async {
    if (!_initialized) await init();
    if (days < 1) return [];

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final startDate = todayDate.subtract(Duration(days: days - 1));
    final endDate = todayDate;

    // Запросим значения из истории (без сегодня)
    final Map<DateTime, int> historyFreq = {};
    if (startDate.isBefore(endDate)) {
      final startStr = startDate.toIso8601String().split('T')[0];
      final endStr = endDate.toIso8601String().split('T')[0];
      final stmt = await _conn!.prepare('''
        SELECT report_date, total_frequency 
        FROM search_history 
        WHERE nm_id = ? AND report_date BETWEEN ? AND ?
      ''');
      stmt.bind(nmId, 1);
      stmt.bind(startStr, 2);
      stmt.bind(endStr, 3);
      final result = await stmt.execute();
      final rows = result.fetchAll();
      await result.dispose();
      await stmt.dispose();
      for (var row in rows) {
        final dt = DateTime.parse(row[0].toString());
        final freq = (row[1] as num).toInt();
        historyFreq[dt] = freq;
      }
    }

    // Формируем результат: от startDate до endDate (включительно)
    final List<int> result = [];
    for (int i = 0; i < days; i++) {
      final date = startDate.add(Duration(days: i));
      int val = 0;
      if (date == todayDate) {
        // сегодня – из кэша
        val = _currentCache[nmId]?.totalFrequency ?? 0;
      } else {
        val = historyFreq[date] ?? 0;
      }
      result.add(val);
    }
    return result;
  }

  /// Получить словарь ключевых запросов для конкретного дня.
  Future<Map<String, int>?> getSearchTextsForDay(int nmId, DateTime date) async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final targetDate = DateTime(date.year, date.month, date.day);

    if (targetDate == todayDate) {
      // Сегодняшний день – из кэша
      return _currentCache[nmId]?.searchTexts;
    } else {
      // История
      if (!_initialized) await init();
      final dateStr = targetDate.toIso8601String().split('T')[0];
      final stmt = await _conn!.prepare('''
        SELECT search_texts FROM search_history 
        WHERE nm_id = ? AND report_date = ?
      ''');
      stmt.bind(nmId, 1);
      stmt.bind(dateStr, 2);
      final result = await stmt.execute();
      final rows = result.fetchAll();
      await result.dispose();
      await stmt.dispose();
      if (rows.isEmpty) return null;
      final jsonStr = rows[0][0].toString();
      if (jsonStr == 'null') return null;
      try {
        final decoded = json.decode(jsonStr);
        if (decoded is Map) {
          final Map<String, int> texts = {};
          decoded.forEach((k, v) {
            texts[k] = (v as num).toInt();
          });
          return texts;
        }
      } catch (e) {
        print('Ошибка парсинга search_texts для $nmId на дату $dateStr: $e');
      }
      return null;
    }
  }


  /// Закрыть соединение (вызывать при завершении приложения)
  Future<void> close() async {
    if (_conn != null) {
      await _conn!.dispose();
      _conn = null;
    }
    if (_db != null) {
      await _db!.dispose();
      _db = null;
    }
    _initialized = false;
    print('🔌 SearchQueryService закрыт');
  }
}