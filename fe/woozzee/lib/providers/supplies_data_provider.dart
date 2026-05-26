import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../utils/product_manager.dart';
import '../widgets/supplies/simple_bar_chart.dart' show UniversalDataTable, DataProvider, FilterSet, CustomColumn, TimeSeriesPoint;
import '../models/batch.dart';

class SuppliesDataProvider implements DataProvider<Product> {
  final ProductManager _productManager = ProductManager();

  Map<int, int> stockMap;
  Map<int, int> ordersMap;
  Map<int, int> cancellationsMap;
  Map<int, int> returnsMap;
  Map<int, int> salesMap;
  Map<int, String> barcodeMap;
  Map<int, int> inTransitMap;
  int daysRange;
  Map<int, String> checkStatusMap;
  int supplyPeriodDays;
  Map<int, BatchEntry> batchDataMap;

  SuppliesDataProvider({
    this.stockMap = const {},
    this.ordersMap = const {},
    this.cancellationsMap = const {},
    this.returnsMap = const {},
    this.salesMap = const {},
    this.barcodeMap = const {},
    this.inTransitMap = const {},
    this.daysRange = 1,
    this.checkStatusMap = const {},
    this.supplyPeriodDays = 30,
    this.batchDataMap = const {},
  });

  void updateData({
    required Map<int, int> newStockMap,
    required Map<int, int> newOrdersMap,
    required Map<int, int> newCancellationsMap,
    required Map<int, int> newReturnsMap,
    required Map<int, int> newSalesMap,
    required Map<int, String> newBarcodeMap,
    required int newDaysRange,
    required Map<int, int> newInTransitMap,
    Map<int, String>? newCheckStatusMap,
    Map<int, BatchEntry>? newBatchData,
    int? newSupplyPeriodDays,
  }) {
    stockMap = newStockMap;
    ordersMap = newOrdersMap;
    cancellationsMap = newCancellationsMap;
    returnsMap = newReturnsMap;
    salesMap = newSalesMap;
    barcodeMap = newBarcodeMap;
    daysRange = newDaysRange;
    inTransitMap = newInTransitMap;
    if (newCheckStatusMap != null) checkStatusMap = newCheckStatusMap;
    if (newSupplyPeriodDays != null) supplyPeriodDays = newSupplyPeriodDays;
    if (newBatchData != null) batchDataMap = newBatchData;
  }

  double _getStockDays(int nmId) {
    final ordersTotal = ordersMap[nmId] ?? 0;
    if (ordersTotal == 0 || daysRange == 0) return 0.0;
    final ordersPerDay = ordersTotal / daysRange;
    final stock = stockMap[nmId] ?? 0;
    final cancellations = cancellationsMap[nmId] ?? 0;
    final returns = returnsMap[nmId] ?? 0;
    final inTransit = inTransitMap[nmId] ?? 0;
    return (stock + cancellations + returns + inTransit) / ordersPerDay;
  }

  int _getDemand(int nmId) {
    final ordersTotal = ordersMap[nmId] ?? 0;
    if (ordersTotal == 0 || daysRange == 0) return 0;
    final ordersPerDay = ordersTotal / daysRange;
    final stockDays = _getStockDays(nmId);
    final deficitDays = supplyPeriodDays - stockDays;
    if (deficitDays <= 0) return 0;
    return (deficitDays * ordersPerDay).round();
  }

  int _getToSupply(int nmId) {
    final ordersTotal = ordersMap[nmId] ?? 0;
    if (ordersTotal == 0 || daysRange == 0) return 0;
    final ordersPerDay = ordersTotal / daysRange;
    final stockDays = _getStockDays(nmId);
    final deficitDays = supplyPeriodDays - stockDays;
    if (deficitDays <= 0) return 0;
    int rawToSupply = (deficitDays * ordersPerDay).round();

    final entry = batchDataMap[nmId];
    if (entry == null || entry.total == 0) return 0;
    if (rawToSupply >= entry.total) return entry.total;
    return _getOptimalToSupply(nmId, rawToSupply);
  }

  int _getOptimalToSupply(int nmId, int demand) {
    final entry = batchDataMap[nmId];
    if (entry == null) return 0;
    final total = entry.total;
    if (total == 0) return 0;
    if (demand >= total) return total;

    final maxDemand = demand;
    final can = List<bool>.filled(maxDemand + 1, false);
    can[0] = true;

    for (final detail in entry.details) {
      final size = detail.qtyInBox;
      int count = detail.boxesCount;
      int k = 1;
      while (count > 0) {
        final take = k < count ? k : count;
        final amount = take * size;
        for (int s = maxDemand; s >= amount; s--) {
          if (can[s - amount]) can[s] = true;
        }
        count -= take;
        k <<= 1;
      }
    }

    for (int s = maxDemand; s >= 0; s--) {
      if (can[s]) return s;
    }
    return 0;
  }

