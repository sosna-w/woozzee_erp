// constructor_screen.dart
// Экран конструктора с универсальной таблицей и демо-данными

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'dart:math' as math;
import 'universal_data_table.dart';
import 'package:pluto_grid/pluto_grid.dart';

// ============================================================================
// Демо-провайдер данных для конструктора
// ============================================================================

class ConstructorDataProvider implements DataProvider<Map<String, dynamic>> {
  // Генерация 200 демо-записей
  final List<Map<String, dynamic>> _allData = List.generate(200, (index) {
    final date = DateTime(2024, (index % 12) + 1, (index % 28) + 1);
    return {
      'id': index + 1,
      'name': 'Продукт ${index + 1}',
      'quantity': (index % 100) + 1,
      'price': (index % 1000) + 10.99,
      'date': date,
      'status': index % 3 == 0 ? 'Завершён' : (index % 2 == 0 ? 'В работе' : 'Новый'),
    };
  });

  // Хранилище кастомных колонок (для демонстрации)
  final List<CustomColumn> _customColumns = [];

  // Фильтрация данных
  List<Map<String, dynamic>> _applyFilters(
      List<Map<String, dynamic>> data, FilterSet filters) {
    if (filters.isEmpty) return data;
    return data.where((row) {
      return filters.filters.entries.every((entry) {
        final field = entry.key;
        final allowedValues = entry.value;
        if (allowedValues.isEmpty) return true;
        final cellValue = row[field];
        return allowedValues.contains(cellValue);
      });
    }).toList();
  }

  // Сортировка
  List<Map<String, dynamic>> _applySorting(
      List<Map<String, dynamic>> data, String? sortField, bool sortDesc) {
    if (sortField == null) return data;
    return data.sorted((a, b) {
      final aVal = a[sortField];
      final bVal = b[sortField];
      int cmp = 0;
      if (aVal is num && bVal is num) {
        cmp = aVal.compareTo(bVal);
      } else if (aVal is DateTime && bVal is DateTime) {
        cmp = aVal.compareTo(bVal);
      } else {
        cmp = aVal.toString().compareTo(bVal.toString());
      }
      return sortDesc ? -cmp : cmp;
    });
  }

  // Группировка (простая агрегация: сумма quantity, средняя price)
  List<Map<String, dynamic>> _applyGrouping(
      List<Map<String, dynamic>> data, String? groupByField,
      Map<String, String>? aggregationMethods) {
    if (groupByField == null) return data;

    final groups = <dynamic, List<Map<String, dynamic>>>{};
    for (var row in data) {
      final key = row[groupByField];
      groups.putIfAbsent(key, () => []).add(row);
    }

    final aggregatedRows = <Map<String, dynamic>>[];
    for (var entry in groups.entries) {
      final groupValue = entry.key;
      final groupRows = entry.value;

      final row = <String, dynamic>{
        groupByField: groupValue,
        '_grouped': true,
        '_count': groupRows.length,
      };

      // Агрегация по полям
      for (var field in ['quantity', 'price']) {
        final method = aggregationMethods?[field] ?? 'sum';
        final values = groupRows.map((r) => r[field]).whereType<num>().toList();
        if (values.isEmpty) continue;
        switch (method) {
          case 'sum':
            row[field] = values.fold(0.0, (s, v) => s + v);
            break;
          case 'avg':
            row[field] = values.fold(0.0, (s, v) => s + v) / values.length;
            break;
          case 'count_unique':
            row[field] = values.toSet().length;
            break;
          case 'concat':
            row[field] = groupRows.map((r) => r[field].toString()).join(', ');
            break;
          default:
            row[field] = values.first;
        }
      }
      aggregatedRows.add(row);
    }
    return aggregatedRows;
  }

