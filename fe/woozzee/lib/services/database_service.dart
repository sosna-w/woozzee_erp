// lib/services/database_service.dart
import 'dart:io';
import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/report_detail_model.dart';
import '../providers/reports_sync_provider.dart';

class DatabaseService {
  Database? _db;
  Connection? _conn;
  bool _isInitialized = false;
  Connection? get conn => _conn;

  Future<void> testConnection() async {
    try {
      print('🔌 Проверка соединения с базой данных...');

      if (!_isInitialized) {
        print('🔄 База не инициализирована, запускаем init()...');
        await init();
        print('✅ База инициализирована');
      }

      if (_conn == null) {
        throw Exception('Соединение с базой данных не установлено');
      }

      print('📝 Выполняем тестовый запрос SELECT 1...');
      final testStmt = await _conn!.prepare('SELECT 1 as test_value');
      final result = await testStmt.execute();
      final rows = result.fetchAll();
      await result.dispose();
      await testStmt.dispose();

      if (rows.isNotEmpty) {
        print('✅ Соединение с базой успешно установлено');
        print('📊 Тестовый запрос вернул: ${rows[0][0]}');
      } else {
        print('⚠️ Тестовый запрос не вернул данных');
      }

    } catch (e) {
      print('❌ Ошибка подключения к базе: $e');
      print('🔄 Пытаемся переинициализировать...');

      _isInitialized = false;
      _db = null;
      _conn = null;

      try {
        await init();
        print('✅ Переинициализация успешна');
      } catch (initError) {
        print('❌ Ошибка переинициализации: $initError');
        rethrow;
      }
    }
  }

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = path.join(documentsDir.path, 'wildberries_analytics.duckdb');

      print('📁 Открытие DuckDB базы: $dbPath');

      _db = await duckdb.open(dbPath);
      _conn = await duckdb.connect(_db!);

      await _conn!.execute("PRAGMA memory_limit='2GB'");
      await _conn!.execute('PRAGMA threads=4');

      await _createTables();

