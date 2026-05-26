import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:path_provider/path_provider.dart';

class SalesFunnelRecord {
  final int nmId;
  final DateTime date;
  final int openCount;
  final int orderCount;

  SalesFunnelRecord({
    required this.nmId,
    required this.date,
    required this.openCount,
    required this.orderCount,
  });
}

class SalesFunnelManager {
  static final SalesFunnelManager _instance = SalesFunnelManager._internal();
  factory SalesFunnelManager() => _instance;
  SalesFunnelManager._internal();

  bool _initialized = false;
  Map<int, List<SalesFunnelRecord>> _dataByNmId = {};
  List<DateTime> _allDates = [];

  Future<void> initialize() async {
    if (_initialized) return;
    await _loadData();
    _initialized = true;
  }

  Future<void> _loadData() async {
    Database? db;
    Connection? conn;
    File? tempFile;

    try {
      print('📥 [SalesFunnel] Начинаем загрузку Parquet по URL...');
      final url = Uri.parse('https://hide_domain.com/reports/sales-funnel/parquet');
      final response = await http.get(url).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        print('❌ [SalesFunnel] Ошибка HTTP ${response.statusCode}');
        return;
      }
      print('✅ [SalesFunnel] Файл загружен, размер ${response.bodyBytes.length} байт');

      final tempDir = await getTemporaryDirectory();
      tempFile = File('${tempDir.path}/sales_funnel.parquet');
      await tempFile.writeAsBytes(response.bodyBytes);
      final parquetPath = tempFile.path.replaceAll('\\', '/');
      print('📁 [SalesFunnel] Временный файл: $parquetPath');

      db = await duckdb.open(':memory:');
      conn = await duckdb.connect(db!);
      print('🔌 [SalesFunnel] DuckDB in-memory подключена');

      // Прочитаем схему Parquet для отладки
      final schemaResult = await conn!.query("SELECT * FROM read_parquet('$parquetPath') LIMIT 0");
      final columnNames = schemaResult.columnNames;
      await schemaResult.dispose();
      print('📊 [SalesFunnel] Колонки в Parquet: $columnNames');

      // Проверим количество строк
      final countResult = await conn!.query("SELECT COUNT(*) FROM read_parquet('$parquetPath')");
      final countRows = countResult.fetchAll().first[0] as int;
      await countResult.dispose();
      print('📊 [SalesFunnel] Всего строк в Parquet: $countRows');

      // Выполним основной запрос
      await conn.execute('''
      CREATE TEMP TABLE sales_funnel AS 
      SELECT * FROM read_parquet('$parquetPath')
    ''');
      print('✅ [SalesFunnel] Временная таблица создана');

      final stmt = await conn.prepare('''
      SELECT nm_id, date, open_count, order_count 
      FROM sales_funnel 
      ORDER BY nm_id, date
    ''');
      final result = await stmt.execute();
      final rows = result.fetchAll();
      print('📊 [SalesFunnel] Выборка вернула ${rows.length} строк');

      await result.dispose();
      await stmt.dispose();

      final Map<int, List<SalesFunnelRecord>> tempMap = {};
      final Set<DateTime> datesSet = {};

      for (final row in rows) {
        if (row.length < 4) continue;
        final nmId = row[0] as int;
        final dateValue = row[1];
        final DateTime date;
        if (dateValue is DateTime) {
          date = dateValue;
        } else if (dateValue is String) {
          date = DateTime.parse(dateValue);
        } else {
          print('❌ Неизвестный тип даты: ${dateValue.runtimeType}');
          continue;
        }
        final openCount = row[2] as int;
        final orderCount = row[3] as int;

        tempMap.putIfAbsent(nmId, () => []).add(
          SalesFunnelRecord(
            nmId: nmId,
            date: date,
            openCount: openCount,
            orderCount: orderCount,
          ),
        );
        datesSet.add(DateTime(date.year, date.month, date.day));
      }

      for (var entry in tempMap.entries) {
        entry.value.sort((a, b) => a.date.compareTo(b.date));
      }

      _dataByNmId = tempMap;
      _allDates = datesSet.toList()..sort();

      print('✅ [SalesFunnel] Итог: ${_dataByNmId.length} товаров, ${_allDates.length} дней');

      if (_dataByNmId.isEmpty) {
        print('⚠️ [SalesFunnel] ВНИМАНИЕ: нет ни одного товара! Возможно, не совпадают имена колонок в Parquet.');
        print('   Ожидаемые колонки: nm_id, date, open_count, order_count');
        print('   Фактические колонки: $columnNames');
      }
    } catch (e, stack) {
      print('❌ [SalesFunnel] Ошибка загрузки/чтения Parquet: $e');
      print(stack);
    } finally {
      await conn?.dispose();
      await db?.dispose();
      await tempFile?.delete();
    }
  }

  /// Возвращает первую запись из загруженных данных (для отладки).
  Future<SalesFunnelRecord?> getFirstRecord() async {
    if (!_initialized) await initialize();
    for (final list in _dataByNmId.values) {
      if (list.isNotEmpty) return list.first;
    }
    return null;
  }

  Future<List<double>> getValuesForNmId(int nmId, int days, {required bool open}) async {
    if (!_initialized) await initialize();
    final records = _dataByNmId[nmId] ?? [];
    if (records.isEmpty) return List.filled(days, 0.0);

    final nowUtc = DateTime.now().toUtc();
    final targetDates = List.generate(days, (i) {
      return DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day - (days - 1 - i));
    });

    final List<double> result = [];
    for (var date in targetDates) {
      final record = records.cast<SalesFunnelRecord?>().firstWhere(
        (r) => r != null &&
            r.date.year == date.year &&
            r.date.month == date.month &&
            r.date.day == date.day,
        orElse: () => null,
      );
      if (record != null) {
        result.add(open ? record.openCount.toDouble() : record.orderCount.toDouble());
      } else {
        result.add(0.0);
      }
    }
    return result;
  }

  List<DateTime> getLastNDates(int days) {
    final now = DateTime.now();
    return List.generate(days, (i) {
      return DateTime(now.year, now.month, now.day - (days - 1 - i));
    });
  }

  List<String> getDateLabels(int days) {
    return getLastNDates(days).map((d) => DateFormat('dd.MM').format(d)).toList();
  }

  bool get isInitialized => _initialized;
}