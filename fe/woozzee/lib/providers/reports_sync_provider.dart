// lib/providers/reports_sync_provider.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/report_detail_model.dart';
import '../services/database_service.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:dart_duckdb/dart_duckdb.dart';

@immutable
class SyncStatus {
  final DateTime lastSyncDate;
  final int totalRecords;
  final String lastError;

  const SyncStatus({
    required this.lastSyncDate,
    required this.totalRecords,
    required this.lastError,
  });

  Map<String, dynamic> toJson() => {
    'last_sync_date': lastSyncDate.toIso8601String(),
    'total_records': totalRecords,
    'last_error': lastError,
  };
}

class ReportsSyncProvider extends ChangeNotifier {
  static const String baseUrl = 'https://hide_domain.com';
  static const String dbEndpoint = '/db_finance';

  DatabaseService _dbService;

  ReportsSyncProvider(this._dbService);

  static const String _LAST_UPDATE_FILE = 'last_update.json';
  DateTime? _lastUpdateDateTime;

  bool _isSyncing = false;
  bool _hasError = false;
  String _errorMessage = '';
  double _progress = 0.0;
  int _syncedRecords = 0;
  int _totalRecords = 0;

  // Кэширование дат
  Map<DateTime, bool> _cachedLocalDateAvailability = {};
  Map<DateTime, bool> _cachedServerDateAvailability = {};
  bool _isDateAvailabilityLoaded = false;
  bool _isDateAvailabilityLoading = false;

  // Флаги для новой логики
  bool _isDownloadingDb = false;
  bool _isCheckingUpdate = false;

  bool get isSyncing => _isSyncing;
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;
  double get progress => _progress;
  int get syncedRecords => _syncedRecords;
  int get totalRecords => _totalRecords;

  Map<DateTime, bool> get cachedLocalDateAvailability => _cachedLocalDateAvailability;
  Map<DateTime, bool> get cachedServerDateAvailability => _cachedServerDateAvailability;
  bool get isDateAvailabilityLoaded => _isDateAvailabilityLoaded;
  bool get isDateAvailabilityLoading => _isDateAvailabilityLoading;

  // Новые геттеры
  bool get isDownloadingDb => _isDownloadingDb;
  bool get isCheckingUpdate => _isCheckingUpdate;

  DateTime? get lastUpdateDateTime => _lastUpdateDateTime;

  Future<SyncStatus?> get lastSyncStatus async => await _dbService.getSyncStatus();

  void resetProgress() {
    if (!_isSyncing && !_isDownloadingDb) {
      _syncedRecords = 0;
      _totalRecords = 0;
      _progress = 0.0;
      notifyListeners();
    }
  }

  Future<List<dynamic>> getUniqueValuesForField({
    required String field,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
    Map<String, List<dynamic>>? otherFilters, // Фильтры по другим полям
    int limit = 1000,
  }) async {
    try {
      await _dbService.testConnection();
      return await _dbService.getUniqueValuesForField(
        field: field,
        dateFrom: dateFrom,
        dateTo: dateTo,
        nmId: nmId,
        saName: saName,
        otherFilters: otherFilters,
        limit: limit,
      );
    } catch (e) {
      print('Ошибка получения уникальных значений для поля $field: $e');
      return [];
    }
  }