  @override
  Future<int> getTotalCount({
    required FilterSet filters,
    String? groupByField,
  }) async {
    final filtered = _applyFilters(_allData, filters);
    if (groupByField != null) {
      final grouped = _applyGrouping(filtered, groupByField, null);
      return grouped.length;
    }
    return filtered.length;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchData({
    required int offset,
    required int limit,
    required FilterSet filters,
    String? sortField,
    bool sortDesc = true,
    String? groupByField,
    Map<String, String>? aggregationMethods,
  }) async {
    var filtered = _applyFilters(_allData, filters);
    filtered = _applySorting(filtered, sortField, sortDesc);
    if (groupByField != null) {
      filtered = _applyGrouping(filtered, groupByField, aggregationMethods);
    }
    return filtered.skip(offset).take(limit).toList();
  }

  @override
  Future<List<dynamic>> getUniqueValues({
    required String field,
    required FilterSet filters,
    int maxValues = 1000,
  }) async {
    final filtered = _applyFilters(_allData, filters);
    final values = filtered.map((row) => row[field]).where((v) => v != null).toSet().toList();
    return values.take(maxValues).toList();
  }

  @override
  Future<List<TimeSeriesPoint>> getTimeSeriesData({
    required String dateField,
    required String valueField,
    required FilterSet filters,
  }) async {
    final filtered = _applyFilters(_allData, filters);
    final points = <TimeSeriesPoint>[];
    for (var row in filtered) {
      final date = row[dateField] as DateTime;
      final value = (row[valueField] as num).toDouble();
      points.add(TimeSeriesPoint(date, value));
    }
    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

  @override
  Future<Map<String, dynamic>> getAggregatedTotals({
    required FilterSet filters,
    String? groupByField,
  }) async {
    var filtered = _applyFilters(_allData, filters);
    if (groupByField != null) {
      filtered = _applyGrouping(filtered, groupByField, null);
    }
    final totals = <String, dynamic>{};
    for (var field in ['quantity', 'price']) {
      final values = filtered.map((r) => r[field]).whereType<num>().toList();
      if (values.isEmpty) {
        totals['sum_$field'] = 0.0;
        totals['avg_$field'] = 0.0;
        totals['max_$field'] = 0.0;
        totals['min_$field'] = 0.0;
        totals['count_$field'] = 0;
        continue;
      }
      final sum = values.fold(0.0, (s, v) => s + v);
      totals['sum_$field'] = sum;
      totals['avg_$field'] = sum / values.length;
      totals['max_$field'] = values.reduce((a, b) => a > b ? a : b);
      totals['min_$field'] = values.reduce((a, b) => a < b ? a : b);
      totals['count_$field'] = values.length;
    }
    return totals;
  }

  @override
  Future<int> getAggregatedGroupCount({
    required String groupByField,
    required FilterSet filters,
  }) async {
    return await getTotalCount(filters: filters, groupByField: groupByField);
  }

  @override
  dynamic getFieldValue(Map<String, dynamic> item, String field) {
    return item[field];
  }

  // ==========================================================================
  // Реализация опциональных методов (кастомные колонки, доступные даты)
  // ==========================================================================

  @override
  Future<void> addCustomColumn(String name, String formula) async {
    _customColumns.removeWhere((c) => c.name == name);
    _customColumns.add(CustomColumn(name, name, formula));
  }

  @override
  Future<void> updateCustomColumn(String oldName, String newName, String formula) async {
    final index = _customColumns.indexWhere((c) => c.name == oldName);
    if (index != -1) {
      _customColumns[index] = CustomColumn(newName, newName, formula);
    }
  }

  @override
  Future<void> deleteCustomColumn(String name) async {
    _customColumns.removeWhere((c) => c.name == name);
  }

  @override
  Future<List<CustomColumn>> getCustomColumns() async {
    return List.from(_customColumns);
  }

  @override
  Future<List<DateTime>> getAvailableDates() async {
    final dates = _allData.map((row) => row['date'] as DateTime).toSet().toList();
    dates.sort();
    return dates;
  }
}

// ============================================================================
// Экран конструктора с таблицей
// ============================================================================

class ConstructorScreen extends StatelessWidget {
  ConstructorScreen({super.key});

  // Определение колонок таблицы
  final List<ColumnDefinition> _columns = [
    ColumnDefinition(
      field: 'id',
      title: 'ID',
      dataType: ColumnDataType.number,
      isAggregatable: false,
      isGroupable: false,
      width: 70,
    ),
    ColumnDefinition(
      field: 'name',
      title: 'Наименование товара',
      dataType: ColumnDataType.text,
      isAggregatable: false,
      isGroupable: true,
      width: 150,
    ),
    ColumnDefinition(
      field: 'quantity',
      title: 'Кол-во',
      dataType: ColumnDataType.number,
      isAggregatable: true,
      isGroupable: false,
      width: 90,
    ),
    ColumnDefinition(
      field: 'price',
      title: 'Цена',
      dataType: ColumnDataType.currency,
      isAggregatable: true,
      isGroupable: false,
      width: 110,
      formatPattern: '#,##0.00 ₽',
    ),
    ColumnDefinition(
      field: 'date',
      title: 'Дата',
      dataType: ColumnDataType.date,
      isAggregatable: false,
      isGroupable: true,
      width: 110,
    ),
    ColumnDefinition(
      field: 'status',
      title: 'Статус',
      dataType: ColumnDataType.text,
      isAggregatable: false,
      isGroupable: true,
      width: 120,
    ),
    // НОВЫЙ СТОЛБЕЦ со случайными виджетами
    ColumnDefinition(
      field: 'random_widget',
      title: 'Рандом',
      dataType: ColumnDataType.text, // тип не важен, т.к. используем кастомный рендерер
      isAggregatable: false,
      isGroupable: false,
      width: 100,
    ),
  ];

  final ConstructorDataProvider _provider = ConstructorDataProvider();

  // Генератор случайного числа на основе id (детерминированный)
  int _getRandomNumber(int id) {
    final rand = math.Random(id);
    return rand.nextInt(100); // число от 0 до 99
  }

  // Генератор цвета на основе id
  Color _getRandomColor(int id) {
    final rand = math.Random(id);
    return Color.fromARGB(
      255,
      100 + rand.nextInt(156),
      100 + rand.nextInt(156),
      100 + rand.nextInt(156),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Expanded(
        child: UniversalDataTable<Map<String, dynamic>>(
          screenId: 'constructor_demo',
          provider: _provider,
          columns: _columns,
          // Кастомный билдер для столбца random_widget
          customCellBuilders: {
            'random_widget': (PlutoRow row) {
              final id = row.cells['id']?.value as int;
              final randomNumber = _getRandomNumber(id);
              final color = _getRandomColor(id);
              return ElevatedButton(
                onPressed: () {}, // Пустой обработчик – кнопка нажимается без реакции
                style: ElevatedButton.styleFrom(
                  backgroundColor: color.withOpacity(0.3),
                  foregroundColor: color,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 32),
                ),
                child: Text(
                  randomNumber.toString(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              );
            },
          },
        ),
      ),
    );
  }
}