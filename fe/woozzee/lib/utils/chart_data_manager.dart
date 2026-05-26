import 'dart:async';
import '../models/stocks_history_data.dart';
import 'stocks_history_manager.dart';

class ChartDataManager {
  final StocksHistoryManager _stocksHistoryManager = StocksHistoryManager();

  // Доступные типы данных для графика
  static final List<String> availableChartTypes = [
    'stocks_history',
  ];

  // Настройки периодов
  static final Map<String, Map<String, dynamic>> periodPresets = {
    '7_days': {
      'name': '7 дней',
      'days': 7,
    },
    '30_days': {
      'name': '30 дней',
      'days': 30,
    },
    '90_days': {
      'name': '90 дней',
      'days': 90,
    },
    'custom': {
      'name': 'Произвольный',
      'days': null,
    },
  };

  Future<Map<String, dynamic>> getChartData({
    required String chartType,
    required int nmId,
    String period = '30_days',
    DateTime? customDateFrom,
    DateTime? customDateTo,
    bool forceRefresh = false,
  }) async {
    switch (chartType) {
      case 'stocks_history':
        return await _getStocksHistoryChartData(
          nmId: nmId,
          period: period,
          customDateFrom: customDateFrom,
          customDateTo: customDateTo,
          forceRefresh: forceRefresh,
        );
      default:
        throw Exception('Неизвестный тип графика: $chartType');
    }
  }

  Future<Map<String, dynamic>> _getStocksHistoryChartData({
    required int nmId,
    required String period,
    DateTime? customDateFrom,
    DateTime? customDateTo,
    bool forceRefresh = false,
  }) async {
    try {
      DateTime? dateFrom;
      DateTime? dateTo = DateTime.now();

      // Определяем период на основе preset
      if (period != 'custom') {
        final preset = periodPresets[period];
        if (preset != null && preset['days'] != null) {
          dateFrom = dateTo.subtract(Duration(days: preset['days']!));
        }
      } else {
        dateFrom = customDateFrom;
        dateTo = customDateTo;
      }

      // Получаем данные истории
      final historyData = await _stocksHistoryManager.getStocksHistory(
        nmId: nmId,
        dateFrom: dateFrom,
        dateTo: dateTo,
        forceRefresh: forceRefresh,
      );

      if (historyData.isEmpty) {
        return {
          'data': [],
          'labels': [],
          'datasets': [],
          'hasData': false,
          'message': 'Нет данных за выбранный период',
        };
      }

      // Подготавливаем данные для графика
      final List<String> labels = [];
      final List<String> detailedLabels = []; // ДЕТАЛЬНЫЕ МЕТКИ С ДАТОЙ И ВРЕМЕНЕМ
      final List<double> fboValues = [];
      final List<double> fbsValues = [];
      final List<DateTime> timestamps = []; // ХРАНИМ ИСХОДНЫЕ TIMESTAMP

      for (final record in historyData) {
        // record.createdAt уже в московском времени после исправления выше
        final dateStr = _formatDateForChart(record.createdAt);
        labels.add(dateStr);

        // Форматируем детальную метку с московским временем
        final detailedStr = _formatDateWithTimeForChart(record.createdAt);
        detailedLabels.add(detailedStr);

        // Сохраняем timestamp
        timestamps.add(record.createdAt);

        // Используем правильные поля из обновленной модели
        fboValues.add(record.totalQuantity.toDouble());
        fbsValues.add(record.fbsQuantity.toDouble());
      }

      // Находим максимальное значение для масштабирования
      final allValues = [...fboValues, ...fbsValues];
      final maxValue = allValues.isNotEmpty
          ? allValues.reduce((a, b) => a > b ? a : b).toDouble()
          : 0.0;

      return {
        'data': historyData,
        'labels': labels,
        'detailedLabels': detailedLabels, // ДОБАВЛЯЕМ ДЕТАЛЬНЫЕ МЕТКИ
        'timestamps': timestamps, // ДОБАВЛЯЕМ TIMESTAMPS
        'datasets': [
          {
            'label': 'FBO',
            'data': fboValues,
            'color': '#4CAF50', // Зеленый
            'maxValue': maxValue,
          },
          {
            'label': 'FBS',
            'data': fbsValues,
            'color': '#2196F3', // Синий
            'maxValue': maxValue,
          },
        ],
        'hasData': true,
        'period': period,
        'dateFrom': dateFrom?.toIso8601String(),
        'dateTo': dateTo?.toIso8601String(),
      };

    } catch (e) {
      print('❌ Ошибка подготовки данных графика: $e');
      return {
        'data': [],
        'labels': [],
        'detailedLabels': [],
        'timestamps': [],
        'datasets': [],
        'hasData': false,
        'message': 'Ошибка загрузки данных: $e',
      };
    }
  }

  // ДОБАВИТЬ НОВЫЙ МЕТОД для форматирования даты с временем
  String _formatDateWithTimeForChart(DateTime date) {
    final months = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
    final dateStr = '${date.day} ${months[date.month - 1]}';
    final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return '$dateStr\n$timeStr';
  }

  String _formatDateForChart(DateTime date) {
    // Форматируем дату в компактный вид: "12 дек"
    final months = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
    return '${date.day} ${months[date.month - 1]}';
  }

  void clearCache({int? nmId}) {
    _stocksHistoryManager.clearCache(nmId: nmId);
  }
}