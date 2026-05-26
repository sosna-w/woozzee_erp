// orders_manager.dart
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'token_manager.dart';

class OrdersManager {
  static final OrdersManager _instance = OrdersManager._internal();
  factory OrdersManager() => _instance;
  OrdersManager._internal();

  final Map<String, List<Map<String, dynamic>>> _ordersCache = {};
  final Map<String, DateTime> _cacheTime = {};
  final Duration _cacheDuration = Duration(minutes: 30);

  Map<int, List<Map<String, dynamic>>> _ordersByNmId = {};
  DateTime? _lastOrdersLoadTime;

  Future<void> initializeAllOrders() async {
    try {
      print('🔄 Начинаем загрузку заказов за последние 7 дней...');
      
      final token = await TokenManager().getToken();
      if (token == null) {
        print('⚠️ Токен не найден для загрузки заказов');
        return;
      }

      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(Duration(days: 7));
      
      final orders = await _fetchOrders(
        dateFrom: sevenDaysAgo,
        dateTo: now,
        token: token,
      );

      _ordersByNmId.clear();
      for (final order in orders) {
        final nmId = order['nmId'];
        if (nmId != null) {
          _ordersByNmId.putIfAbsent(nmId, () => []).add(order);
        }
      }

      _lastOrdersLoadTime = now;
      print('✅ Загружено ${orders.length} заказов для ${_ordersByNmId.length} товаров');
    } catch (e) {
      print('❌ Ошибка загрузки заказов: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getOrdersForProduct({
    required int nmId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final cacheKey = '${nmId}_${dateFrom.toIso8601String()}_${dateTo.toIso8601String()}';

    if (_ordersCache.containsKey(cacheKey) && 
        _cacheTime.containsKey(cacheKey)) {
      final cachedTime = _cacheTime[cacheKey]!;
      if (DateTime.now().difference(cachedTime) < _cacheDuration) {
        return _ordersCache[cacheKey]!;
      }
    }

    if (_ordersByNmId.containsKey(nmId)) {
      final allOrders = _ordersByNmId[nmId]!;
      final filteredOrders = allOrders.where((order) {
        final orderDate = DateTime.parse(order['date']);
        return !orderDate.isBefore(dateFrom) && orderDate.isBefore(dateTo);
      }).toList();

      _ordersCache[cacheKey] = filteredOrders;
      _cacheTime[cacheKey] = DateTime.now();
      
      return filteredOrders;
    }

    final token = await TokenManager().getToken();
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final orders = await _fetchOrders(
      dateFrom: dateFrom,
      dateTo: dateTo,
      token: token,
    );

    final productOrders = orders.where((order) => order['nmId'] == nmId).toList();

    _ordersCache[cacheKey] = productOrders;
    _cacheTime[cacheKey] = DateTime.now();

    return productOrders;
  }

  Future<List<Map<String, dynamic>>> _fetchOrders({
    required DateTime dateFrom,
    required DateTime dateTo,
    required String token,
  }) async {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final dateFromStr = dateFormat.format(dateFrom);
    
    final url = Uri.parse('https://statistics-api.wildberries.ru/api/v1/supplier/orders');
    final response = await http.get(
      url.replace(queryParameters: {
        'dateFrom': dateFromStr,
        'flag': '1',
      }),
      headers: {
        'Authorization': token,
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> jsonList = jsonDecode(response.body);
      return jsonList.map((item) => item as Map<String, dynamic>).toList();
    } else {
      throw Exception('Ошибка при загрузке заказов: ${response.statusCode}');
    }
  }

  Map<String, dynamic> getOrdersChartData({
    required List<Map<String, dynamic>> orders,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) {
    if (orders.isEmpty) {
      return {
        'labels': [],
        'detailedLabels': [],
        'timestamps': [],
        'datasets': [],
        'hasData': false,
        'message': 'Нет заказов за выбранный период',
      };
    }

    final Map<DateTime, int> ordersByDay = {};
    final dateFormat = DateFormat('yyyy-MM-dd');
    final displayFormat = DateFormat('dd.MM');
    final detailedFormat = DateFormat('dd.MM HH:mm');

    DateTime currentDay = DateTime(dateFrom.year, dateFrom.month, dateFrom.day);
    final endDay = DateTime(dateTo.year, dateTo.month, dateTo.day);
    
    while (currentDay.isBefore(endDay) || currentDay.isAtSameMomentAs(endDay)) {
      ordersByDay[currentDay] = 0;
      currentDay = currentDay.add(Duration(days: 1));
    }

    for (final order in orders) {
      final orderDate = DateTime.parse(order['date']);
      final dayKey = DateTime(orderDate.year, orderDate.month, orderDate.day);
      
      if (ordersByDay.containsKey(dayKey)) {
        ordersByDay[dayKey] = ordersByDay[dayKey]! + 1;
      }
    }

    final sortedDays = ordersByDay.keys.toList()..sort();

    final List<String> labels = [];
    final List<String> detailedLabels = [];
    final List<DateTime> timestamps = [];
    final List<int> data = [];

    for (final day in sortedDays) {
      labels.add(displayFormat.format(day));
      detailedLabels.add(detailedFormat.format(day));
      timestamps.add(day);
      data.add(ordersByDay[day]!);
    }

    return {
      'labels': labels,
      'detailedLabels': detailedLabels,
      'timestamps': timestamps,
      'datasets': [
        {
          'label': 'Заказы',
          'data': data,
          'color': '#FF9800',
        }
      ],
      'hasData': true,
      'message': '',
    };
  }

  void clearCache() {
    _ordersCache.clear();
    _cacheTime.clear();
    _ordersByNmId.clear();
    _lastOrdersLoadTime = null;
  }

  void clearCacheForProduct(int nmId) {
    final keysToRemove = _ordersCache.keys.where((key) => key.startsWith('${nmId}_')).toList();
    for (final key in keysToRemove) {
      _ordersCache.remove(key);
      _cacheTime.remove(key);
    }
    _ordersByNmId.remove(nmId);
  }
}