  @override
  dynamic getFieldValue(Product product, String field) {
    switch (field) {
      case 'supplier_article':
        return product.vendorCode;
      case 'wb_article':
        return product.nmID;
      case 'name':
        return product.title;
      case 'demand':
        return _getDemand(product.nmID);
      case 'in_transit':
        return inTransitMap[product.nmID] ?? 0;
      case 'ready_to_ship':
        return batchDataMap[product.nmID]?.total ?? 0;
      case 'subject':
        return product.subjectName;
      case 'tags':
        return product.tags;
      case 'preview_photo':
        final photos = product.getPhotoUrls();
        return photos.isNotEmpty ? photos.first : null;
      case 'barcode':
        return barcodeMap[product.nmID] ?? '';
      case 'stock':
        return stockMap[product.nmID];
      case 'orders':
        return ordersMap[product.nmID];
      case 'orders_per_day':
        final orders = ordersMap[product.nmID];
        if (orders == null || daysRange == 0) return null;
        return orders / daysRange;
      case 'cancellations':
        return cancellationsMap[product.nmID];
      case 'returns':
        return returnsMap[product.nmID];
      case 'sales':
        return salesMap[product.nmID];
      case 'stock_days':
        return 0;
      case 'to_supply':
        return 0;
      case 'margin':
        return 0;
      case 'dynamic_prices':
      case 'dynamic_orders':
      case 'dynamic_stocks':
      case 'dynamic_queries':
      case 'dynamic_transitions':
      case 'abc':
        return null;
      default:
        return null;
    }
  }

  @override
  Future<int> getTotalCount({
    required FilterSet filters,
    String? groupByField,
  }) async {
    if (groupByField != null) return 0;
    final filtered = _applyFilters(_productManager.allProducts, filters);
    return filtered.length;
  }

  @override
  Future<List<Product>> fetchData({
    required int offset,
    required int limit,
    required FilterSet filters,
    String? sortField,
    bool sortDesc = true,
    String? groupByField,
    Map<String, String>? aggregationMethods,
  }) async {
    if (groupByField != null) return [];

    List<Product> result = _applyFilters(_productManager.allProducts, filters);
    result = _applySorting(result, sortField, sortDesc);
    if (offset < result.length) {
      final end = (offset + limit) > result.length ? result.length : offset + limit;
      result = result.sublist(offset, end);
    } else {
      result = [];
    }
    return result;
  }

  @override
  Future<List<dynamic>> getUniqueValues({
    required String field,
    required FilterSet filters,
    int maxValues = 1000,
  }) async {
    final Set<dynamic> values = {};

    switch (field) {
      case 'barcode':
        for (final barcode in barcodeMap.values) {
          if (barcode.isNotEmpty) values.add(barcode);
        }
        break;

      case 'check_status':
        values.addAll(['Разрешено', 'Недоступно']);
        break;

      case 'demand':
        for (final nmId in ordersMap.keys) {
          values.add(_getDemand(nmId));
        }
        break;

      case 'ready_to_ship':
        for (final entry in batchDataMap.values) {
          values.add(entry.total.toString());
        }
        break;

      case 'stock':
        for (final nmId in stockMap.keys) {
          values.add(stockMap[nmId] ?? 0);
        }
        break;

      case 'orders':
        for (final nmId in ordersMap.keys) {
          values.add(ordersMap[nmId]);
        }
        break;

      case 'orders_per_day':
        for (final nmId in ordersMap.keys) {
          final orders = ordersMap[nmId] ?? 0;
          final value = daysRange > 0 ? orders / daysRange : 0.0;
          values.add(value);
        }
        break;

      case 'cancellations':
        for (final nmId in cancellationsMap.keys) {
          values.add(cancellationsMap[nmId] ?? 0);
        }
        break;

      case 'returns':
        for (final nmId in returnsMap.keys) {
          values.add(returnsMap[nmId] ?? 0);
        }
        break;

      case 'sales':
        for (final nmId in salesMap.keys) {
          values.add(salesMap[nmId] ?? 0);
        }
        break;

      case 'stock_days':
        for (final nmId in stockMap.keys) {
          values.add(_getStockDays(nmId));
        }
        break;

      case 'to_supply':
        for (final nmId in ordersMap.keys) {
          values.add(_getToSupply(nmId));
        }
        break;

      case 'in_transit':
        for (final nmId in inTransitMap.keys) {
          values.add(inTransitMap[nmId] ?? 0);
        }
        break;

      default:
        final allProducts = _productManager.allProducts;
        for (var product in allProducts) {
          dynamic val;
          switch (field) {
            case 'supplier_article':
              val = product.vendorCode;
              break;
            case 'wb_article':
              val = product.nmID;
              break;
            case 'name':
              val = product.title;
              break;
            case 'subject':
              val = product.subjectName;
              break;
            case 'tags':
              final tagsList = product.tags as List<dynamic>?;
              if (tagsList != null) {
                for (var tag in tagsList) {
                  final name = tag['name']?.toString();
                  if (name != null && name.isNotEmpty) values.add(name);
                }
              }
              continue;
            default:
              continue;
          }
          if (val != null && val.toString().isNotEmpty) values.add(val);
        }
        break;
    }
    return values.toList();
  }