      _isInitialized = true;
      print('✅ DuckDB база данных инициализирована');

    } catch (e) {
      print('❌ Критическая ошибка инициализации базы данных: $e');
      _isInitialized = false;
      _db = null;
      _conn = null;
      rethrow;
    }
  }

  Future<List<dynamic>> getUniqueValuesForField({
    required String field,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
    Map<String, List<dynamic>>? otherFilters,
    int limit = 1000,
  }) async {
    if (!_isInitialized) {
      try {
        await init();
      } catch (e) {
        print('❌ Ошибка инициализации базы: $e');
        return [];
      }
    }

    try {
      // Начинаем построение SQL запроса
      String sql = 'SELECT DISTINCT "$field" FROM reports WHERE 1=1';
      final params = <dynamic>[];

      // Базовые фильтры (дата, nmId, saName)
      if (dateFrom != null) {
        sql += ' AND report_date >= ?';
        params.add(dateFrom.toIso8601String());
      }

      if (dateTo != null) {
        sql += ' AND report_date <= ?';
        params.add(dateTo.toIso8601String());
      }

      if (nmId != null) {
        sql += ' AND nm_id = ?';
        params.add(nmId);
      }

      if (saName != null && saName.isNotEmpty) {
        sql += ' AND sa_name LIKE ?';
        params.add('%$saName%');
      }

      // Фильтры по другим полям (исключая текущее поле)
      if (otherFilters != null) {
        otherFilters.forEach((filterField, filterValues) {
          if (filterField != field && filterValues.isNotEmpty) {
            // Исключаем NULL из обычных значений
            final nonNullValues = filterValues.where((v) => v != null).toList();
            final hasNull = filterValues.any((v) => v == null);

            if (nonNullValues.isNotEmpty) {
              final placeholders = List.filled(nonNullValues.length, '?').join(',');
              sql += ' AND "$filterField" IN ($placeholders)';
              params.addAll(nonNullValues);
            }

            if (hasNull) {
              sql += ' AND "$filterField" IS NULL';
            }
          }
        });
      }

      // Сортировка и лимит
      sql += ' ORDER BY "$field"';
      sql += ' LIMIT $limit';

      final stmt = await _conn!.prepare(sql);

      try {
        // Биндим параметры
        for (int i = 0; i < params.length; i++) {
          stmt.bind(params[i], i + 1);
        }

        final result = await stmt.execute();
        final rows = result.fetchAll();
        await result.dispose();

        // Преобразуем результат в список
        final List<dynamic> values = [];
        for (final row in rows) {
          if (row.isNotEmpty) {
            final value = row[0];

            // Для дат конвертируем строку в DateTime
            if (field.endsWith('_dt') ||
                field == 'report_date' ||
                field == 'created_at' ||
                field == 'updated_at') {
              if (value is String) {
                try {
                  values.add(DateTime.parse(value));
                } catch (e) {
                  values.add(value);
                }
              } else if (value is DateTime) {
                values.add(value);
              } else if (value != null) {
                values.add(value);
              } else {
                values.add(null);
              }
            } else {
              values.add(value);
            }
          }
        }

        return values;
      } finally {
        await stmt.dispose();
      }
    } catch (e) {
      print('❌ Ошибка выполнения запроса getUniqueValuesForField: $e');
      return [];
    }
  }

  // lib/services/database_service.dart - ДОБАВЛЯЕМ НОВЫЕ МЕТОДЫ
  Future<List<Map<String, dynamic>>> getReportsPaginated({
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
    Map<String, List<dynamic>>? filters,
    String? sortField,
    bool sortDesc = true,
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_isInitialized) await init();

    try {
      final customFormulas = await getCustomFormulas();

      // Формируем SELECT
      String selectFields = '*';
      if (customFormulas.isNotEmpty) {
        final customSelects = customFormulas.entries
            .map((e) => '(${e.value}) AS "${e.key}"')
            .join(', ');
        selectFields = '*, $customSelects';
      }

      String sql = 'SELECT $selectFields FROM reports WHERE 1=1';
      final params = <dynamic>[];

      // Базовые фильтры
      if (dateFrom != null) {
        sql += ' AND report_date >= ?';
        params.add(dateFrom.toIso8601String());
      }
      if (dateTo != null) {
        sql += ' AND report_date <= ?';
        params.add(dateTo.toIso8601String());
      }
      if (nmId != null) {
        sql += ' AND nm_id = ?';
        params.add(nmId);
      }
      if (saName != null && saName.isNotEmpty) {
        sql += ' AND sa_name LIKE ?';
        params.add('%$saName%');
      }

      // Фильтры по полям (включая кастомные)
      if (filters != null && filters.isNotEmpty) {
        filters.forEach((field, values) {
          if (values.isEmpty) return;

          final isCustom = customFormulas.containsKey(field);
          final fieldExpr = isCustom ? '(${customFormulas[field]})' : '"$field"';

          final nonNullValues = values.where((v) => v != null).toList();
          final hasNull = values.any((v) => v == null);

          if (nonNullValues.isNotEmpty && hasNull) {
            final placeholders = List.filled(nonNullValues.length, '?').join(',');
            sql += ' AND ($fieldExpr IN ($placeholders) OR $fieldExpr IS NULL)';
            params.addAll(nonNullValues);
          } else if (nonNullValues.isNotEmpty) {
            final placeholders = List.filled(nonNullValues.length, '?').join(',');
            sql += ' AND $fieldExpr IN ($placeholders)';
            params.addAll(nonNullValues);
          } else if (hasNull) {
            sql += ' AND $fieldExpr IS NULL';
          }
        });
      }

      // Сортировка
      if (sortField != null) {
        final isCustom = customFormulas.containsKey(sortField);
        final orderExpr = isCustom ? '(${customFormulas[sortField]})' : '"$sortField"';
        sql += ' ORDER BY $orderExpr ${sortDesc ? 'DESC' : 'ASC'}';
      } else {
        sql += ' ORDER BY report_date DESC';
      }

      sql += ' LIMIT $limit OFFSET $offset';

      final stmt = await _conn!.prepare(sql);
      try {
        for (int i = 0; i < params.length; i++) {
          stmt.bind(params[i], i + 1);
        }
        final result = await stmt.execute();
        final rows = result.fetchAll();
        final columnNames = result.columnNames;
        await result.dispose();

        final List<Map<String, dynamic>> data = [];
        for (final row in rows) {
          final record = <String, dynamic>{};
          for (int i = 0; i < columnNames.length; i++) {
            record[columnNames[i]] = row[i];
          }
          data.add(record);
        }
        return data;
      } finally {
        await stmt.dispose();
      }
    } catch (e) {
      print('❌ Ошибка getReportsPaginated: $e');
      return [];
    }
  }

  // lib/services/database_service.dart
  Future<Map<String, dynamic>> getAggregatedData({
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
    Map<String, List<dynamic>>? filters,
  }) async {
    if (!_isInitialized) await init();

    try {
      // Получаем все кастомные колонки и их формулы
      final customFormulas = await getCustomFormulas(); // Map<columnName, formula>

      // Список стандартных числовых полей (без изменений)
      final numericFields = [
        'quantity',
        'operation_quantity',
        'retail_price',
        'retail_price_recovery',
        'retail_amount',
        'retail_amount_refunded',
        'ppvz_for_pay',
        'ppvz_for_recovery',
        'cost_price',
        'cost_price_recovered',
        'additional_expenses',
        'additional_expenses_recovered',
        'commission_amount',
        'commission_amount_reversed',
        'commission_normal',
        'commission_normal_reversed',
        'penalty_commission_rub',
        'penalty_commission_reversed',
        'delivery_rub',
        'return_delivery_rub',
        'ppvz_reward',
        'ppvz_reward_reversed',
        'acquiring_fee',
        'acquiring_fee_reversed',
        'acceptance',
        'cashback_amount',
        'cashback_amount_reversed',
        'cashback_commission_change',
        'cashback_commission_change_reversed',
        'storage_fee',
        'penalty',
        'deduction',
        'additional_payment',
        'payment_schedule',
        'delivery_amount',
        'return_amount'
      ];

      final selectParts = <String>[];
      selectParts.add('COUNT(*) as total_count');

      // Агрегаты для стандартных полей
      for (final field in numericFields) {
        selectParts.add('SUM("$field") as total_$field');
        selectParts.add('AVG("$field") as avg_$field');
        selectParts.add('MAX("$field") as max_$field');
        selectParts.add('MIN("$field") as min_$field');
        selectParts.add('COUNT("$field") as count_$field');
      }

      // Агрегаты для кастомных полей
      for (final entry in customFormulas.entries) {
        final columnName = entry.key;
        final formula = entry.value; // формула уже обёрнута в COALESCE при создании
        selectParts.add('SUM($formula) as total_$columnName');
        selectParts.add('AVG($formula) as avg_$columnName');
        selectParts.add('MAX($formula) as max_$columnName');
        selectParts.add('MIN($formula) as min_$columnName');
        selectParts.add('COUNT($formula) as count_$columnName');
      }

      final selectClause = selectParts.join(',\n');

      String sql = '''
      SELECT 
        $selectClause
      FROM reports 
      WHERE 1=1
    ''';

      final params = <dynamic>[];

      // Базовые фильтры (без изменений)
      if (dateFrom != null) {
        sql += ' AND report_date >= ?';
        params.add(dateFrom.toIso8601String());
      }
      if (dateTo != null) {
        sql += ' AND report_date <= ?';
        params.add(dateTo.toIso8601String());
      }
      if (nmId != null) {
        sql += ' AND nm_id = ?';
        params.add(nmId);
      }
      if (saName != null && saName.isNotEmpty) {
        sql += ' AND sa_name LIKE ?';
        params.add('%$saName%');
      }

      // Дополнительные фильтры по полям (включая кастомные)
      if (filters != null && filters.isNotEmpty) {
        for (final entry in filters.entries) {
          final field = entry.key;
          final values = entry.value;
          if (values.isEmpty) continue;

          final isCustom = customFormulas.containsKey(field);
          final fieldExpr = isCustom ? '(${customFormulas[field]})' : '"$field"';

          final nonNullValues = values.where((v) => v != null).toList();
          final hasNull = values.any((v) => v == null);

          if (nonNullValues.isNotEmpty && hasNull) {
            final placeholders = List.filled(nonNullValues.length, '?').join(',');
            sql += ' AND ($fieldExpr IN ($placeholders) OR $fieldExpr IS NULL)';
            params.addAll(nonNullValues);
          } else if (nonNullValues.isNotEmpty) {
            final placeholders = List.filled(nonNullValues.length, '?').join(',');
            sql += ' AND $fieldExpr IN ($placeholders)';
            params.addAll(nonNullValues);
          } else if (hasNull) {
            sql += ' AND $fieldExpr IS NULL';
          }
        }
      }

      print('🔍 SQL агрегации: $sql');
      print('📌 Параметры: $params');

      final stmt = await _conn!.prepare(sql);
      try {
        for (int i = 0; i < params.length; i++) {
          stmt.bind(params[i], i + 1);
        }

        final result = await stmt.execute();
        final rows = result.fetchAll();
        final columnNames = result.columnNames;
        await result.dispose();

        if (rows.isEmpty) return {};

        final row = rows.first;
        final aggregatedData = <String, dynamic>{};
        for (int i = 0; i < columnNames.length; i++) {
          aggregatedData[columnNames[i]] = row[i];
        }

        // 👇 ДОБАВИТЬ ЛОГИРОВАНИЕ КЛЮЧЕЙ И ЗНАЧЕНИЙ
        print('📊 Ключи агрегированных данных: ${aggregatedData.keys}');
        if (aggregatedData.containsKey('total_quantity')) {
          print('total_quantity = ${aggregatedData['total_quantity']} (тип: ${aggregatedData['total_quantity'].runtimeType})');
        } else {
          print('⚠️ total_quantity отсутствует в результатах');
        }

        return aggregatedData;
      } finally {
        await stmt.dispose();
      }
    } catch (e) {
      print('❌ Ошибка выполнения запроса getAggregatedData: $e');
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
      String sql = 'SELECT COUNT(*) as count FROM reports WHERE 1=1';
      final params = <dynamic>[];

      // Базовые фильтры
      if (dateFrom != null) {
        sql += ' AND report_date >= ?';
        params.add(dateFrom.toIso8601String());
      }

      if (dateTo != null) {
        sql += ' AND report_date <= ?';
        params.add(dateTo.toIso8601String());
      }

      if (nmId != null) {
        sql += ' AND nm_id = ?';
        params.add(nmId);
      }

      if (saName != null && saName.isNotEmpty) {
        sql += ' AND sa_name LIKE ?';
        params.add('%$saName%');
      }

      // Дополнительные фильтры по полям
      if (filters != null && filters.isNotEmpty) {
        filters.forEach((field, values) {
          if (values.isNotEmpty) {
            final nonNullValues = values.where((v) => v != null).toList();
            final hasNull = values.any((v) => v == null);

            if (nonNullValues.isNotEmpty && hasNull) {
              final placeholders = List.filled(nonNullValues.length, '?').join(',');
              sql += ' AND ("$field" IN ($placeholders) OR "$field" IS NULL)';
              params.addAll(nonNullValues);
            } else if (nonNullValues.isNotEmpty) {
              final placeholders = List.filled(nonNullValues.length, '?').join(',');
              sql += ' AND "$field" IN ($placeholders)';
              params.addAll(nonNullValues);
            } else if (hasNull) {
              sql += ' AND "$field" IS NULL';
            }
          }
        });
      }

      final stmt = await _conn!.prepare(sql);

      try {
        for (int i = 0; i < params.length; i++) {
          stmt.bind(params[i], i + 1);
        }

        final result = await stmt.execute();
        final rows = result.fetchAll();
        await result.dispose();

        if (rows.isNotEmpty && rows[0].isNotEmpty) {
          return (rows[0][0] as int?) ?? 0;
        }
        return 0;
      } finally {
        await stmt.dispose();
      }
    } catch (e) {
      print('❌ Ошибка выполнения запроса getTotalCountWithFilters: $e');
      return 0;
    }
  }

  // Добавить в lib/services/database_service.dart после других методов getAggregatedData

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
    int? limit,
    int? offset,
  }) async {
    if (!_isInitialized) {
      try {
        await init();
      } catch (e) {
        print('❌ Ошибка инициализации базы: $e');
        return [];
      }
    }

    try {
      // Получаем все поля модели
      final allFields = ReportDetail.getFieldNames();

      // Получаем кастомные колонки и их формулы
      final customFormulas = await getCustomFormulas(); // Map<String, String>
      final customFields = customFormulas.keys.toSet();

      // Функция для получения выражения для поля (с учётом кастомности)
      String exprForField(String field) {
        if (customFields.contains(field)) {
          return '(${customFormulas[field]})';
        } else {
          return '"$field"';
        }
      }

      // Строим динамический SELECT
      final selectParts = <String>[];
      final fieldMap = <String, String>{}; // Карта: псевдоним -> исходное поле

      // Добавляем поле для группировки (может быть кастомным)
      final groupByExpr = exprForField(groupByField);
      selectParts.add('$groupByExpr AS "$groupByField"');
      // groupByField не попадает в fieldMap, т.к. остаётся под своим именем

      // Для каждого стандартного поля (кроме группируемого) применяем метод агрегации
      for (final field in allFields) {
        if (field == groupByField) continue;

        final method = aggregationMethods?[field] ?? 'none';
        if (method == 'none') continue;

        // Определяем выражение агрегации в зависимости от типа поля и метода
        final dataType = ReportDetail.getFieldDataType(field);
        String? aggregationExpr;
        final fieldExpr = exprForField(field);

        if (dataType == 'currency' || dataType == 'percent' ||
            dataType == 'integer' || field == 'quantity' ||
            field == 'delivery_amount' || field == 'return_amount') {
          // Числовые поля
          switch (method) {
            case 'sum':
              aggregationExpr = 'SUM($fieldExpr)';
              break;
            case 'average':
            case 'mean_without_null':
              aggregationExpr = 'AVG($fieldExpr)';
              break;
            case 'mean_with_null':
              aggregationExpr = 'AVG(COALESCE($fieldExpr, 0))';
              break;
            case 'max':
              aggregationExpr = 'MAX($fieldExpr)';
              break;
            case 'min':
              aggregationExpr = 'MIN($fieldExpr)';
              break;
            case 'first_non_empty':                   // <-- добавляем
              aggregationExpr = 'FIRST($fieldExpr) FILTER (WHERE $fieldExpr IS NOT NULL)';
              break;
            default:
              aggregationExpr = null;
          }
        } else {
          // Текстовые поля
          switch (method) {
            case 'count_unique':
              aggregationExpr = 'COUNT(DISTINCT $fieldExpr)';
              break;
            case 'concat':
              aggregationExpr = 'STRING_AGG(COALESCE($fieldExpr, \'\'), \', \')';
              break;
            case 'first_non_empty':
              aggregationExpr = 'FIRST($fieldExpr) FILTER (WHERE $fieldExpr IS NOT NULL)';
              break;
            default:
              aggregationExpr = null;
          }
        }

        if (aggregationExpr != null) {
          final alias = '${field}_${method}';
          selectParts.add('$aggregationExpr AS "$alias"');
          fieldMap[alias] = field;
        }
      }

      // ========== ДОБАВЛЯЕМ ОБРАБОТКУ КАСТОМНЫХ ПОЛЕЙ ==========
      for (final field in customFields) {
        if (field == groupByField) continue;
        final method = aggregationMethods?[field] ?? 'none';
        if (method == 'none') continue;

        // Для кастомных полей формула уже обёрнута в COALESCE при создании
        final fieldExpr = customFormulas[field]!;
        // По умолчанию считаем кастомные поля числовыми (DOUBLE)
        String? aggregationExpr;
        switch (method) {
          case 'sum':
            aggregationExpr = 'SUM($fieldExpr)';
            break;
          case 'average':
          case 'mean_without_null':
            aggregationExpr = 'AVG($fieldExpr)';
            break;
          case 'mean_with_null':
            aggregationExpr = 'AVG(COALESCE($fieldExpr, 0))';
            break;
          case 'max':
            aggregationExpr = 'MAX($fieldExpr)';
            break;
          case 'min':
            aggregationExpr = 'MIN($fieldExpr)';
            break;
          case 'first_non_empty':                     // <-- добавляем
            aggregationExpr = 'FIRST($fieldExpr) FILTER (WHERE $fieldExpr IS NOT NULL)';
            break;
          default:
            aggregationExpr = null;
        }

        if (aggregationExpr != null) {
          final alias = '${field}_${method}';
          selectParts.add('$aggregationExpr AS "$alias"');
          fieldMap[alias] = field;
        }
      }
      // =========================================================

      if (selectParts.length <= 1) {
        // Нет полей для агрегации (только группирующее поле)
        return [];
      }

      final selectClause = selectParts.join(',\n');

      String sql = '''
      SELECT 
        $selectClause
      FROM reports 
      WHERE 1=1
    ''';

      final params = <dynamic>[];

      // Базовые фильтры
      if (dateFrom != null) {
        sql += ' AND report_date >= ?';
        params.add(dateFrom.toIso8601String());
      }

      if (dateTo != null) {
        sql += ' AND report_date <= ?';
        params.add(dateTo.toIso8601String());
      }

      if (nmId != null) {
        sql += ' AND nm_id = ?';
        params.add(nmId);
      }

      if (saName != null && saName.isNotEmpty) {
        sql += ' AND sa_name LIKE ?';
        params.add('%$saName%');
      }

      // Дополнительные фильтры по полям (включая кастомные)
      if (filters != null && filters.isNotEmpty) {
        filters.forEach((field, values) {
          if (values.isEmpty) return;
          final isCustom = customFields.contains(field);
          final fieldExpr = isCustom ? '(${customFormulas[field]})' : '"$field"';

          final nonNullValues = values.where((v) => v != null).toList();
          final hasNull = values.any((v) => v == null);

          if (nonNullValues.isNotEmpty && hasNull) {
            final placeholders = List.filled(nonNullValues.length, '?').join(',');
            sql += ' AND ($fieldExpr IN ($placeholders) OR $fieldExpr IS NULL)';
            params.addAll(nonNullValues);
          } else if (nonNullValues.isNotEmpty) {
            final placeholders = List.filled(nonNullValues.length, '?').join(',');
            sql += ' AND $fieldExpr IN ($placeholders)';
            params.addAll(nonNullValues);
          } else if (hasNull) {
            sql += ' AND $fieldExpr IS NULL';
          }
        });
      }

      // GROUP BY
      sql += '\nGROUP BY $groupByExpr';

      // Сортировка
      if (sortField != null) {
        final isCustomSortField = customFields.contains(sortField);
        if (sortField == groupByField) {
          sql += '\nORDER BY $groupByExpr ${sortDesc ? 'DESC' : 'ASC'}';
        } else {
          final method = aggregationMethods?[sortField] ?? 'none';
          if (method != 'none') {
            final alias = '${sortField}_${method}';
            sql += '\nORDER BY "$alias" ${sortDesc ? 'DESC' : 'ASC'}';
          } else if (isCustomSortField) {
            // Если поле кастомное, но метод 'none', оно отсутствует в SELECT,
            // поэтому сортируем по группируемому полю
            sql += '\nORDER BY $groupByExpr ${sortDesc ? 'DESC' : 'ASC'}';
          } else {
            sql += '\nORDER BY $groupByExpr ${sortDesc ? 'DESC' : 'ASC'}';
          }
        }
      } else {
        sql += '\nORDER BY $groupByExpr ${sortDesc ? 'DESC' : 'ASC'}';
      }

      // Пагинация
      if (limit != null) {
        sql += ' LIMIT $limit';
        if (offset != null) {
          sql += ' OFFSET $offset';
        }
      }

      print('🔍 SQL агрегации по столбцу (с кастомными):');
      print(sql);
      print('Параметры: $params');

      final stmt = await _conn!.prepare(sql);

      try {
        for (int i = 0; i < params.length; i++) {
          stmt.bind(params[i], i + 1);
        }

        final result = await stmt.execute();
        final rows = result.fetchAll();
        final columnNames = result.columnNames;
        await result.dispose();

        print('✅ Получено групп: ${rows.length}');

        final List<Map<String, dynamic>> aggregatedData = [];

        for (final row in rows) {
          final record = <String, dynamic>{};

          for (int i = 0; i < columnNames.length; i++) {
            final columnName = columnNames[i];
            final value = row[i];

            if (columnName == groupByField) {
              record[columnName] = value;
            } else {
              final originalField = fieldMap[columnName];
              if (originalField != null) {
                record[originalField] = value;
              }
            }
          }

          // Добавляем недостающие стандартные поля с null
          for (final field in allFields) {
            if (!record.containsKey(field) && field != groupByField) {
              record[field] = null;
            }
          }

          // Добавляем недостающие кастомные поля с null
          for (final field in customFields) {
            if (!record.containsKey(field) && field != groupByField) {
              record[field] = null;
            }
          }

          // Вычисляем total
          final totalValue = _calculateTotalForRecord(record);
          record['total'] = totalValue;

          aggregatedData.add(record);
        }

        return aggregatedData;
      } finally {
        await stmt.dispose();
      }
    } catch (e) {
      print('❌ Ошибка выполнения агрегации по столбцу: $e');
      return [];
    }
  }

  Future<void> updateCustomColumn(String columnName, String newDisplayName, String newFormula) async {
    if (!_isInitialized) await init();

    // Получаем все поля для безопасной обёртки формулы
    final baseFields = ReportDetail.getFieldNames().toSet();
    final existingCustom = (await getCustomColumns())
        .map((c) => c['column_name'] as String)
        .toSet();
    final allFields = baseFields.union(existingCustom);

    // Преобразуем формулу с COALESCE для всех упомянутых полей
    final safeFormula = _wrapFormulaFields(newFormula, allFields);

    final stmt = await _conn!.prepare(
        'UPDATE custom_columns SET display_name = ?, formula = ? WHERE column_name = ?'
    );
    try {
      stmt.bind(newDisplayName, 1);
      stmt.bind(safeFormula, 2);
      stmt.bind(columnName, 3);
      await stmt.execute();
    } finally {
      await stmt.dispose();
    }
  }

  // ========== МЕТОД ДЛЯ ДАННЫХ ГРАФИКА ==========
  Future<List<Map<String, dynamic>>> getTimeSeriesData({
    required String dateColumn,
    required String valueColumn,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
    Map<String, List<dynamic>>? filters,
  }) async {
    if (!_isInitialized) await init();

    try {
      // Получаем все кастомные формулы
      final customFormulas = await getCustomFormulas(); // Map<columnName, formula>

      // Определяем выражение для valueColumn
      final valueExpr = customFormulas.containsKey(valueColumn)
          ? '(${customFormulas[valueColumn]})'
          : '"$valueColumn"';

      // Формируем базовый SQL
      String sql = '''
    SELECT 
      CAST("$dateColumn" AS DATE) as date,
      SUM($valueExpr) as total
    FROM reports 
    WHERE 1=1
    ''';

      final params = <dynamic>[];

      // Базовые фильтры
      if (dateFrom != null) {
        sql += ' AND report_date >= ?';
        params.add(dateFrom.toIso8601String());
      }
      if (dateTo != null) {
        sql += ' AND report_date <= ?';
        params.add(dateTo.toIso8601String());
      }
      if (nmId != null) {
        sql += ' AND nm_id = ?';
        params.add(nmId);
      }
      if (saName != null && saName.isNotEmpty) {
        sql += ' AND sa_name LIKE ?';
        params.add('%$saName%');
      }

      // Дополнительные фильтры по полям (включая кастомные)
      if (filters != null && filters.isNotEmpty) {
        for (final entry in filters.entries) {
          final field = entry.key;
          final values = entry.value;
          if (values.isEmpty) continue;

          // Определяем выражение для поля фильтра (кастомное или обычное)
          final fieldExpr = customFormulas.containsKey(field)
              ? '(${customFormulas[field]})'
              : '"$field"';

          final nonNullValues = values.where((v) => v != null).toList();
          final hasNull = values.any((v) => v == null);

          if (nonNullValues.isNotEmpty && hasNull) {
            final placeholders = List.filled(nonNullValues.length, '?').join(',');
            sql += ' AND ($fieldExpr IN ($placeholders) OR $fieldExpr IS NULL)';
            params.addAll(nonNullValues);
          } else if (nonNullValues.isNotEmpty) {
            final placeholders = List.filled(nonNullValues.length, '?').join(',');
            sql += ' AND $fieldExpr IN ($placeholders)';
            params.addAll(nonNullValues);
          } else if (hasNull) {
            sql += ' AND $fieldExpr IS NULL';
          }
        }
      }

      sql += '''
    GROUP BY CAST("$dateColumn" AS DATE)
    ORDER BY date
    ''';

      final stmt = await _conn!.prepare(sql);
      try {
        for (int i = 0; i < params.length; i++) {
          stmt.bind(params[i], i + 1);
        }
        final result = await stmt.execute();
        final rows = result.fetchAll();
        final columnNames = result.columnNames;
        await result.dispose();

        final List<Map<String, dynamic>> data = [];
        for (final row in rows) {
          final record = <String, dynamic>{};
          for (int i = 0; i < columnNames.length; i++) {
            final col = columnNames[i];
            var val = row[i];

            if (col == 'date') {
              if (val == null) continue;
              // Универсальное преобразование даты
              try {
                val = DateTime.parse(val.toString());
              } catch (e) {
                val = null;
              }
            }
            record[col] = val;
          }
          if (record['date'] != null) {
            data.add(record);
          }
        }
        return data;
      } finally {
        await stmt.dispose();
      }
    } catch (e) {
      print('❌ Ошибка получения данных для графика: $e');
      return [];
    }
  }