  Future<void> checkDatabaseUpdate() async {
    if (_isCheckingUpdate) return;

    _isCheckingUpdate = true;
    notifyListeners();

    final client = http.Client();
    try {
      if (_lastUpdateDateTime == null) {
        _lastUpdateDateTime = await _readLastUpdateFile();
      }

      final dateParam = _formatDateTimeParam(_lastUpdateDateTime!);
      print('Отправляем дату на сервер: $dateParam');

      final url = Uri.parse('$baseUrl$dbEndpoint?datetime=$dateParam');
      print('URL запроса: $url');

      final request = http.Request('GET', url);
      request.headers.addAll({'Accept': 'application/json, application/octet-stream'});
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode == 200) {
        final contentType = streamedResponse.headers['content-type'] ?? '';
        final contentDisposition = streamedResponse.headers['content-disposition'] ?? '';

        print('Content-Type: $contentType');
        print('Content-Disposition: $contentDisposition');

        if (contentType.contains('application/json')) {
          // JSON → база актуальна, читаем тело
          final response = await http.Response.fromStream(streamedResponse);
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          print('База актуальна: ${data['message']}');
        } else {
          // Бинарный ответ → загружаем новую базу
          print('Найдена новая версия базы, начинаем загрузку...');

          String? filename;
          if (contentDisposition.isNotEmpty) {
            final match = RegExp(r'filename="(.+?)"').firstMatch(contentDisposition);
            if (match != null) {
              filename = match.group(1);
              print('Имя файла из заголовка: $filename');
            }
          }

          await _downloadAndReplaceDatabaseFromStream(streamedResponse, filename);
        }
      } else {
        throw Exception('Ошибка сервера: ${streamedResponse.statusCode}');
      }
    } catch (e) {
      print('Ошибка при проверке обновления: $e');
      _hasError = true;
      _errorMessage = 'Ошибка при проверке обновления: $e';
    } finally {
      client.close();
      _isCheckingUpdate = false;
      notifyListeners();
    }
  }

  Future<void> _downloadAndReplaceDatabaseFromStream(
      http.StreamedResponse streamedResponse, String? filename) async {
    _isDownloadingDb = true;
    _progress = 0.0;
    notifyListeners();

    DateTime newDbDateTime;

    try {
      // 1. Извлекаем имя файла и дату
      String? sourceString = filename;
      if (sourceString == null) {
        final contentDisposition = streamedResponse.headers['content-disposition'] ?? '';
        final match = RegExp(r'filename=([^;]+)').firstMatch(contentDisposition);
        if (match != null) {
          sourceString = match.group(1)!.replaceAll('"', '');
        }
      }

      if (sourceString == null) {
        throw Exception('Нет имени файла');
      }

      final dateMatch = RegExp(r'(\d{8}_\d{6})').firstMatch(sourceString);
      if (dateMatch == null) {
        throw Exception('Нет даты в файле: $sourceString');
      }

      final dateStr = dateMatch.group(1)!;
      newDbDateTime = DateTime(
        int.parse(dateStr.substring(0, 4)),
        int.parse(dateStr.substring(4, 6)),
        int.parse(dateStr.substring(6, 8)),
        int.parse(dateStr.substring(9, 11)),
        int.parse(dateStr.substring(11, 13)),
        int.parse(dateStr.substring(13, 15)),
      );

      print('📅 Дата базы: $newDbDateTime');

      // 2. Сохраняем файл с отслеживанием прогресса
      final documentsDir = await getApplicationDocumentsDirectory();
      final tempParquetPath = path.join(documentsDir.path, 'wildberries_new.parquet');
      final file = File(tempParquetPath);
      final sink = file.openWrite();

      final totalBytes = streamedResponse.contentLength ?? 0;
      int receivedBytes = 0;

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        if (totalBytes > 0) {
          _progress = receivedBytes / totalBytes;
        } else {
          // Если размер неизвестен, прогресс будет приблизительным
          _progress = receivedBytes / (receivedBytes + 1);
        }
        notifyListeners();
      }

      await sink.close();
      _progress = 0.3;
      notifyListeners();

      // 3. Закрываем соединение с БД
      print('🔒 Закрываем соединение...');
      try {
        await _dbService.close();
      } catch (e) {
        // игнорируем
      }

      // 4. Импортируем Parquet
      _progress = 0.5;
      notifyListeners();
      await _dbService.importParquetDirectly(tempParquetPath);

      // 5. Сохраняем дату обновления
      _progress = 0.7;
      notifyListeners();
      await _writeLastUpdateFile(newDbDateTime);

      // 6. Обновляем статус синхронизации
      _progress = 0.9;
      notifyListeners();
      final totalCount = await _dbService.getTotalCount();
      await _updateSyncStatusSafe(SyncStatus(
        lastSyncDate: newDbDateTime,
        totalRecords: totalCount,
        lastError: '',
      ));

      // 7. Обновляем кэш дат
      await _updateDateCache();

      // 8. Удаляем временный файл
      _progress = 1.0;
      notifyListeners();
      try {
        await file.delete();
      } catch (e) {
        print('⚠️ Не удалось удалить временный файл: $e');
      }

      print('🎉 База обновлена!');
    } catch (e, stack) {
      print('❌ Ошибка при загрузке/импорте: $e');
      print(stack);
      _hasError = true;
      _errorMessage = 'Ошибка: $e';

      // Пытаемся пересоздать соединение с БД
      try {
        _dbService = DatabaseService();
        await _dbService.testConnection();
      } catch (reconnectError) {
        // ничего
      }

      rethrow;
    } finally {
      _isDownloadingDb = false;
      notifyListeners();
    }
  }

  // Новый метод форматирования даты
  String _formatDateTimeParam(DateTime dateTime) {
    final year = dateTime.year.toString();
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');

    return '${year}${month}${day}_${hour}${minute}${second}';
  }

  Future<DateTime> _getLastDbUpdateDate() async {
    // Используем сохраненную дату или загружаем из файла
    if (_lastUpdateDateTime != null) {
      return _lastUpdateDateTime!;
    }

    _lastUpdateDateTime = await _readLastUpdateFile();
    return _lastUpdateDateTime!;
  }

  String _formatDateParam(DateTime date) {
    // Формат YYYYMMDD для сервера
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year$month$day';
  }

  // Чтение даты последнего обновления из файла
  Future<DateTime> _readLastUpdateFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(path.join(directory.path, _LAST_UPDATE_FILE));

      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content);
        final dateStr = json['last_update'] as String;

        // Парсим дату из формата "YYYY-MM-DD HH:MM:SS"
        try {
          final dateTime = DateTime.parse(dateStr.replaceAll(' ', 'T'));
          print('📅 Загружена сохраненная дата обновления: $dateTime');
          return dateTime;
        } catch (e) {
          // Если не получается, пробуем другой формат
          final parts = dateStr.split(' ');
          final datePart = parts[0];
          final timePart = parts.length > 1 ? parts[1] : '00:00:00';
          final dateTime = DateTime.parse('${datePart}T$timePart');
          print('📅 Загружена сохраненная дата обновления (альтернативный формат): $dateTime');
          return dateTime;
        }
      }
    } catch (e) {
      print('❌ Ошибка чтения файла last_update: $e');
    }

    // Если файла нет, возвращаем минимальную дату для первичной загрузки
    print('📅 Файл last_update не найден, используем минимальную дату');
    return DateTime(2000, 1, 1, 0, 0, 0);
  }

  // Запись даты обновления в файл
  Future<void> _writeLastUpdateFile(DateTime dateTime) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(path.join(directory.path, _LAST_UPDATE_FILE));

      // Сохраняем в формате "YYYY-MM-DD HH:MM:SS"
      final dateStr = '${dateTime.year.toString().padLeft(4, '0')}-'
          '${dateTime.month.toString().padLeft(2, '0')}-'
          '${dateTime.day.toString().padLeft(2, '0')} '
          '${dateTime.hour.toString().padLeft(2, '0')}:'
          '${dateTime.minute.toString().padLeft(2, '0')}:'
          '${dateTime.second.toString().padLeft(2, '0')}';

      await file.writeAsString(jsonEncode({
        'last_update': dateStr,
        'created_at': DateTime.now().toIso8601String(),
      }));

      _lastUpdateDateTime = dateTime;
      print('Дата обновления сохранена: $dateStr');
    } catch (e) {
      print('Ошибка записи файла last_update: $e');
    }
  }

  // Извлечение даты из имени файла
  DateTime _extractDateTimeFromFilename(String filename) {
    try {
      print('📋 Извлечение даты из имени файла: $filename');

      // Убираем всё лишнее из имени файла
      String cleanFilename = filename;

      // Удаляем расширение .parquet
      if (cleanFilename.toLowerCase().endsWith('.parquet')) {
        cleanFilename = cleanFilename.substring(0, cleanFilename.length - 8);
      }

      // Удаляем префикс db_to_client_
      if (cleanFilename.toLowerCase().startsWith('db_to_client_')) {
        cleanFilename = cleanFilename.substring('db_to_client_'.length);
      }

      print('📋 Очищенное имя файла: $cleanFilename');

      // Теперь cleanFilename должен быть в формате YYYYMMDD_HHMMSS
      // Пример: 20260205_162555

      // Разделяем на дату и время
      final parts = cleanFilename.split('_');
      if (parts.length >= 2) {
        final dateStr = parts[0]; // YYYYMMDD
        final timeStr = parts[1]; // HHMMSS

        if (dateStr.length == 8 && timeStr.length == 6) {
          final year = int.parse(dateStr.substring(0, 4));
          final month = int.parse(dateStr.substring(4, 6));
          final day = int.parse(dateStr.substring(6, 8));

          final hour = int.parse(timeStr.substring(0, 2));
          final minute = int.parse(timeStr.substring(2, 4));
          final second = int.parse(timeStr.substring(4, 6));

          final dateTime = DateTime(year, month, day, hour, minute, second);
          print('✅ Дата успешно извлечена из файла: $dateTime');
          return dateTime;
        }
      }

      // Альтернативный вариант: пробуем распарсить как целую строку
      // Формат: YYYYMMDD_HHMMSS
      final regex = RegExp(r'(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})');
      final match = regex.firstMatch(cleanFilename);

      if (match != null && match.groupCount >= 6) {
        final year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);
        final hour = int.parse(match.group(4)!);
        final minute = int.parse(match.group(5)!);
        final second = int.parse(match.group(6)!);

        final dateTime = DateTime(year, month, day, hour, minute, second);
        print('✅ Дата успешно извлечена из файла (через regex): $dateTime');
        return dateTime;
      }

      print('❌ Не удалось извлечь дату из имени файла: $cleanFilename');
      print('Ожидаемый формат: YYYYMMDD_HHMMSS');

    } catch (e) {
      print('❌ Ошибка извлечения даты из имени файла: $e');
    }

    // Если не удалось извлечь дату, ПАДАЕМ С ОШИБКОЙ
    throw Exception('Не удалось извлечь дату из имени файла: $filename. Ожидаемый формат: db_to_client_YYYYMMDD_HHMMSS.parquet или YYYYMMDD_HHMMSS');
  }

  Future<void> _downloadAndReplaceDatabase(String urlString, String? filename) async {
    _isDownloadingDb = true;
    _progress = 0.0;
    notifyListeners();

    DateTime newDbDateTime;
    final client = http.Client();

    try {
      // 1. Подготовка запроса
      final url = Uri.parse(urlString);
      final request = http.Request('GET', url);
      request.headers.addAll({'Accept': 'application/json, application/octet-stream'});

      // 2. Отправка и получение потокового ответа
      final streamedResponse = await client.send(request);

      // 3. Проверка статуса
      if (streamedResponse.statusCode != 200) {
        throw Exception('Ошибка сервера: ${streamedResponse.statusCode}');
      }

      // 4. Определение имени файла и даты
      String? sourceString = filename;
      if (sourceString == null) {
        final contentDisposition = streamedResponse.headers['content-disposition'] ?? '';
        final match = RegExp(r'filename=([^;]+)').firstMatch(contentDisposition);
        if (match != null) {
          sourceString = match.group(1)!.replaceAll('"', '');
        }
      }

      if (sourceString == null) {
        throw Exception('Нет имени файла');
      }

      final dateMatch = RegExp(r'(\d{8}_\d{6})').firstMatch(sourceString);
      if (dateMatch == null) {
        throw Exception('Нет даты в файле: $sourceString');
      }

      final dateStr = dateMatch.group(1)!;
      newDbDateTime = DateTime(
        int.parse(dateStr.substring(0, 4)),
        int.parse(dateStr.substring(4, 6)),
        int.parse(dateStr.substring(6, 8)),
        int.parse(dateStr.substring(9, 11)),
        int.parse(dateStr.substring(11, 13)),
        int.parse(dateStr.substring(13, 15)),
      );

      print('📅 Дата базы: $newDbDateTime');

      // 5. Подготовка к сохранению файла с отслеживанием прогресса
      final documentsDir = await getApplicationDocumentsDirectory();
      final tempParquetPath = path.join(documentsDir.path, 'wildberries_new.parquet');
      final file = File(tempParquetPath);
      final sink = file.openWrite();

      final totalBytes = streamedResponse.contentLength ?? 0;
      int receivedBytes = 0;

      // 6. Чтение потока и запись в файл с обновлением прогресса
      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        if (totalBytes > 0) {
          _progress = receivedBytes / totalBytes;
        } else {
          // Если размер неизвестен, показываем приблизительный прогресс (например, по чанкам)
          _progress = receivedBytes / (receivedBytes + 1); // никогда не достигнет 1
        }
        notifyListeners();
      }

      await sink.close();
      _progress = 0.3;
      notifyListeners();

      // 7. Закрываем соединение с БД перед импортом
      print('🔒 Закрываем соединение...');
      try {
        await _dbService.close();
      } catch (e) {
        // игнорируем
      }

      // 8. Импортируем Parquet напрямую в DuckDB
      _progress = 0.5;
      notifyListeners();
      await _dbService.importParquetDirectly(tempParquetPath);

      // 9. Сохраняем дату обновления
      _progress = 0.7;
      notifyListeners();
      await _writeLastUpdateFile(newDbDateTime);

      // 10. Обновляем статус синхронизации
      _progress = 0.9;
      notifyListeners();
      final totalCount = await _dbService.getTotalCount();
      await _updateSyncStatusSafe(SyncStatus(
        lastSyncDate: newDbDateTime,
        totalRecords: totalCount,
        lastError: '',
      ));

      // 11. Обновляем кэш дат
      await _updateDateCache();

      // 12. Удаляем временный файл
      _progress = 1.0;
      notifyListeners();
      try {
        await file.delete();
      } catch (e) {
        print('⚠️ Не удалось удалить временный файл: $e');
      }

      print('🎉 База обновлена!');
    } catch (e, stack) {
      print('❌ Ошибка при загрузке/импорте: $e');
      print(stack);
      _hasError = true;
      _errorMessage = 'Ошибка: $e';

      // Пытаемся пересоздать соединение с БД
      try {
        _dbService = DatabaseService();
        await _dbService.testConnection();
      } catch (reconnectError) {
        // ничего не делаем
      }

      rethrow;
    } finally {
      client.close();
      _isDownloadingDb = false;
      notifyListeners();
    }
  }