  @override
  Future<Map<String, dynamic>> getAggregatedTotals({
    required FilterSet filters,
    String? groupByField,
  }) async {
    return {};
  }

  @override
  Future<List<TimeSeriesPoint>> getTimeSeriesData({
    required String dateField,
    required String valueField,
    required FilterSet filters,
  }) async {
    return [];
  }

  @override
  Future<List<DateTime>> getAvailableDates() async => [];

  @override
  Future<int> getAggregatedGroupCount({
    required String groupByField,
    required FilterSet filters,
  }) async {
    return 0;
  }

  @override
  Future<void> addCustomColumn(String name, String formula) async {}
  @override
  Future<void> updateCustomColumn(String oldName, String newName, String formula) async {}
  @override
  Future<void> deleteCustomColumn(String name) async {}
  @override
  Future<List<CustomColumn>> getCustomColumns() async => [];

  List<Product> _applyFilters(List<Product> products, FilterSet filters) {
    if (filters.isEmpty) return products;

    return products.where((product) {
      for (var entry in filters.filters.entries) {
        final field = entry.key;
        final selectedValues = entry.value;
        if (selectedValues.isEmpty) continue;

        dynamic productValue;
        switch (field) {
          case 'supplier_article':
            productValue = product.vendorCode;
            break;
          case 'wb_article':
            productValue = product.nmID;
            break;
          case 'name':
            productValue = product.title;
            break;
          case 'subject':
            productValue = product.subjectName;
            break;
          case 'barcode':
            productValue = barcodeMap[product.nmID] ?? '';
            break;
          case 'stock':
            productValue = stockMap[product.nmID] ?? 0;
            break;
          case 'demand':
            productValue = _getDemand(product.nmID);
            break;
          case 'orders':
            productValue = ordersMap[product.nmID] ?? 0;
            break;
          case 'ready_to_ship':
            productValue = batchDataMap[product.nmID] ?? 0;
            break;
          case 'orders_per_day':
            final orders = ordersMap[product.nmID] ?? 0;
            productValue = daysRange > 0 ? orders / daysRange : 0.0;
            break;
          case 'cancellations':
            productValue = cancellationsMap[product.nmID] ?? 0;
            break;
          case 'returns':
            productValue = returnsMap[product.nmID] ?? 0;
            break;
          case 'sales':
            productValue = salesMap[product.nmID] ?? 0;
            break;
          case 'stock_days':
            productValue = _getStockDays(product.nmID);
            break;
          case 'to_supply':
            productValue = _getToSupply(product.nmID);
            break;
          case 'in_transit':
            productValue = inTransitMap[product.nmID] ?? 0;
            break;
          case 'check_status':
            productValue = checkStatusMap[product.nmID] ?? '';
            break;
          case 'tags':
            final tagsList = product.tags as List<dynamic>?;
            final selectedNames = selectedValues.map((e) => e.toString()).toSet();
            if (selectedNames.isEmpty) continue;
            if (tagsList == null || tagsList.isEmpty) return false;
            final productTagNames = tagsList
                .map((tag) => tag['name']?.toString())
                .where((name) => name != null && name.isNotEmpty)
                .toSet();
            if (!_setEquals(selectedNames, productTagNames)) return false;
            continue;
          case 'margin':
          case 'dynamic_prices':
          case 'dynamic_orders':
          case 'dynamic_stocks':
          case 'dynamic_queries':
          case 'dynamic_transitions':
          case 'abc':
            continue;
          default:
            productValue = null;
        }
        if (productValue == null) return false;
        final String strValue = productValue.toString();
        if (!selectedValues.any((v) => v.toString() == strValue)) return false;
      }
      return true;
    }).toList();
  }