// В lib/services/database_service.dart добавить:

  Future<int> getAggregatedGroupCount({
    required String groupByField,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
    Map<String, List<dynamic>>? filters,
  }) async {
    if (!_isInitialized) {
      try {
        await init();
      } catch (e) {
        print('❌ Ошибка инициализации базы: $e');
        return 0;
      }
    }

    try {
      String sql = 'SELECT COUNT(DISTINCT "$groupByField") as count FROM reports WHERE 1=1';
      final params = <dynamic>[];

      // Базовые фильтры
      if (dateFrom != null) {
        sql += ' AND report_date >= ?';
        params.add(dateFrom.toIso8601String());
      }

      if (dateTo != null) {
        sql += ' AND report_date <= ?';
        params.add(dateTo.toIso8601String());
      }

      if (nmId != null) {
        sql += ' AND nm_id = ?';
        params.add(nmId);
      }

      if (saName != null && saName.isNotEmpty) {
        sql += ' AND sa_name LIKE ?';
        params.add('%$saName%');
      }

      // Дополнительные фильтры по полям
      if (filters != null && filters.isNotEmpty) {
        filters.forEach((field, values) {
          if (values.isNotEmpty) {
            final nonNullValues = values.where((v) => v != null).toList();
            final hasNull = values.any((v) => v == null);

            if (nonNullValues.isNotEmpty && hasNull) {
              final placeholders = List.filled(nonNullValues.length, '?').join(',');
              sql += ' AND ("$field" IN ($placeholders) OR "$field" IS NULL)';
              params.addAll(nonNullValues);
            } else if (nonNullValues.isNotEmpty) {
              final placeholders = List.filled(nonNullValues.length, '?').join(',');
              sql += ' AND "$field" IN ($placeholders)';
              params.addAll(nonNullValues);
            } else if (hasNull) {
              sql += ' AND "$field" IS NULL';
            }
          }
        });
      }

      final stmt = await _conn!.prepare(sql);

      try {
        for (int i = 0; i < params.length; i++) {
          stmt.bind(params[i], i + 1);
        }

        final result = await stmt.execute();
        final rows = result.fetchAll();
        await result.dispose();

        if (rows.isNotEmpty && rows[0].isNotEmpty) {
          return (rows[0][0] as int?) ?? 0;
        }
        return 0;
      } finally {
        await stmt.dispose();
      }
    } catch (e) {
      print('❌ Ошибка подсчета групп: $e');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getDataWithOptions({
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
    Map<String, List<dynamic>>? filters,
    String? sortField,
    bool sortDesc = true,
    int limit = 50,
    int offset = 0,
    String? groupByField,  // Если null - обычные данные, если не null - группировка
    Map<String, String>? aggregationMethods,  // Методы агрегации
  }) async {
    if (!_isInitialized) await init();

    try {
      if (groupByField != null && aggregationMethods != null) {
        // Агрегированные данные с пагинацией
        return await getAggregatedByColumn(
          groupByField: groupByField,
          dateFrom: dateFrom,
          dateTo: dateTo,
          nmId: nmId,
          saName: saName,
          filters: filters,
          aggregationMethods: aggregationMethods,
          sortField: sortField,
          sortDesc: sortDesc,
          limit: limit,
          offset: offset,
        );
      } else {
        // Обычные данные с пагинацией
        return await getReportsPaginated(
          dateFrom: dateFrom,
          dateTo: dateTo,
          nmId: nmId,
          saName: saName,
          filters: filters,
          sortField: sortField,
          sortDesc: sortDesc,
          limit: limit,
          offset: offset,
        );
      }
    } catch (e) {
      print('❌ Ошибка выполнения запроса getDataWithOptions: $e');
      return [];
    }
  }

  Future<int> getTotalCountWithOptions({
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
    Map<String, List<dynamic>>? filters,
    String? groupByField,  // Если группировка - считаем количество групп
    Map<String, String>? aggregationMethods,
  }) async {
    if (groupByField != null && aggregationMethods != null) {
      // Для агрегированных данных считаем количество уникальных групп
      try {
        String sql = 'SELECT COUNT(DISTINCT "$groupByField") as count FROM reports WHERE 1=1';
        final params = <dynamic>[];

        // Фильтры (такие же как в getAggregatedByColumn)
        if (dateFrom != null) {
          sql += ' AND report_date >= ?';
          params.add(dateFrom.toIso8601String());
        }

        if (dateTo != null) {
          sql += ' AND report_date <= ?';
          params.add(dateTo.toIso8601String());
        }

        if (nmId != null) {
          sql += ' AND nm_id = ?';
          params.add(nmId);
        }

        if (saName != null && saName.isNotEmpty) {
          sql += ' AND sa_name LIKE ?';
          params.add('%$saName%');
        }

        // Фильтры по полям
        if (filters != null && filters.isNotEmpty) {
          filters.forEach((field, values) {
            if (values.isNotEmpty) {
              final nonNullValues = values.where((v) => v != null).toList();
              final hasNull = values.any((v) => v == null);

              if (nonNullValues.isNotEmpty && hasNull) {
                final placeholders = List.filled(nonNullValues.length, '?').join(',');
                sql += ' AND ("$field" IN ($placeholders) OR "$field" IS NULL)';
                params.addAll(nonNullValues);
              } else if (nonNullValues.isNotEmpty) {
                final placeholders = List.filled(nonNullValues.length, '?').join(',');
                sql += ' AND "$field" IN ($placeholders)';
                params.addAll(nonNullValues);
              } else if (hasNull) {
                sql += ' AND "$field" IS NULL';
              }
            }
          });
        }

        final stmt = await _conn!.prepare(sql);

        try {
          for (int i = 0; i < params.length; i++) {
            stmt.bind(params[i], i + 1);
          }

          final result = await stmt.execute();
          final rows = result.fetchAll();
          await result.dispose();

          if (rows.isNotEmpty && rows[0].isNotEmpty) {
            return (rows[0][0] as int?) ?? 0;
          }
          return 0;
        } finally {
          await stmt.dispose();
        }
      } catch (e) {
        print('❌ Ошибка подсчета групп: $e');
        return 0;
      }
    } else {
      // Для обычных данных используем существующий метод
      return await getTotalCountWithFilters(
        dateFrom: dateFrom,
        dateTo: dateTo,
        nmId: nmId,
        saName: saName,
        filters: filters,
      );
    }
  }

// Вспомогательный метод для вычисления total
  double _calculateTotalForRecord(Map<String, dynamic> record) {
    // Список полей для суммирования (аналогичен _totalFields)
    final totalFields = [
      'retail_price',
      'retail_price_recovery',
      'retail_amount',
      'retail_amount_refunded',
      'ppvz_for_pay',
      'ppvz_for_recovery',
      'cost_price',
      'cost_price_recovered',
      'additional_expenses',
      'additional_expenses_recovered',
      'commission_amount',
      'commission_amount_reversed',
      'commission_normal',
      'commission_normal_reversed',
      'penalty_commission_rub',
      'penalty_commission_reversed',
      'delivery_rub',
      'return_delivery_rub',
      'ppvz_reward',
      'ppvz_reward_reversed',
      'acquiring_fee',
      'acquiring_fee_reversed',
      'acceptance',
      'cashback_amount',
      'cashback_amount_reversed',
      'cashback_commission_change',
      'cashback_commission_change_reversed',
      'storage_fee',
      'penalty',
      'deduction',
      'additional_payment',
      'payment_schedule',
    ];

    double total = 0.0;

    for (final field in totalFields) {
      final value = record[field];
      if (value is num) {
        total += value.toDouble();
      }
    }

    return total;
  }

  Future<void> importParquetDirectly(String parquetPath) async {
    if (_conn == null) {
      await init();
    }

    try {
      print('📥 Прямой импорт Parquet в DuckDB...');

      final tableColumnsResult = await _conn!.query("PRAGMA table_info(reports)");
      final tableColumns = tableColumnsResult.fetchAll();
      await tableColumnsResult.dispose();

      final parquetColumnsResult = await _conn!.query(
          "DESCRIBE SELECT * FROM read_parquet('${parquetPath.replaceAll('\\', '/')}')"
      );
      final parquetColumns = parquetColumnsResult.fetchAll();
      await parquetColumnsResult.dispose();

      final List<String> selectColumns = [];
      final List<String> insertColumns = [];

      for (final tableCol in tableColumns) {
        final tableColName = tableCol[1] as String;

        for (final parquetCol in parquetColumns) {
          final parquetColName = parquetCol[0] as String;
          if (tableColName.toLowerCase() == parquetColName.toLowerCase()) {
            selectColumns.add('"$parquetColName"');
            insertColumns.add('"$tableColName"');
            break;
          }
        }
      }

      if (selectColumns.isEmpty) {
        throw Exception('Не найдено совпадающих колонок между таблицей и Parquet файлом');
      }

      final selectClause = selectColumns.join(', ');
      final insertClause = insertColumns.join(', ');

      await _conn!.execute('''
      INSERT INTO reports ($insertClause)
      SELECT $selectClause FROM read_parquet('${parquetPath.replaceAll('\\', '/')}')
      ON CONFLICT (rrd_id) DO NOTHING
    ''');

      print('✅ Прямой импорт завершен');

    } catch (e) {
      print('❌ Ошибка прямого импорта: $e');
      await importParquetFile(parquetPath);
    }
  }

  String _getColumnType(String parquetCol, String tableCol) {
    if (parquetCol.contains('_id') || parquetCol.contains('uid') || parquetCol == 'rrd_id') {
      return 'VARCHAR';
    }

    if (parquetCol.contains('_dt') || parquetCol.contains('date') || parquetCol.contains('_at')) {
      return 'TIMESTAMP';
    }

    if (parquetCol.contains('_percent') || parquetCol.contains('_prc') || parquetCol.endsWith('_prc')) {
      return 'DOUBLE';
    }

    if (parquetCol.contains('quantity') || parquetCol.contains('amount') ||
        parquetCol.contains('hours') || parquetCol == 'nm_id' || parquetCol == 'id') {
      return 'INTEGER';
    }

    if (parquetCol.contains('price') || parquetCol.contains('fee') ||
        parquetCol.contains('commission') || parquetCol.contains('rub') ||
        parquetCol.contains('discount') || parquetCol.contains('percent')) {
      return 'DOUBLE';
    }

    return 'VARCHAR';
  }

  Future<void> importParquetFile(String parquetPath) async {
    if (_conn == null) {
      await init();
    }

    try {
      print('📥 Импорт данных из Parquet файла напрямую в DuckDB...');

      final tableColumnsResult = await _conn!.query("PRAGMA table_info(reports)");
      final tableColumns = tableColumnsResult.fetchAll();
      await tableColumnsResult.dispose();

      final parquetColumnsResult = await _conn!.query(
          "DESCRIBE SELECT * FROM read_parquet('${parquetPath.replaceAll('\\', '/')}')"
      );
      final parquetColumns = parquetColumnsResult.fetchAll();
      await parquetColumnsResult.dispose();

      final List<String> selectColumns = [];
      final List<String> insertColumns = [];

      for (final tableCol in tableColumns) {
        final tableColName = tableCol[1] as String;

        for (final parquetCol in parquetColumns) {
          final parquetColName = parquetCol[0] as String;
          if (tableColName.toLowerCase() == parquetColName.toLowerCase()) {
            selectColumns.add('"$parquetColName"');
            insertColumns.add('"$tableColName"');
            break;
          }
        }
      }

      if (selectColumns.isEmpty) {
        throw Exception('Не найдено совпадающих колонок между таблицей и Parquet файлом');
      }

      final selectClause = selectColumns.join(', ');
      final insertClause = insertColumns.join(', ');

      await _conn!.execute('''
      CREATE TEMP TABLE temp_parquet_data AS 
      SELECT $selectClause FROM read_parquet('${parquetPath.replaceAll('\\', '/')}')
    ''');

      await _conn!.execute('''
      INSERT INTO reports ($insertClause)
      SELECT $selectClause FROM temp_parquet_data
      ON CONFLICT (rrd_id) DO NOTHING
    ''');

      print('✅ Импортировано данных из Parquet файла');

      await _conn!.execute('DROP TABLE temp_parquet_data');

    } catch (e) {
      print('❌ Ошибка импорта Parquet файла: $e');
      rethrow;
    }
  }

  Future<void> _createTables() async {
    await _conn!.execute('''
    CREATE TABLE IF NOT EXISTS reports (
      rrd_id TEXT PRIMARY KEY,
      id TEXT,
      srid TEXT,
      operation_quantity INTEGER,
      shk_id TEXT,
      sticker_id TEXT,
      assembly_id TEXT,
      nm_id INTEGER,
      sa_name TEXT,
      barcode TEXT,
      gi_id TEXT,
      ppvz_office_id TEXT,
      order_uid TEXT,
      trbx_id TEXT,
      seller_promo_id TEXT,
      loyalty_id TEXT,
      uuid_promocode TEXT,
      subject_name TEXT,
      brand_name TEXT,
      ts_name TEXT,
      doc_type_name TEXT,
      supplier_oper_name TEXT,
      bonus_type_name TEXT,
      payment_processing TEXT,
      rr_dt TIMESTAMP,
      order_dt TIMESTAMP,
      sale_dt TIMESTAMP,
      delivery_time_hours INTEGER,
      type_fb TEXT,
      delivery_method TEXT,
      gi_box_type_name TEXT,
      site_country TEXT,
      office_name TEXT,
      ppvz_office_name TEXT,
      dlv_prc DOUBLE,
      acquiring_percent DOUBLE,
      commission_percent DOUBLE,
      base_comission DOUBLE,
      penalty_commission_percent DOUBLE,
      is_kgvp_v2 DOUBLE,
      loyalty_discount DOUBLE,
      ppvz_kvw_prc DOUBLE,
      ppvz_kvw_prc_base DOUBLE,
      ppvz_spp_prc DOUBLE,
      product_discount_for_report DOUBLE,
      sale_percent DOUBLE,
      sale_price_promocode_discount_prc DOUBLE,
      seller_promo_discount DOUBLE,
      sup_rating_prc_up DOUBLE,
      supplier_promo DOUBLE,
      wibes_wb_discount_percent DOUBLE,
      quantity INTEGER,
      delivery_amount INTEGER,
      return_amount INTEGER,
      retail_price DOUBLE,
      retail_price_recovery DOUBLE,
      retail_amount DOUBLE,
      retail_amount_refunded DOUBLE,
      ppvz_for_pay DOUBLE,
      ppvz_for_recovery DOUBLE,
      cost_price DOUBLE,
      cost_price_recovered DOUBLE,
      additional_expenses DOUBLE,
      additional_expenses_recovered DOUBLE,
      commission_amount DOUBLE,
      commission_amount_reversed DOUBLE,
      commission_normal DOUBLE,
      commission_normal_reversed DOUBLE,
      penalty_commission_rub DOUBLE,
      penalty_commission_reversed DOUBLE,
      delivery_rub DOUBLE,
      return_delivery_rub DOUBLE,
      ppvz_reward DOUBLE,
      ppvz_reward_reversed DOUBLE,
      acquiring_fee DOUBLE,
      acquiring_fee_reversed DOUBLE,
      acceptance DOUBLE,
      cashback_amount DOUBLE,
      cashback_amount_reversed DOUBLE,
      cashback_commission_change DOUBLE,
      cashback_commission_change_reversed DOUBLE,
      storage_fee DOUBLE,
      penalty DOUBLE,
      deduction DOUBLE,
      installment_cofinancing_amount DOUBLE,
      additional_payment DOUBLE,
      payment_schedule DOUBLE,
      report_date TIMESTAMP,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ''');

    await _conn!.execute('CREATE INDEX IF NOT EXISTS idx_reports_nm_id ON reports(nm_id)');
    await _conn!.execute('CREATE INDEX IF NOT EXISTS idx_reports_report_date ON reports(report_date)');
    await _conn!.execute('CREATE INDEX IF NOT EXISTS idx_reports_rr_dt ON reports(rr_dt)');
    await _conn!.execute('CREATE INDEX IF NOT EXISTS idx_reports_sa_name ON reports(sa_name)');

    await _conn!.execute('''
    CREATE TABLE IF NOT EXISTS sync_status (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      last_sync_date TIMESTAMP,
      total_records INTEGER,
      last_error TEXT
    )
  ''');

    await _conn!.execute('''
    CREATE TABLE IF NOT EXISTS date_cache (
      date DATE PRIMARY KEY,
      has_local_data BOOLEAN,
      has_server_data BOOLEAN,
      checked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ''');

    await _conn!.execute('''
    CREATE TABLE IF NOT EXISTS custom_columns (
      id INTEGER PRIMARY KEY,
      column_name TEXT UNIQUE,
      display_name TEXT,
      formula TEXT,
      data_type TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  }

  // Новый метод для получения данных как Map (без ReportDetail)
  Future<List<Map<String, dynamic>>> getReports({
    DateTime? dateFrom,
    DateTime? dateTo,
    int? nmId,
    String? saName,
    int? limit,
  }) async {
    if (!_isInitialized) {
      try {
        await init();
      } catch (e) {
        print('❌ Ошибка инициализации базы: $e');
        return [];
      }
    }

    try {
      String sql = 'SELECT * FROM reports WHERE 1=1';
      final params = <dynamic>[];

      if (dateFrom != null) {
        sql += ' AND report_date >= ?';
        params.add(dateFrom.toIso8601String());
      }

      if (dateTo != null) {
        sql += ' AND report_date <= ?';
        params.add(dateTo.toIso8601String());
      }

      if (nmId != null) {
        sql += ' AND nm_id = ?';
        params.add(nmId);
      }

      if (saName != null && saName.isNotEmpty) {
        sql += ' AND sa_name LIKE ?';
        params.add('%$saName%');
      }

      sql += ' ORDER BY report_date DESC';

      if (limit != null) {
        sql += ' LIMIT $limit';
      }

      final stmt = await _conn!.prepare(sql);

      try {
        for (int i = 0; i < params.length; i++) {
          stmt.bind(params[i], i + 1);
        }

        final result = await stmt.execute();
        final rows = result.fetchAll();
        final columnNames = result.columnNames;
        await result.dispose();

        final List<Map<String, dynamic>> data = [];

        for (final row in rows) {
          final record = <String, dynamic>{};

          for (int i = 0; i < columnNames.length; i++) {
            final columnName = columnNames[i];
            final value = row[i];

            // Корректируем типы данных для полей дат
            if (columnName.endsWith('_dt') ||
                columnName == 'report_date' ||
                columnName == 'created_at' ||
                columnName == 'updated_at') {
              if (value is String) {
                try {
                  record[columnName] = DateTime.parse(value);
                } catch (e) {
                  record[columnName] = null;
                }
              } else if (value is DateTime) {
                record[columnName] = value;
              } else {
                record[columnName] = null;
              }
            } else {
              record[columnName] = value;
            }
          }

          data.add(record);
        }

        return data;
      } finally {
        await stmt.dispose();
      }
    } catch (e) {
      print('❌ Ошибка выполнения запроса getReports: $e');
      return [];
    }
  }

  // Получить все кастомные колонки
  Future<List<Map<String, dynamic>>> getCustomColumns() async {
    if (!_isInitialized) await init();
    try {
      final result = await _conn!.query('SELECT * FROM custom_columns ORDER BY id');
      final rows = result.fetchAll();
      final columnNames = result.columnNames;
      await result.dispose();
      return rows.map((row) => Map.fromIterables(columnNames, row)).toList();
    } catch (e) {
      print('❌ Ошибка получения кастомных колонок: $e');
      return [];
    }
  }

// Добавить новую кастомную колонку
  Future<void> addCustomColumn(String displayName, String formula) async {
    if (!_isInitialized) await init();

    // Получаем все существующие поля (базовые + уже созданные кастомные)
    final baseFields = ReportDetail.getFieldNames().toSet();
    final existingCustom = (await getCustomColumns())
        .map((c) => c['column_name'] as String)
        .toSet();
    final allFields = baseFields.union(existingCustom);

    // Преобразуем формулу: заменяем каждое поле на COALESCE(поле, 0)
    final safeFormula = _wrapFormulaFields(formula, allFields);

    const dataType = 'DOUBLE'; // пока всегда число

    final countResult = await _conn!.query('SELECT COUNT(*) FROM custom_columns');
    final count = countResult.fetchAll().first[0] as int;
    await countResult.dispose();
    final nextId = count + 1;
    final columnName = 'custom_$nextId';

    await _conn!.execute('BEGIN TRANSACTION');
    try {

      final stmt = await _conn!.prepare(
          'INSERT INTO custom_columns (id, column_name, display_name, formula, data_type) VALUES (?, ?, ?, ?, ?)'
      );
      stmt.bind(nextId, 1);
      stmt.bind(columnName, 2);
      stmt.bind(displayName, 3);
      stmt.bind(safeFormula, 4);   // ← сохраняем безопасную формулу
      stmt.bind(dataType, 5);
      await stmt.execute();
      await stmt.dispose();

      await _conn!.execute('COMMIT');
      print('✅ Кастомная колонка $columnName добавлена с безопасной формулой: $safeFormula');
    } catch (e) {
      await _conn!.execute('ROLLBACK');
      print('❌ Ошибка добавления кастомной колонки: $e');
      rethrow;
    }
  }

  // Преобразует формулу, заменяя каждое упоминание поля на COALESCE(поле, 0)
  String _wrapFormulaFields(String formula, Set<String> allFieldNames) {
    // Сортируем поля по убыванию длины, чтобы сначала заменять более длинные имена
    final sortedFields = allFieldNames.toList()..sort((a, b) => b.length.compareTo(a.length));
    String result = formula;
    for (final field in sortedFields) {
      // Заменяем только целые слова (используем границы \b)
      final regex = RegExp(r'\b' + RegExp.escape(field) + r'\b');
      result = result.replaceAllMapped(regex, (match) => 'COALESCE(${match.group(0)}, 0)');
    }
    return result;
  }

// Получить маппинг формул для всех кастомных колонок (имя колонки -> формула)
  Future<Map<String, String>> getCustomFormulas() async {
    final cols = await getCustomColumns();
    return {for (var c in cols) c['column_name'] as String: c['formula'] as String};
  }

  Future<int> getTotalCount() async {
    final stmt = await _conn!.prepare('SELECT COUNT(*) as count FROM reports');
    try {
      final result = await stmt.execute();
      final rows = result.fetchAll();
      await result.dispose();

      if (rows.isNotEmpty && rows[0].isNotEmpty) {
        return (rows[0][0] as int?) ?? 0;
      }
      return 0;
    } finally {
      await stmt.dispose();
    }
  }

  Future<void> deleteReportsByDateRange(DateTime startDate, DateTime endDate) async {
    final stmt = await _conn!.prepare(
      'DELETE FROM reports WHERE report_date >= ? AND report_date <= ?',
    );
    try {
      stmt.bind(startDate.toIso8601String(), 1);
      stmt.bind(endDate.toIso8601String(), 2);
      await stmt.execute();
    } finally {
      await stmt.dispose();
    }
  }

  Future<void> clearAllReports() async {
    await _conn!.execute('DELETE FROM reports');
  }

  Future<SyncStatus?> getSyncStatus() async {
    final stmt = await _conn!.prepare('SELECT * FROM sync_status WHERE id = 1');
    try {
      final result = await stmt.execute();
      final rows = result.fetchAll();
      await result.dispose();

      if (rows.isEmpty) return null;

      final row = rows.first;
      final json = <String, dynamic>{};
      final columnNames = result.columnNames;

      for (int i = 0; i < columnNames.length; i++) {
        json[columnNames[i]] = row[i];
      }

      return SyncStatus(
        lastSyncDate: DateTime.parse(json['last_sync_date']),
        totalRecords: json['total_records'] as int,
        lastError: json['last_error'] as String,
      );
    } finally {
      await stmt.dispose();
    }
  }

  Future<void> updateSyncStatusSafe(SyncStatus status) async {
    if (_conn == null) await init();

    try {
      await _conn!.execute('BEGIN TRANSACTION');

      await _conn!.execute('DELETE FROM sync_status WHERE id = 1');

      final stmt = await _conn!.prepare(
        'INSERT INTO sync_status (id, last_sync_date, total_records, last_error) VALUES (1, ?, ?, ?)',
      );

      stmt.bind(status.lastSyncDate.toIso8601String(), 1);
      stmt.bind(status.totalRecords, 2);
      stmt.bind(status.lastError, 3);
      await stmt.execute();
      await stmt.dispose();

      await _conn!.execute('COMMIT');

    } catch (e) {
      await _conn!.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> updateSyncStatus(SyncStatus status) async {
    await _conn!.execute('BEGIN TRANSACTION');
    try {
      await _conn!.execute('DELETE FROM sync_status WHERE id = 1');

      final stmt = await _conn!.prepare(
        'INSERT INTO sync_status (id, last_sync_date, total_records, last_error) VALUES (1, ?, ?, ?)',
      );
      try {
        stmt.bind(status.lastSyncDate.toIso8601String(), 1);
        stmt.bind(status.totalRecords, 2);
        stmt.bind(status.lastError, 3);
        await stmt.execute();
      } finally {
        await stmt.dispose();
      }

      await _conn!.execute('COMMIT');
    } catch (e) {
      await _conn!.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<Map<DateTime, bool>> checkDates(List<DateTime> dates) async {
    final result = <DateTime, bool>{};

    for (final date in dates) {
      final normalizedDate = DateTime.utc(date.year, date.month, date.day);
      final formattedDate = normalizedDate.toIso8601String().split('T')[0];

      final stmt = await _conn!.prepare(
        "SELECT 1 FROM reports WHERE DATE(rr_dt) = DATE(?) LIMIT 1",
      );
      try {
        stmt.bind(formattedDate, 1);
        final queryResult = await stmt.execute();
        final rows = queryResult.fetchAll();
        await queryResult.dispose();
        result[normalizedDate] = rows.isNotEmpty;
      } finally {
        await stmt.dispose();
      }
    }

    return result;
  }

  Future<void> updateDateCache(DateTime date, bool hasLocalData, bool hasServerData) async {
    final normalizedDate = DateTime.utc(date.year, date.month, date.day);
    final dateString = normalizedDate.toIso8601String().split('T')[0];

    final stmt = await _conn!.prepare(
      'INSERT OR REPLACE INTO date_cache (date, has_local_data, has_server_data) VALUES (?, ?, ?)',
    );
    try {
      stmt.bind(dateString, 1);
      stmt.bind(hasLocalData ? 1 : 0, 2);
      stmt.bind(hasServerData ? 1 : 0, 3);
      await stmt.execute();
    } finally {
      await stmt.dispose();
    }
  }

  Future<Map<DateTime, Map<String, bool>>> getDateCache(List<DateTime> dates) async {
    final result = <DateTime, Map<String, bool>>{};

    if (dates.isEmpty) return result;

    final dateStrings = dates.map((d) => d.toIso8601String().split('T')[0]).toList();
    final placeholders = List.filled(dateStrings.length, '?').join(',');

    final sql = '''
    SELECT date, has_local_data, has_server_data 
    FROM date_cache 
    WHERE date IN ($placeholders)
  ''';

    final stmt = await _conn!.prepare(sql);
    try {
      for (int i = 0; i < dateStrings.length; i++) {
        stmt.bind(dateStrings[i], i + 1);
      }

      final cacheResult = await stmt.execute();
      final rows = cacheResult.fetchAll();
      final columnNames = cacheResult.columnNames;
      await cacheResult.dispose();

      for (final row in rows) {
        final json = <String, dynamic>{};
        for (int i = 0; i < columnNames.length; i++) {
          json[columnNames[i]] = row[i];
        }

        final dateValue = json['date'];
        DateTime date;

        if (dateValue is DateTime) {
          date = dateValue;
        } else if (dateValue is String) {
          date = DateTime.parse(dateValue);
        } else {
          try {
            final daysSinceEpoch = dateValue as int;
            date = DateTime.utc(1970, 1, 1).add(Duration(days: daysSinceEpoch));
          } catch (e) {
            continue;
          }
        }

        final normalizedDate = DateTime.utc(date.year, date.month, date.day);

        result[normalizedDate] = {
          'has_local_data': json['has_local_data'] == 1 || json['has_local_data'] == true,
          'has_server_data': json['has_server_data'] == 1 || json['has_server_data'] == true,
        };
      }

      for (final date in dates) {
        if (!result.containsKey(date)) {
          result[date] = {'has_local_data': false, 'has_server_data': false};
        }
      }

      return result;
    } finally {
      await stmt.dispose();
    }
  }

  Future<List<DateTime>> getAvailableDates() async {
    final result = await _conn!.query(
        'SELECT DISTINCT DATE(rr_dt) as date FROM reports WHERE rr_dt IS NOT NULL ORDER BY date'
    );

    final rows = result.fetchAll();
    await result.dispose();

    return rows
        .where((row) => row[0] != null)
        .map((row) => DateTime.parse(row[0].toString()))
        .toList();
  }

  Future<Map<String, dynamic>> getStatistics() async {
    final result = await _conn!.query('''
      SELECT 
        COUNT(*) as total_records,
        MIN(report_date) as min_date,
        MAX(report_date) as max_date,
        SUM(quantity) as total_quantity,
        SUM(retail_amount) as total_retail_amount,
        AVG(commission_amount) as average_commission
      FROM reports
    ''');

    final rows = result.fetchAll();
    final columnNames = result.columnNames;
    await result.dispose();

    if (rows.isEmpty) {
      return {
        'total_records': 0,
        'date_range': 'Нет данных',
        'total_quantity': 0,
        'total_retail_amount': 0,
        'average_commission': 0,
      };
    }

    final row = rows.first;
    final json = <String, dynamic>{};
    for (int i = 0; i < columnNames.length; i++) {
      json[columnNames[i]] = row[i];
    }

    final minDate = json['min_date'] != null ? DateTime.parse(json['min_date']) : null;
    final maxDate = json['max_date'] != null ? DateTime.parse(json['max_date']) : null;

    String dateRange = 'Нет данных';
    if (minDate != null && maxDate != null) {
      dateRange = '${_formatDate(minDate)} - ${_formatDate(maxDate)}';
    }

    return {
      'total_records': json['total_records'] as int? ?? 0,
      'date_range': dateRange,
      'total_quantity': json['total_quantity'] ?? 0,
      'total_retail_amount': ((json['total_retail_amount'] as double?) ?? 0.0).toStringAsFixed(2),
      'average_commission': ((json['average_commission'] as double?) ?? 0.0).toStringAsFixed(2),
    };
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  Future<void> close() async {
    try {
      if (_conn != null) {
        await _conn!.dispose();
        _conn = null;
      }

      if (_db != null) {
        await _db!.dispose();
        _db = null;
      }

      _isInitialized = false;
      print('✅ Соединение с базой данных закрыто');
    } catch (e) {
      print('⚠️ Ошибка при закрытии базы: $e');
      _isInitialized = false;
      _db = null;
      _conn = null;
    }
  }

  Future<void> deleteCustomColumn(String columnName) async {
    if (!_isInitialized) await init();
    try {
      await _conn!.execute('BEGIN TRANSACTION');

      // Удаляем запись из custom_columns через подготовленный запрос
      final deleteStmt = await _conn!.prepare('DELETE FROM custom_columns WHERE column_name = ?');
      deleteStmt.bind(columnName, 1);
      await deleteStmt.execute();
      await deleteStmt.dispose();

      // Удаляем физическую колонку, если она существует (ошибка игнорируется)
      try {
        await _conn!.execute('ALTER TABLE reports DROP COLUMN "$columnName"');
      } catch (e) {
        print('⚠️ Физическая колонка $columnName не найдена или не удалена: $e');
      }

      await _conn!.execute('COMMIT');
      print('✅ Кастомная колонка $columnName удалена');
    } catch (e) {
      await _conn!.execute('ROLLBACK');
      print('❌ Ошибка удаления кастомной колонки $columnName: $e');
      rethrow;
    }
  }
}