// lib/providers/reports_sync_provider.dart - ДОБАВЛЯЕМ НОВЫЕ МЕТОДЫ
  Future<List<Map<String, dynamic>>> getReportsPaginated({
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
    Map<String, List<dynamic>>? filters, // НОВЫЙ ПАРАМЕТР
    String? sortField,
    bool sortDesc = true,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      await _dbService.testConnection();
      final reports = await _dbService.getReportsPaginated(
        dateFrom: dateFrom,
        dateTo: dateTo,
        nmId: nmId,
        saName: saName,
        filters: filters, // Передаем фильтры
        sortField: sortField,
        sortDesc: sortDesc,
        limit: limit,
        offset: offset,
      );

      return reports;
    } catch (e) {
      print('Ошибка получения отчетов с пагинацией: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getAggregatedData({
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
    Map<String, List<dynamic>>? filters, // НОВЫЙ ПАРАМЕТР
  }) async {
    try {
      await _dbService.testConnection();
      return await _dbService.getAggregatedData(
        dateFrom: dateFrom,
        dateTo: dateTo,
        nmId: nmId,
        saName: saName,
        filters: filters, // Передаем фильтры
      );
    } catch (e) {
      print('Ошибка получения агрегированных данных: $e');
      return {};
    }
  }

  Future<int> getTotalCountWithFilters({
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
    Map<String, List<dynamic>>? filters, // НОВЫЙ ПАРАМЕТР
  }) async {
    try {
      await _dbService.testConnection();
      return await _dbService.getTotalCountWithFilters(
        dateFrom: dateFrom,
        dateTo: dateTo,
        nmId: nmId,
        saName: saName,
        filters: filters, // Передаем фильтры
      );
    } catch (e) {
      print('Ошибка получения общего количества: $e');
      return 0;
    }
  }

  Future<void> _updateSyncStatusSafe(SyncStatus status) async {
    try {
      // Способ 1: DELETE + INSERT (работает в DuckDB)
      final conn = await _getConnection();

      await conn.execute('DELETE FROM sync_status WHERE id = 1');

      final stmt = await conn.prepare(
        'INSERT INTO sync_status (id, last_sync_date, total_records, last_error) VALUES (1, ?, ?, ?)',
      );

      stmt.bind(status.lastSyncDate.toIso8601String(), 1);
      stmt.bind(status.totalRecords, 2);
      stmt.bind(status.lastError ?? '', 3);
      await stmt.execute();
      await stmt.dispose();

    } catch (e) {
      print('⚠️ Не удалось обновить статус в базе: $e');
      // Сохраняем в файл как запасной вариант
      await _saveSyncStatusToFile(status);
    }
  }

  Future<Connection> _getConnection() async {
    try {
      // Проверяем, инициализировано ли соединение
      if (_dbService.conn == null) {
        await _dbService.init();
      }

      final connection = _dbService.conn;
      if (connection == null) {
        throw Exception('Не удалось установить соединение с базой данных');
      }

      return connection;
    } catch (e) {
      print('❌ Ошибка получения соединения: $e');
      rethrow;
    }
  }

  Future<void> _saveSyncStatusToFile(SyncStatus status) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(path.join(directory.path, 'sync_status_fallback.json'));
    await file.writeAsString(jsonEncode(status.toJson()));
  }

  Future<void> _insertBatch(PreparedStatement stmt, List<List<dynamic>> rows) async {
    for (final row in rows) {
      stmt.clearBinding();
      for (int i = 0; i < row.length; i++) {
        stmt.bind(row[i], i + 1);
      }
      await stmt.execute();
    }
  }

  Future<void> _updateDateCache() async {
    _isDateAvailabilityLoading = true;
    notifyListeners();

    try {
      final startDate = DateTime(2025, 9, 1);
      final endDate = DateTime.now();

      List<DateTime> allDates = [];
      DateTime currentDate = startDate;

      while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
        allDates.add(DateTime.utc(currentDate.year, currentDate.month, currentDate.day));
        currentDate = currentDate.add(const Duration(days: 1));
      }

      final localAvailability = await _dbService.checkDates(allDates);
      _cachedLocalDateAvailability = localAvailability;

      // Серверные данные - все даты считаем доступными после загрузки новой базы
      final serverAvailability = <DateTime, bool>{};
      for (final date in allDates) {
        serverAvailability[date] = true;
      }
      _cachedServerDateAvailability = serverAvailability;

      // Обновляем кэш в базе
      for (final date in allDates) {
        await _dbService.updateDateCache(
          date,
          _cachedLocalDateAvailability[date] ?? false,
          _cachedServerDateAvailability[date] ?? false,
        );
      }

      _isDateAvailabilityLoaded = true;

    } catch (e) {
      print('Ошибка обновления кэша дат: $e');
    } finally {
      _isDateAvailabilityLoading = false;
      notifyListeners();
    }
  }

  Future<void> clearDataForDateRange(DateTime startDate, DateTime endDate) async {
    if (_isSyncing) return;

    _isSyncing = true;
    _hasError = false;
    _errorMessage = '';
    notifyListeners();

    try {
      await _dbService.deleteReportsByDateRange(startDate, endDate);

      // Обновляем кэш дат
      await _updateDateCacheAfterDelete(startDate, endDate);

    } catch (e) {
      _hasError = true;
      _errorMessage = 'Ошибка при удалении данных: $e';
    } finally {
      _isSyncing = false;
      _progress = 0.0;
      notifyListeners();
    }
  }

  Future<void> _updateDateCacheAfterDelete(DateTime startDate, DateTime endDate) async {
    DateTime currentDate = startDate;
    final endDateNormalized = DateTime(endDate.year, endDate.month, endDate.day);

    while (currentDate.isBefore(endDateNormalized) || currentDate.isAtSameMomentAs(endDateNormalized)) {
      _cachedLocalDateAvailability.remove(currentDate);
      _cachedServerDateAvailability.remove(currentDate);

      await _dbService.updateDateCache(currentDate, false, false);

      currentDate = currentDate.add(const Duration(days: 1));
    }

    final totalRecords = await _dbService.getTotalCount();
    final syncStatus = SyncStatus(
      lastSyncDate: DateTime.now(),
      totalRecords: totalRecords,
      lastError: '',
    );

    await _dbService.updateSyncStatus(syncStatus);
    notifyListeners();
  }

  Future<void> checkDateAvailability({bool forceRefresh = false}) async {
    if (forceRefresh) {
      _isDateAvailabilityLoaded = false;
      _cachedLocalDateAvailability.clear();
      _cachedServerDateAvailability.clear();
    }

    if (_isDateAvailabilityLoading) return;

    _isDateAvailabilityLoading = true;
    notifyListeners();

    try {
      final startDate = DateTime(2025, 9, 1);
      final endDate = DateTime.now();

      List<DateTime> allDates = [];
      DateTime currentDate = startDate;

      while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
        allDates.add(DateTime.utc(currentDate.year, currentDate.month, currentDate.day));
        currentDate = currentDate.add(const Duration(days: 1));
      }

      final localAvailability = await _dbService.checkDates(allDates);
      _cachedLocalDateAvailability = localAvailability;

      // Для серверных данных используем кэш или считаем все доступными
      if (_cachedServerDateAvailability.isEmpty) {
        final serverAvailability = <DateTime, bool>{};
        for (final date in allDates) {
          serverAvailability[date] = true;
        }
        _cachedServerDateAvailability = serverAvailability;
      }

      _isDateAvailabilityLoaded = true;

    } catch (e) {
      print('Ошибка загрузки доступности дат: $e');
    } finally {
      _isDateAvailabilityLoading = false;
      notifyListeners();
    }
  }

  // Старая логика синхронизации - оставляем для совместимости, но не используем
  Future<void> syncWithServer({DateTime? customDateFrom, DateTime? customDateTo}) async {
    // Просто проверяем обновление базы
    await checkDatabaseUpdate();
  }

  Future<List<Map<String, dynamic>>> getReports({
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
  }) async {
    try {
      await _dbService.testConnection();
      final reports = await _dbService.getReports(
        dateFrom: dateFrom,
        dateTo: dateTo,
        nmId: nmId,
        saName: saName,
      );

      return reports;
    } catch (e) {
      print('Ошибка получения отчетов: $e');
      return [];
    }
  }

  Future<void> clearLocalData() async {
    await _dbService.clearAllReports();

    // Сбрасываем дату обновления к начальной
    _lastUpdateDateTime = DateTime(2000, 1, 1, 0, 0, 0);
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(path.join(directory.path, _LAST_UPDATE_FILE));
      if (await file.exists()) {
        await file.delete();
        print('Файл с датой обновления удален');
      }
    } catch (e) {
      print('Ошибка удаления файла даты: $e');
    }

    final syncStatus = SyncStatus(
      lastSyncDate: DateTime.now(),
      totalRecords: 0,
      lastError: '',
    );
    await _dbService.updateSyncStatus(syncStatus);

    _cachedLocalDateAvailability.clear();
    _cachedServerDateAvailability.clear();
    _isDateAvailabilityLoaded = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>> getStatistics() async {
    return await _dbService.getStatistics();
  }

  bool hasDataForDateRange(DateTime startDate, DateTime endDate) {
    final normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);
    final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day);

    for (final entry in _cachedLocalDateAvailability.entries) {
      final date = entry.key;
      if ((date.isAfter(normalizedStart) || date.isAtSameMomentAs(normalizedStart)) &&
          (date.isBefore(normalizedEnd) || date.isAtSameMomentAs(normalizedEnd))) {
        if (entry.value) {
          return true;
        }
      }
    }

    return false;
  }

  Future<Map<DateTime, bool>> checkDatesFromDateTimes(List<DateTime> dates) async {
    if (_isDateAvailabilityLoaded && _cachedLocalDateAvailability.isNotEmpty) {
      final Map<DateTime, bool> result = {};
      for (final date in dates) {
        result[date] = _cachedLocalDateAvailability[date] ?? false;
      }
      return result;
    }

    return await _dbService.checkDates(dates);
  }

  bool hasDataForDate(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    return _cachedLocalDateAvailability[normalizedDate] ?? false;
  }

  Future<Map<DateTime, bool>> checkDatesOnServer(List<DateTime> dates) async {
    if (_isDateAvailabilityLoaded && _cachedServerDateAvailability.isNotEmpty) {
      final Map<DateTime, bool> result = {};
      for (final date in dates) {
        result[date] = _cachedServerDateAvailability[date] ?? false;
      }
      return result;
    }

    // Возвращаем true для всех дат, так как после загрузки новой базы считаем всё доступным
    final result = <DateTime, bool>{};
    for (final date in dates) {
      result[date] = true;
    }
    return result;
  }

  // ========== ДАННЫЕ ДЛЯ ГРАФИКА ==========
  Future<List<Map<String, dynamic>>> getTimeSeriesData({
    required String dateColumn,
    required String valueColumn,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
    Map<String, List<dynamic>>? filters,
  }) async {
    try {
      await _dbService.testConnection();
      return await _dbService.getTimeSeriesData(
        dateColumn: dateColumn,
        valueColumn: valueColumn,
        dateFrom: dateFrom,
        dateTo: dateTo,
        nmId: nmId,
        saName: saName,
        filters: filters,
      );
    } catch (e) {
      print('❌ Ошибка получения данных графика: $e');
      return [];
    }
  }

  Future<void> updateCustomColumn(String columnName, String newDisplayName, String newFormula) async {
    try {
      await _dbService.testConnection();
      await _dbService.updateCustomColumn(columnName, newDisplayName, newFormula);
    } catch (e) {
      print('❌ Ошибка обновления кастомной колонки: $e');
      rethrow;
    }
  }

  Future<void> deleteCustomColumn(String columnName) async {
    try {
      await _dbService.testConnection();
      await _dbService.deleteCustomColumn(columnName);
    } catch (e) {
      print('❌ Ошибка удаления кастомной колонки через провайдер: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getCustomColumns() async {
    return await _dbService.getCustomColumns();
  }

  Future<void> addCustomColumn(String displayName, String formula) async {
    await _dbService.addCustomColumn(displayName, formula);
  }

  Future<int> getAggregatedGroupCount({
    required String groupByField,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
    Map<String, List<dynamic>>? filters,
  }) async {
    try {
      await _dbService.testConnection();
      return await _dbService.getAggregatedGroupCount(
        groupByField: groupByField,
        dateFrom: dateFrom,
        dateTo: dateTo,
        nmId: nmId,
        saName: saName,
        filters: filters,
      );
    } catch (e) {
      print('❌ Ошибка подсчёта групп: $e');
      return 0;
    }
  }
  // Добавить в lib/providers/reports_sync_provider.dart после других методов

  Future<List<Map<String, dynamic>>> getAggregatedByColumn({
    required String groupByField,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
    Map<String, List<dynamic>>? filters,
    Map<String, String>? aggregationMethods,
    String? sortField,
    bool sortDesc = true,
    int? limit,      // ← добавлено
    int? offset,     // ← добавлено
  }) async {
    try {
      await _dbService.testConnection();
      return await _dbService.getAggregatedByColumn(
        groupByField: groupByField,
        dateFrom: dateFrom,
        dateTo: dateTo,
        nmId: nmId,
        saName: saName,
        filters: filters,
        aggregationMethods: aggregationMethods,
        sortField: sortField,
        sortDesc: sortDesc,
        limit: limit,    // ← передаём
        offset: offset,  // ← передаём
      );
    } catch (e) {
      print('❌ Ошибка получения агрегированных данных по столбцу: $e');
      return [];
    }
  }
}