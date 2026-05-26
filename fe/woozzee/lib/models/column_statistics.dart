import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:intl/intl.dart';

class ColumnStatistics {
  final String field;
  String displayName;
  double sum = 0.0;
  double average = 0.0;
  double max = 0.0;
  double min = 0.0;
  int count = 0;
  int numericCount = 0;
  String displayMode = 'sum'; // 'sum', 'count', 'average', 'max', 'min'
  PlutoColumnSort sortState = PlutoColumnSort.none;
  bool _isAggregatedFromDatabase = false;
  String aggregationMethod = 'none';

  Color get modeColor => _getModeColor();

  ColumnStatistics(this.field, {this.displayName = ''});

  bool _hasFilter = false;

  bool get hasFilter => _hasFilter;

  void updateFilterStatus(bool hasFilter) {
    _hasFilter = hasFilter;
  }

  void update(List<PlutoRow> rows) {
    final values = <double>[];
    sum = 0.0;
    count = 0;
    numericCount = 0;
    _isAggregatedFromDatabase = false;

    for (final row in rows) {
      final cell = row.cells[field];
      if (cell != null) {
        final value = cell.value;
        if (value != null) {
          count++;
          if (value is num) {
            final doubleValue = value.toDouble();
            values.add(doubleValue);
            sum += doubleValue;
            numericCount++;
          }
        }
      }
    }

    if (values.isNotEmpty) {
      average = sum / values.length;
      max = values.reduce((a, b) => a > b ? a : b);
      min = values.reduce((a, b) => a < b ? a : b);
    }
  }

  Future<void> updateFromDatabase({
    required Map<String, dynamic> aggregatedData,
    double? customSum,
    double? customAverage,
    double? customMax,
    double? customMin,
  }) async {
    _isAggregatedFromDatabase = true;

    double? _toDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is BigInt) return value.toDouble();
      if (value is String) {
        try {
          return double.parse(value);
        } catch (_) {}
      }
      return null;
    }

    if (field == 'total') {
      if (customSum != null) {
        sum = customSum;
      } else {
        double totalSum = 0.0;
        for (final key in aggregatedData.keys) {
          if (key.startsWith('total_') && aggregatedData[key] != null) {
            final val = _toDouble(aggregatedData[key]);
            if (val != null) totalSum += val;
          }
        }
        sum = totalSum;
      }
      count = aggregatedData['total_count'] as int? ?? 0;
      numericCount = count;
      if (count > 0) average = sum / count;
      return;
    }

    final sumKey = 'total_$field';
    final avgKey = 'avg_$field';
    final maxKey = 'max_$field';
    final minKey = 'min_$field';
    final countKey = 'count_$field';

    sum = 0.0;
    average = 0.0;
    max = 0.0;
    min = 0.0;

    count = aggregatedData.containsKey(countKey) && aggregatedData[countKey] != null
        ? (aggregatedData[countKey] as num).toInt()
        : 0;
    numericCount = count;

    final sumVal = _toDouble(aggregatedData[sumKey]);
    if (sumVal != null) sum = sumVal;

    final avgVal = _toDouble(aggregatedData[avgKey]);
    if (avgVal != null) {
      average = avgVal;
    } else if (count > 0 && sum != 0) {
      average = sum / count;
    }

    final maxVal = _toDouble(aggregatedData[maxKey]);
    if (maxVal != null) max = maxVal;

    final minVal = _toDouble(aggregatedData[minKey]);
    if (minVal != null) min = minVal;

    if (min == 0 && max > 0) min = max;
  }

  bool get isAggregatedFromDatabase => _isAggregatedFromDatabase;

  void toggleSort() {
    if (sortState.isNone) {
      sortState = PlutoColumnSort.ascending;
    } else if (sortState.isAscending) {
      sortState = PlutoColumnSort.descending;
    } else {
      sortState = PlutoColumnSort.none;
    }
  }

  IconData getSortIcon() {
    if (sortState.isAscending) return Icons.arrow_upward;
    if (sortState.isDescending) return Icons.arrow_downward;
    return Icons.sort;
  }

  Color getSortColor() {
    if (!sortState.isNone) return Colors.green;
    return Colors.grey;
  }

  String getFormattedValue() {
    double value;
    switch (displayMode) {
      case 'sum':
        if (numericCount == 0) return '';
        value = sum;
        break;
      case 'count':
        return NumberFormat('#,###', 'ru_RU').format(count);
      case 'average':
        if (numericCount == 0) return '';
        value = average;
        break;
      case 'max':
        if (numericCount == 0) return '';
        value = max;
        break;
      case 'min':
        if (numericCount == 0) return '';
        value = min;
        break;
      default:
        return '';
    }
    if (value == 0) return '';
    final formatted = NumberFormat('#,###', 'ru_RU').format(value.round());
    return formatted;
  }

  String getDisplaySymbol() {
    switch (displayMode) {
      case 'sum': return 'Σ';
      case 'count': return 'n';
      case 'average': return 'x̄';
      case 'max': return '▲';
      case 'min': return '▼';
      default: return '';
    }
  }

  void cycleMode() {
    final modes = ['sum', 'count', 'average', 'max', 'min'];
    final currentIndex = modes.indexOf(displayMode);
    final nextIndex = (currentIndex + 1) % modes.length;
    displayMode = modes[nextIndex];
  }

  Color _getModeColor() {
    if (!_isAggregatedFromDatabase) return Colors.grey;
    switch (displayMode) {
      case 'sum': return Colors.blue;
      case 'count': return Colors.green;
      case 'average': return Colors.orange;
      case 'max': return Colors.red;
      case 'min': return Colors.purple;
      default: return Colors.grey;
    }
  }

  bool supportsStatistics() {
    if (field.startsWith('custom_')) return true;
    final fieldType = ReportDetail.getFieldDataType(field);
    return fieldType == 'currency' ||
        fieldType == 'percent' ||
        fieldType == 'integer' ||
        field == 'quantity' ||
        field == 'delivery_amount' ||
        field == 'return_amount';
  }
}