  bool _setEquals<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  List<Product> _applySorting(List<Product> products, String? sortField, bool sortDesc) {
    if (sortField == null) return products;
    final list = List<Product>.from(products);
    list.sort((a, b) {
      int cmp = 0;
      switch (sortField) {
        case 'supplier_article':
          cmp = a.vendorCode.compareTo(b.vendorCode);
          break;
        case 'wb_article':
          cmp = a.nmID.compareTo(b.nmID);
          break;
        case 'name':
          cmp = a.title.compareTo(b.title);
          break;
        case 'ready_to_ship':
          final valA = batchDataMap[a.nmID]?.total ?? 0;
          final valB = batchDataMap[b.nmID]?.total ?? 0;
          cmp = valA.compareTo(valB);
          break;
        case 'stock_days':
          final valA = _getStockDays(a.nmID);
          final valB = _getStockDays(b.nmID);
          cmp = valA.compareTo(valB);
          break;
        case 'demand':
          final valA = _getDemand(a.nmID);
          final valB = _getDemand(b.nmID);
          cmp = valA.compareTo(valB);
          break;
        case 'in_transit':
          final valA = inTransitMap[a.nmID] ?? 0;
          final valB = inTransitMap[b.nmID] ?? 0;
          cmp = valA.compareTo(valB);
          break;
        case 'to_supply':
          final valA = _getToSupply(a.nmID);
          final valB = _getToSupply(b.nmID);
          cmp = valA.compareTo(valB);
          break;
        case 'check_status':
          final statusA = checkStatusMap[a.nmID] ?? '';
          final statusB = checkStatusMap[b.nmID] ?? '';
          cmp = statusA.compareTo(statusB);
          break;
        case 'subject':
          cmp = a.subjectName.compareTo(b.subjectName);
          break;
        case 'tags':
          final aFirst = _getFirstTagName(a);
          final bFirst = _getFirstTagName(b);
          if (aFirst == null && bFirst == null) cmp = 0;
          else if (aFirst == null) cmp = -1;
          else if (bFirst == null) cmp = 1;
          else cmp = aFirst.compareTo(bFirst);
          if (cmp == 0) {
            final aCount = _getTagCount(a);
            final bCount = _getTagCount(b);
            cmp = aCount.compareTo(bCount);
          }
          break;
        case 'barcode':
          cmp = _getStringField(a, sortField).compareTo(_getStringField(b, sortField));
          break;
        case 'stock':
        case 'orders':
        case 'orders_per_day':
        case 'cancellations':
        case 'returns':
        case 'sales':
        case 'stock_days':
        case 'to_supply':
        case 'margin':
          cmp = _getNumericField(a, sortField).compareTo(_getNumericField(b, sortField));
          break;
        case 'dynamic_prices':
        case 'dynamic_orders':
        case 'dynamic_stocks':
        case 'dynamic_queries':
        case 'dynamic_transitions':
        case 'abc':
          cmp = 0;
          break;
        default:
          cmp = 0;
      }
      return sortDesc ? -cmp : cmp;
    });
    return list;
  }

  String _getStringField(Product p, String field) {
    switch (field) {
      case 'barcode': return barcodeMap[p.nmID] ?? '';
      default: return '';
    }
  }

  num _getNumericField(Product p, String field) {
    switch (field) {
      case 'stock': return stockMap[p.nmID] ?? 0;
      case 'orders': return ordersMap[p.nmID] ?? 0;
      case 'orders_per_day':
        if (daysRange > 0) return (ordersMap[p.nmID] ?? 0) / daysRange;
        return 0;
      case 'cancellations': return cancellationsMap[p.nmID] ?? 0;
      case 'returns': return returnsMap[p.nmID] ?? 0;
      case 'sales': return salesMap[p.nmID] ?? 0;
      case 'stock_days': return 0;
      case 'demand': return _getToSupply(p.nmID);
      case 'to_supply': return 0;
      case 'margin': return 0;
      default: return 0;
    }
  }

  String? _getFirstTagName(Product p) {
    final tags = p.tags as List<dynamic>?;
    if (tags == null || tags.isEmpty) return null;
    final first = tags.first;
    if (first is Map && first.containsKey('name')) {
      return first['name']?.toString();
    }
    return null;
  }

  int _getTagCount(Product p) {
    final tags = p.tags as List<dynamic>?;
    return tags?.length ?? 0;
  }
}