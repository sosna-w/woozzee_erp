import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

import '../models/warehouse.dart';
import '../models/batch.dart';
import '../providers/supplies_data_provider.dart';
import '../widgets/supplies/date_range_picker_dialog.dart';
import '../widgets/supplies/image_preview_cell.dart';
import '../widgets/supplies/placeholder_widgets.dart';
import '../widgets/supplies/batch_details_cell.dart';
import '../widgets/supplies/editable_to_supply_cell.dart';
import '../widgets/supplies/in_transit_cell.dart';
import '../widgets/supplies/simple_bar_chart.dart';
import '../utils/photo_cache_manager.dart';
import '../utils/token_manager.dart';
import '../utils/private_token_manager.dart';
import '../utils/product_manager.dart';
import '../utils/price_history_manager.dart';
import '../utils/sales_funnel_manager.dart';
import '../services/search_query_service.dart';
import 'universal_data_table.dart';

class SuppliesScreenNew extends StatefulWidget {
  const SuppliesScreenNew({Key? key}) : super(key: key);

  @override
  State<SuppliesScreenNew> createState() => _SuppliesScreenNewState();
}

class _SuppliesScreenNewState extends State<SuppliesScreenNew> {
  final GlobalKey<UniversalDataTableState> _tableKey = GlobalKey<UniversalDataTableState>();
  late final UniversalDataTableController _tableController;
  late final SuppliesDataProvider _provider;

  bool _ordersLoadedFromPrecomputed = false;

  Map<int, int> get _batchTotalMap => _batchData.map((key, value) => MapEntry(key, value.total));

  DateTimeRange? _selectedDateRange;
  final TextEditingController _dateRangeController = TextEditingController();
  bool _isInitialized = true;
  bool _isExporting = false;

  Map<int, int> _manualToSupply = {};
  final Map<String, int> _tempNmIdForBarcode = {};

  List<Warehouse> _warehouses = [];
  Warehouse? _selectedWarehouse;
  bool _isLoadingWarehouses = false;
  String? _warehousesError;

  bool _isLoadingRemainsStats = false;
  String? _remainsStatsError;
  int _uniqueWarehouseCount = 0;
  int _totalStockSum = 0;
  int _uniqueArticleCount = 0;

  Map<String, int> _warehouseArticleCount = {};
  Map<String, int> _warehouseStockSum = {};
  Map<String, Set<int>> _warehouseArticlesSets = {};

  Map<String, Map<int, int>> _warehouseNmIdQuantityMap = {};

  Map<String, String> _warehouseMapping = {};
  Map<String, String> _orderWarehouseMapping = {};
  bool _isMappingLoaded = false;
  bool _useMapping = false;

  Map<String, Set<int>> _mappedArticlesSets = {};
  Map<String, int> _mappedStockSum = {};
  Map<String, Map<int, int>> _mappedNmIdQuantityMap = {};

  bool _isLoadingOrders = false;
  int _ordersWarehouseCount = 0;
  int _totalOrdersCount = 0;
  int _ordersUniqueArticlesCount = 0;
  String? _ordersError;

  Map<String, Map<int, int>> _ordersNmIdCountByWB = {};
  Map<String, int> _ordersWarehouseCountMap = {};
  Map<String, Set<int>> _ordersWarehouseArticlesMap = {};

  Map<String, Map<int, int>> _cancellationsByWB = {};
  Map<String, Map<int, int>> _returnsByWB = {};
  Map<String, Map<int, int>> _salesByWB = {};

  Map<int, int> _currentStockMap = {};
  Map<int, int> _currentOrdersMap = {};
  Map<int, int> _currentCancellationsMap = {};
  Map<int, int> _currentReturnsMap = {};
  Map<int, int> _currentSalesMap = {};
  int _currentDaysRange = 1;

  int _supplyPeriodDays = 30;
  late TextEditingController _supplyPeriodController;
  Timer? _supplyPeriodDebounceTimer;

  bool _isLoadingMapping = false;

  late PriceHistoryManager _priceHistoryManager;
  late SalesFunnelManager _salesManager;
  late SearchQueryService _searchQueryService;

  final Map<int, Future<List<int>>> _priceHistoryFutures = {};
  final Map<int, Future<List<int>>> _searchFrequenciesFutures = {};
  final Map<int, Future<List<double>>> _transitionsFutures = {};

  Map<String, Map<int, Map<DateTime, int>>> _ordersTimeSeriesByWarehouse = {};
  Map<int, Map<DateTime, int>> _currentOrdersTimeSeriesMap = {};
  final Map<int, Future<List<int>>> _ordersTimeSeriesFutures = {};

  Map<int, int> _currentPrices = {};

  Map<String, Map<int, Map<DateTime, int>>> _stockTimeSeriesByWarehouse = {};
  Map<int, Map<DateTime, int>> _currentStockTimeSeriesMap = {};
  bool _isLoadingStockHistory = false;
  String? _stockHistoryError;
  final Map<int, Future<List<int>>> _stockTimeSeriesFutures = {};

  Map<int, String> _barcodeMap = {};
  Map<int, String> _checkStatus = {};
  bool _isChecking = false;

  bool _isCalendarLoading = false;
  Set<DateTime> _supplyDates = {};
  DateTime _calendarFocusedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;

  Map<int, Map<int, List<Map<String, dynamic>>>> _inTransitFull = {};
  Map<int, int> _currentInTransitMap = {};
  Map<int, List<Map<String, dynamic>>> _currentInTransitDetails = {};
  bool _isLoadingInTransit = false;
  String? _inTransitError;

  Map<int, BatchEntry> _batchData = {};

  @override
  void initState() {
    super.initState();
    _tableController = UniversalDataTableController();
    _provider = SuppliesDataProvider(batchDataMap: {});
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final weekAgo = yesterday.subtract(const Duration(days: 20));
    _selectedDateRange = DateTimeRange(
      start: DateTime(weekAgo.year, weekAgo.month, weekAgo.day),
      end: DateTime(yesterday.year, yesterday.month, yesterday.day),
    );
    _updateDateRangeController();
    _loadPrecomputedOrdersData();

    _supplyPeriodController = TextEditingController(text: '30');
    _supplyPeriodController.addListener(_onSupplyPeriodTextChanged);

    _loadWarehouses();
    _loadInTransitGoods();
    _fetchWarehouseRemainsStats();
    _fetchWarehouseMapping();

    _priceHistoryManager = PriceHistoryManager();
    _salesManager = SalesFunnelManager();
    _searchQueryService = SearchQueryService();

    _priceHistoryManager.loadAllPriceHistory().then((_) {
      _priceHistoryFutures.clear();
      if (mounted) setState(() {});
    });

    _salesManager.initialize().then((_) {
      _transitionsFutures.clear();
      if (mounted) setState(() {});
    });

    _searchQueryService.loadHistory(forceReload: false).then((_) {
      _searchFrequenciesFutures.clear();
      if (mounted) setState(() {});
    });
    _searchQueryService.loadCurrentData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buildBarcodeMapFromProducts();
    });

    _loadCurrentPrices().then((_) {
      _priceHistoryFutures.clear();
      if (mounted) setState(() {});
    });
  }

  int _getCappedToSupply(int nmId, [int? manualValue]) {
    if (manualValue != null) {
      final maxReady = _batchData[nmId]?.total ?? 0;
      if (maxReady == 0) return 0;
      return manualValue > maxReady ? maxReady : manualValue;
    }
    final demand = _getAutoToSupplyForNmId(nmId);
    final entry = _batchData[nmId];
    if (entry == null || entry.total == 0) return 0;
    if (demand >= entry.total) return entry.total;
    return _getOptimalToSupplyHelper(nmId, demand);
  }

  int _getOptimalToSupplyHelper(int nmId, int demand) {
    final entry = _batchData[nmId];
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
  void dispose() {
    _supplyPeriodDebounceTimer?.cancel();
    _supplyPeriodController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchSuppliesList(DateTime from, DateTime till) async {
    final token = await TokenManager().getToken();
    if (token == null) return [];

    final dateFormat = DateFormat('yyyy-MM-dd');
    final requestBody = {
      "dates": [
        {
          "from": dateFormat.format(from),
          "till": dateFormat.format(till),
          "type": "supplyDate"
        }
      ],
      "statusIDs": [2, 3, 4, 6]
    };

    try {
      final response = await http.post(
        Uri.parse('https://supplies-api.wildberries.ru/api/v1/supplies'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => {
          'supplyID': item['supplyID'],
          'statusID': item['statusID'],
          'supplyDate': item['supplyDate'],
        }).toList();
      }
    } catch (e) {
      debugPrint('Ошибка получения списка поставок: $e');
    }
    return [];
  }

  Future<Map<int, int>> _fetchGoodsForSupply(int supplyID) async {
    final token = await TokenManager().getToken();
    if (token == null) return {};

    Map<int, int> goods = {};
    int offset = 0;
    const limit = 100;
    bool hasMore = true;

    while (hasMore) {
      final url = Uri.parse(
          'https://supplies-api.wildberries.ru/api/v1/supplies/$supplyID/goods?limit=$limit&offset=$offset');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> items = json.decode(response.body);
        for (var item in items) {
          final nmId = item['nmID'] as int?;
          final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
          if (nmId != null && quantity > 0) {
            goods[nmId] = (goods[nmId] ?? 0) + quantity;
          }
        }
        hasMore = items.length == limit;
        offset += limit;
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        debugPrint('Ошибка загрузки товаров поставки $supplyID: ${response.statusCode}');
        hasMore = false;
      }
    }
    return goods;
  }

  Future<Map<String, dynamic>?> _fetchSupplyDetails(int supplyID) async {
    final token = await TokenManager().getToken();
    if (token == null) return null;

    final url = Uri.parse('https://supplies-api.wildberries.ru/api/v1/supplies/$supplyID');
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      debugPrint('Ошибка получения деталей поставки $supplyID: ${response.statusCode}');
      return null;
    }
  }

  Future<void> _loadInTransitGoods() async {
    setState(() {
      _isLoadingInTransit = true;
      _inTransitError = null;
    });

    try {
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 90));
      final till = now.add(const Duration(days: 30));

      final supplies = await _fetchSuppliesList(from, till);
      if (supplies.isEmpty) {
        setState(() {
          _isLoadingInTransit = false;
          _inTransitFull.clear();
          _updateCurrentInTransitData();
        });
        return;
      }

      final Map<int, Map<int, List<Map<String, dynamic>>>> newFull = {};

      for (var supply in supplies) {
        final supplyID = supply['supplyID'] as int?;
        final statusID = supply['statusID'] as int?;
        if (supplyID == null || statusID == null) continue;

        Map<String, dynamic>? supplyDetails;
        try {
          supplyDetails = await _fetchSupplyDetails(supplyID);
        } catch (e) {
          debugPrint('Ошибка получения деталей поставки $supplyID: $e');
          continue;
        }
        final warehouseID = supplyDetails?['warehouseID'] as int?;
        if (warehouseID == null) continue;

        final goods = await _fetchGoodsForSupply(supplyID);
        if (goods.isEmpty) continue;

        for (var entry in goods.entries) {
          final nmId = entry.key;
          final quantity = entry.value;

          newFull.putIfAbsent(nmId, () => {});
          newFull[nmId]!.putIfAbsent(warehouseID, () => []);
          newFull[nmId]![warehouseID]!.add({
            'supplyID': supplyID,
            'statusID': statusID,
            'quantity': quantity,
          });
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }

      setState(() {
        _inTransitFull = newFull;
        _isLoadingInTransit = false;
      });
      _updateCurrentInTransitData();
    } catch (e) {
      setState(() {
        _inTransitError = e.toString();
        _isLoadingInTransit = false;
      });
    }
  }

  void _updateCurrentInTransitData() {
    final warehouseId = _selectedWarehouse?.id;
    final Map<int, int> newSums = {};
    final Map<int, List<Map<String, dynamic>>> newDetails = {};

    if (warehouseId == null) {
      for (final nmEntry in _inTransitFull.entries) {
        final nmId = nmEntry.key;
        int total = 0;
        final detailsList = <Map<String, dynamic>>[];
        for (final whEntry in nmEntry.value.entries) {
          for (final detail in whEntry.value) {
            total += detail['quantity'] as int;
            detailsList.add(detail);
          }
        }
        if (total > 0) {
          newSums[nmId] = total;
          newDetails[nmId] = detailsList;
        }
      }
    } else {
      for (final nmEntry in _inTransitFull.entries) {
        final nmId = nmEntry.key;
        final whData = nmEntry.value[warehouseId];
        if (whData != null && whData.isNotEmpty) {
          int total = 0;
          final detailsList = <Map<String, dynamic>>[];
          for (final detail in whData) {
            total += detail['quantity'] as int;
            detailsList.add(detail);
          }
          newSums[nmId] = total;
          newDetails[nmId] = detailsList;
        }
      }
    }

    setState(() {
      _currentInTransitMap = newSums;
      _currentInTransitDetails = newDetails;
    });
    _refreshProviderData();
  }

  Future<void> _loadSuppliesCalendar() async {
    setState(() {
      _isCalendarLoading = true;
    });

    debugPrint('📦 Начинаем загрузку календаря поставок...');

    final token = await TokenManager().getToken();
    if (token == null || token.isEmpty) {
      debugPrint('❌ Нет токена для загрузки поставок');
      setState(() => _isCalendarLoading = false);
      return;
    }

    final now = DateTime.now();
    final fromDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
    final tillDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 30));

    final dateFormat = DateFormat('yyyy-MM-dd');
    final requestBody = {
      "dates": [
        {
          "from": dateFormat.format(fromDate),
          "till": dateFormat.format(tillDate),
          "type": "supplyDate"
        }
      ],
      "statusIDs": [2, 3, 4, 6]
    };

    final stopwatch = Stopwatch()..start();

    try {
      final response = await http.post(
        Uri.parse('https://supplies-api.wildberries.ru/api/v1/supplies'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 30));

      stopwatch.stop();
      debugPrint('⏱️ Запрос выполнен за ${stopwatch.elapsedMilliseconds} мс');
      debugPrint('📥 Статус ответа: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        debugPrint('✅ Получено поставок: ${data.length}');

        final Set<DateTime> datesSet = {};
        for (var item in data) {
          final supplyDateStr = item['supplyDate'] as String?;
          if (supplyDateStr != null && supplyDateStr.isNotEmpty) {
            try {
              String datePart = supplyDateStr.substring(0, 10);
              List<String> parts = datePart.split('-');
              if (parts.length == 3) {
                int year = int.parse(parts[0]);
                int month = int.parse(parts[1]);
                int day = int.parse(parts[2]);
                DateTime dateOnly = DateTime(year, month, day);
                datesSet.add(dateOnly);
              } else {
                DateTime dateOnly = DateFormat('yyyy-MM-dd').parse(datePart);
                datesSet.add(dateOnly);
              }
            } catch (e) {
              debugPrint('⚠️ Ошибка парсинга даты "$supplyDateStr": $e');
            }
          }
        }

        debugPrint('📅 Уникальных дат с поставками: ${datesSet.length}');
        setState(() {
          _supplyDates = datesSet;
        });
      } else {
        debugPrint('❌ Ошибка HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Исключение при загрузке поставок: $e');
    } finally {
      setState(() => _isCalendarLoading = false);
    }
  }

  void _showSuppliesCalendar() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final now = DateTime.now();
        final minDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
        final maxDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 30));

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              child: Container(
                width: 400,
                height: 500,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'Календарь поставок',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    if (_isCalendarLoading)
                      const Expanded(child: Center(child: CircularProgressIndicator()))
                    else
                      Expanded(
                        child: TableCalendar(
                          firstDay: minDate,
                          lastDay: maxDate,
                          focusedDay: _calendarFocusedDay,
                          startingDayOfWeek: StartingDayOfWeek.monday,
                          locale: 'ru_RU',
                          calendarFormat: _calendarFormat,
                          onPageChanged: (focusedDay) {
                            setModalState(() {
                              _calendarFocusedDay = focusedDay;
                            });
                          },
                          onFormatChanged: (format) {
                            setModalState(() {
                              _calendarFormat = format;
                            });
                          },
                          calendarBuilders: CalendarBuilders(
                            defaultBuilder: (context, date, _) {
                              final isSupplyDay = _supplyDates.any((supplyDate) => DateUtils.isSameDay(supplyDate, date));
                              final isToday = DateUtils.isSameDay(date, DateTime.now());

                              Color backgroundColor;
                              Color borderColor;
                              Color textColor;

                              if (isSupplyDay && isToday) {
                                backgroundColor = Colors.green.withOpacity(0.1);
                                borderColor = Colors.green;
                                textColor = Colors.red;
                              } else if (isSupplyDay) {
                                backgroundColor = Colors.green.withOpacity(0.1);
                                borderColor = Colors.green;
                                textColor = Colors.green[800]!;
                              } else if (isToday) {
                                backgroundColor = Colors.transparent;
                                borderColor = Colors.transparent;
                                textColor = Colors.red;
                              } else {
                                backgroundColor = Colors.grey[100]!;
                                borderColor = Colors.grey[300]!;
                                textColor = Colors.grey[600]!;
                              }

                              return Container(
                                margin: const EdgeInsets.all(1),
                                decoration: BoxDecoration(
                                  color: backgroundColor,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: borderColor, width: 1.5),
                                  boxShadow: isSupplyDay
                                      ? [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.3),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    '${date.day}',
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              );
                            },
                            todayBuilder: (context, date, focusedDay) {
                              final isSupplyDay = _supplyDates.any((supplyDate) => DateUtils.isSameDay(supplyDate, date));
                              Color backgroundColor;
                              Color borderColor;
                              Color textColor;
                              if (isSupplyDay) {
                                backgroundColor = Colors.green.withOpacity(0.1);
                                borderColor = Colors.green;
                                textColor = Colors.red;
                              } else {
                                backgroundColor = Colors.transparent;
                                borderColor = Colors.transparent;
                                textColor = Colors.red;
                              }
                              return Container(
                                margin: const EdgeInsets.all(1),
                                decoration: BoxDecoration(
                                  color: backgroundColor,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: borderColor, width: 1.5),
                                ),
                                child: Center(
                                  child: Text(
                                    '${date.day}',
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          rowHeight: 45,
                          headerStyle: HeaderStyle(
                            titleCentered: true,
                            formatButtonVisible: true,
                            formatButtonShowsNext: false,
                            formatButtonDecoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            formatButtonTextStyle: const TextStyle(color: Colors.black),
                            leftChevronIcon: const Icon(Icons.chevron_left),
                            rightChevronIcon: const Icon(Icons.chevron_right),
                            headerPadding: const EdgeInsets.symmetric(vertical: 8),
                            titleTextStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          daysOfWeekStyle: const DaysOfWeekStyle(
                            weekdayStyle: TextStyle(fontWeight: FontWeight.bold),
                            weekendStyle: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Закрыть'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<List<int>> _getPriceHistoryFuture(int nmId) {
    if (!_priceHistoryFutures.containsKey(nmId)) {
      _priceHistoryFutures[nmId] = Future(() => _priceHistoryManager.getPricesForLastNDays(nmId, 21));
    }
    return _priceHistoryFutures[nmId]!;
  }

  Future<List<int>> _getSearchFrequenciesCached(int nmId) {
    if (!_searchFrequenciesFutures.containsKey(nmId)) {
      _searchFrequenciesFutures[nmId] = Future(() => _searchQueryService.getTotalFrequenciesForLastNDays(nmId, 21));
    }
    return _searchFrequenciesFutures[nmId]!;
  }

  Future<List<double>> _getTransitionsCached(int nmId) {
    if (!_transitionsFutures.containsKey(nmId)) {
      _transitionsFutures[nmId] = Future(() => _salesManager.getValuesForNmId(nmId, 21, open: true));
    }
    return _transitionsFutures[nmId]!;
  }

  List<DateTime> _getLastNDates(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(days, (index) => today.subtract(Duration(days: days - 1 - index)));
  }

  void _buildBarcodeMapFromProducts() {
    final productManager = ProductManager();
    if (!productManager.isInitialized) return;

    final newMap = <int, String>{};
    for (final product in productManager.allProducts) {
      final size = product.sizes.isNotEmpty ? product.sizes.first : null;
      final sku = size?.skus.isNotEmpty == true ? size!.skus.first : null;
      if (sku != null && sku.isNotEmpty) {
        newMap[product.nmID] = sku;
      }
    }
    setState(() {
      _barcodeMap = newMap;
    });
    debugPrint('📦 Загружено штрихкодов из продуктов: ${_barcodeMap.length}');
  }

  Future<void> _loadCurrentPrices() async {
    try {
      final response = await http.get(
        Uri.parse('https://hide_domain.com/current-prices'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['data'] as List<dynamic>?;
        if (items == null) return;

        final Map<int, int> tempPrices = {};
        for (var item in items) {
          int? nmId;
          final nmIdRaw = item['nm_id'];
          if (nmIdRaw is int) nmId = nmIdRaw;
          else if (nmIdRaw is double) nmId = nmIdRaw.toInt();
          else if (nmIdRaw is String) nmId = int.tryParse(nmIdRaw);

          int? price;
          final priceRaw = item['price'];
          if (priceRaw is int) price = priceRaw;
          else if (priceRaw is double) price = priceRaw.toInt();
          else if (priceRaw is String) price = int.tryParse(priceRaw);

          if (nmId != null && price != null) {
            tempPrices[nmId] = price;
          }
        }

        setState(() {
          _currentPrices = tempPrices;
        });
        debugPrint('✅ Загружено текущих цен: ${_currentPrices.length}');
      } else {
        debugPrint('❌ Ошибка загрузки current-prices: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Исключение при загрузке current-prices: $e');
    }
  }

  void _onSupplyPeriodTextChanged() {
    _supplyPeriodDebounceTimer?.cancel();
    _supplyPeriodDebounceTimer = Timer(const Duration(seconds: 2), () {
      final text = _supplyPeriodController.text.trim();
      final value = int.tryParse(text);
      if (value != null && value != _supplyPeriodDays) {
        setState(() {
          _supplyPeriodDays = value;
        });
        _refreshProviderData();
      }
    });
  }

  void _updateDateRangeController() {
    if (_selectedDateRange != null) {
      final start = _selectedDateRange!.start;
      final end = _selectedDateRange!.end;
      _dateRangeController.text = '${_formatDate(start)} – ${_formatDate(end)}';
    } else {
      _dateRangeController.text = '';
    }
  }

  String _formatDate(DateTime date) => DateFormat('dd.MM.yyyy').format(date);

  Future<void> _selectDateRange(BuildContext context) async {
    final result = await showDialog<DateTimeRange>(
      context: context,
      builder: (context) => SimpleDateRangePickerDialog(
        initialRange: _selectedDateRange,
        onConfirm: (range) {
          setState(() {
            _selectedDateRange = range;
            _updateDateRangeController();
          });
          _loadOrdersData();
        },
      ),
    );
  }

  Future<void> _fetchWarehouseMapping() async {
    setState(() {
      _isLoadingMapping = true;
    });
    try {
      final response = await http.get(Uri.parse('https://hide_domain.com/warehouse-mapping'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _warehouseMapping = {};
        _orderWarehouseMapping = {};
        for (var item in data) {
          final remainsName = item['wh_name_my_api_warehouse_remains']?.toString() ?? '';
          final wbName = item['wh_name_wb_api_warehouses']?.toString() ?? '';
          if (remainsName.isNotEmpty && wbName.isNotEmpty) {
            _warehouseMapping[remainsName.trim()] = wbName.trim();
          }
          final orderFeedName = item['wh_name_my_api_order_feed']?.toString() ?? '';
          if (orderFeedName.isNotEmpty && wbName.isNotEmpty) {
            _orderWarehouseMapping[orderFeedName.trim()] = wbName.trim();
          }
        }
        _isMappingLoaded = true;
      }
    } catch (e) {
      debugPrint('Ошибка загрузки маппинга складов: $e');
    } finally {
      setState(() {
        _isLoadingMapping = false;
      });
    }
  }

  void _applyWarehouseMapping() {
    _mappedArticlesSets.clear();
    _mappedStockSum.clear();
    _mappedNmIdQuantityMap.clear();

    for (final entry in _warehouseArticlesSets.entries) {
      final remainsName = entry.key;
      final wbName = _warehouseMapping.containsKey(remainsName)
          ? _warehouseMapping[remainsName]!
          : remainsName;
      if (_warehouses.any((w) => w.name == wbName)) {
        _mappedArticlesSets.update(
          wbName,
          (existing) => existing..addAll(entry.value),
          ifAbsent: () => Set<int>.from(entry.value),
        );
        _mappedStockSum[wbName] = (_mappedStockSum[wbName] ?? 0) + (_warehouseStockSum[remainsName] ?? 0);
      }
    }

    for (final entry in _warehouseNmIdQuantityMap.entries) {
      final remainsName = entry.key;
      final wbName = _warehouseMapping.containsKey(remainsName)
          ? _warehouseMapping[remainsName]!
          : remainsName;
      if (_warehouses.any((w) => w.name == wbName)) {
        _mappedNmIdQuantityMap.putIfAbsent(wbName, () => {});
        for (final nmEntry in entry.value.entries) {
          _mappedNmIdQuantityMap[wbName]![nmEntry.key] =
              (_mappedNmIdQuantityMap[wbName]![nmEntry.key] ?? 0) + nmEntry.value;
        }
      }
    }

    _useMapping = true;
    _reorderWarehouses();
  }

  Future<void> _loadWarehouses() async {
    setState(() {
      _isLoadingWarehouses = true;
      _warehousesError = null;
    });

    try {
      await TokenManager().initialize();
      final token = await TokenManager().getToken();

      if (token == null || token.isEmpty) {
        throw Exception('Токен авторизации отсутствует');
      }

      final url = Uri.parse('https://supplies-api.wildberries.ru/api/v1/warehouses');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        final List<Warehouse> allWarehouses = jsonList
            .map((json) => Warehouse.fromJson(json as Map<String, dynamic>))
            .toList();

        setState(() {
          _warehouses = allWarehouses;
          _reorderWarehouses();
          if (_warehouses.isNotEmpty) {
            _selectedWarehouse = null;
          } else {
            _warehousesError = 'Склады не найдены';
          }
        });
      } else if (response.statusCode == 401) {
        throw Exception('Ошибка авторизации. Проверьте токен.');
      } else {
        throw Exception('Ошибка загрузки складов: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _warehousesError = e.toString();
      });
    } finally {
      setState(() {
        _isLoadingWarehouses = false;
      });
    }
  }

  Future<void> _fetchWarehouseRemainsStats() async {
    setState(() {
      _isLoadingRemainsStats = true;
      _remainsStatsError = null;
    });

    try {
      final response = await http.get(Uri.parse('https://hide_domain.com/warehouse-remains?get_all=true'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        final List<dynamic> data = jsonResponse['data'] as List<dynamic>? ?? [];

        final Map<String, Set<int>> warehouseArticles = {};
        final Map<String, int> warehouseTotalStock = {};
        final Map<String, Map<int, int>> warehouseNmIdQuantity = {};
        final Set<String> warehousesSet = {};
        int totalStock = 0;
        final Set<int> articlesSet = {};

        for (var item in data) {
          final warehouseName = item['warehouse_name'] as String? ?? '';
          if (warehouseName.isEmpty) continue;

          warehousesSet.add(warehouseName);
          final nmId = item['nm_id'] as int?;
          final quantity = (item['quantity'] as num?)?.toInt() ?? 0;

          if (nmId != null) {
            warehouseArticles.putIfAbsent(warehouseName, () => {}).add(nmId);
            articlesSet.add(nmId);

            warehouseNmIdQuantity.putIfAbsent(warehouseName, () => {});
            warehouseNmIdQuantity[warehouseName]![nmId] =
                (warehouseNmIdQuantity[warehouseName]![nmId] ?? 0) + quantity;
          }
          warehouseTotalStock[warehouseName] = (warehouseTotalStock[warehouseName] ?? 0) + quantity;
          totalStock += quantity;
        }

        setState(() {
          _warehouseArticlesSets = warehouseArticles;
          _warehouseArticleCount = warehouseArticles.map((k, v) => MapEntry(k, v.length));
          _warehouseStockSum = warehouseTotalStock;
          _warehouseNmIdQuantityMap = warehouseNmIdQuantity;
          _uniqueWarehouseCount = warehousesSet.length;
          _totalStockSum = totalStock;
          _uniqueArticleCount = articlesSet.length;
          _isLoadingRemainsStats = false;
        });

        final wbCountWithStock = _warehouses.where((w) => (_warehouseStockSum[w.name] ?? 0) > 0).length;
        if (wbCountWithStock < _uniqueWarehouseCount) {
          await _fetchWarehouseMapping();
          if (_isMappingLoaded) {
            _applyWarehouseMapping();
          } else {
            _reorderWarehouses();
          }
        } else {
          _reorderWarehouses();
        }

        _buildDataMapsForSelectedWarehouse();

        if (_stockTimeSeriesByWarehouse.isEmpty) {
          _loadStockHistory();
        }
      } else {
        throw Exception('Ошибка загрузки статистики: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _remainsStatsError = e.toString();
        _isLoadingRemainsStats = false;
      });
    }
  }

  Future<void> _loadOrdersData() async {
    if (_ordersLoadedFromPrecomputed) return;
    if (_selectedDateRange == null) return;

    final token = await TokenManager().getToken();
    if (token == null || token.isEmpty) {
      debugPrint('⚠️ Публичный токен отсутствует. Заказы не загружены.');
      return;
    }

    final privateTokenManager = PrivateTokenManager();
    await privateTokenManager.initialize();
    if (!privateTokenManager.hasKeysSync()) {
      debugPrint('⚠️ Приватные ключи отсутствуют. Заказы недоступны.');
      setState(() {
        _ordersError = 'Нет приватных ключей для заказов';
      });
      return;
    }

    setState(() {
      _isLoadingOrders = true;
      _ordersError = null;
    });

    try {
      final dateFormat = DateFormat('yyyy-MM-dd');
      final requestBody = {
        'date_from': dateFormat.format(_selectedDateRange!.start),
        'date_to': dateFormat.format(_selectedDateRange!.end),
        'authorize_v3': privateTokenManager.authorizeV3,
        'wb_seller_lk': privateTokenManager.wbSellerLk,
        'cookie': privateTokenManager.cookie,
      };

      final startUrl = Uri.parse('https://hide_domain.com/api/orders/export-csv/start');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
      final startResponse = await http.post(
        startUrl,
        headers: headers,
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (startResponse.statusCode != 200) {
        throw Exception('Ошибка создания задачи: ${startResponse.statusCode}');
      }
      final startData = json.decode(startResponse.body);
      final taskId = startData['task_id'];

      String status = 'pending';
      String? downloadUrl;
      int attempts = 0;
      const maxAttempts = 150;

      while (status == 'pending' && attempts < maxAttempts) {
        await Future.delayed(const Duration(seconds: 2));
        attempts++;

        final statusUrl = Uri.parse('https://hide_domain.com/api/orders/export-csv/status/$taskId');
        final statusResponse = await http.get(
          statusUrl,
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 10));

        if (statusResponse.statusCode != 200) {
          debugPrint('Ошибка получения статуса: ${statusResponse.statusCode}');
          continue;
        }

        final statusData = json.decode(statusResponse.body);
        status = statusData['status'];
        if (status == 'done') {
          downloadUrl = statusData['download_url'];
          break;
        } else if (status == 'error') {
          throw Exception(statusData['error'] ?? 'Неизвестная ошибка при формировании отчёта');
        }
      }

      if (status != 'done' || downloadUrl == null) {
        throw Exception('Время ожидания отчёта истекло');
      }

      final downloadResponse = await http.get(
        Uri.parse('https://hide_domain.com$downloadUrl'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 120));

      if (downloadResponse.statusCode != 200) {
        throw Exception('Ошибка скачивания CSV: ${downloadResponse.statusCode}');
      }

      final csvString = utf8.decode(downloadResponse.bodyBytes);
      final csvRows = const CsvToListConverter().convert(csvString, eol: '\n');
      _processOrdersCsv(csvRows);
    } catch (e, stack) {
      debugPrint('❌ Ошибка _loadOrdersData: $e\n$stack');
      setState(() {
        _ordersError = e.toString();
      });
    } finally {
      setState(() {
        _isLoadingOrders = false;
      });
    }
  }

  void _processOrdersCsv(List<List<dynamic>> csvRows) {
    if (csvRows.isEmpty) {
      setState(() {
        _ordersWarehouseCount = 0;
        _totalOrdersCount = 0;
        _ordersUniqueArticlesCount = 0;
        _ordersNmIdCountByWB = {};
        _ordersWarehouseCountMap = {};
        _ordersWarehouseArticlesMap = {};
        _cancellationsByWB = {};
        _returnsByWB = {};
        _salesByWB = {};
      });
      _buildDataMapsForSelectedWarehouse();
      return;
    }

    final headersRow = csvRows.first.map((e) => e.toString().trim()).toList();
    int? warehouseColIdx;
    int? nmIdColIdx;
    int? typeColIdx;
    int? statusColIdx;
    int? dateColIdx;

    for (int i = 0; i < headersRow.length; i++) {
      final lower = headersRow[i].toLowerCase();
      if (lower.contains('empty') && warehouseColIdx == null) {
        warehouseColIdx = i;
      } else if ((lower.contains('артикул wb') || lower.contains('nm')) && nmIdColIdx == null) {
        nmIdColIdx = i;
      } else if (lower.contains('тип склада') && typeColIdx == null) {
        typeColIdx = i;
      } else if (statusColIdx == null && lower.contains('статус')) {
        if (!lower.contains('дата')) statusColIdx = i;
      } else if (lower.contains('дата оформления заказа') && dateColIdx == null) {
        dateColIdx = i;
      }
    }

    if (statusColIdx == null && csvRows.length > 1) {
      const possibleStatusValues = {'Создан', 'Выкуплен', 'Отказ', 'Возврат'};
      for (int col = 0; col < headersRow.length; col++) {
        bool found = false;
        for (int row = 1; row <= (csvRows.length-1 > 10 ? 10 : csvRows.length-1); row++) {
          final rowData = csvRows[row];
          if (rowData.length > col) {
            final cellValue = rowData[col].toString().trim();
            if (possibleStatusValues.contains(cellValue)) {
              found = true;
              break;
            }
          }
        }
        if (found) {
          statusColIdx = col;
          break;
        }
      }
    }

    if (warehouseColIdx == null && headersRow.length > 13) warehouseColIdx = 13;
    if (warehouseColIdx == null || nmIdColIdx == null) {
      debugPrint('❌ Не найдены колонки склад или nmId');
      return;
    }

    final Map<String, int> warehouseOrdersCount = {};
    final Map<String, Set<int>> warehouseArticles = {};
    final Map<String, Map<int, int>> warehouseNmIdOrders = {};
    final Map<String, Map<int, int>> cancellationsByWB = {};
    final Map<String, Map<int, int>> returnsByWB = {};
    final Map<String, Map<int, int>> salesByWB = {};
    int totalOrders = 0;

    _ordersTimeSeriesByWarehouse.clear();

    for (int i = 1; i < csvRows.length; i++) {
      final row = csvRows[i];
      if (row.length <= warehouseColIdx || row.length <= nmIdColIdx) continue;

      if (typeColIdx != null && row.length > typeColIdx) {
        final type = row[typeColIdx].toString().trim();
        if (type == 'Свои склады') continue;
      }

      final warehouseRaw = row[warehouseColIdx].toString().trim();
      if (warehouseRaw.isEmpty) continue;

      final nmIdRaw = row[nmIdColIdx];
      int nmId = 0;
      if (nmIdRaw is int) nmId = nmIdRaw;
      else if (nmIdRaw is String) nmId = int.tryParse(nmIdRaw) ?? 0;
      if (nmId <= 0) continue;

      if (dateColIdx != null && row.length > dateColIdx && typeColIdx != null && row.length > typeColIdx) {
        final type = row[typeColIdx].toString().trim();
        if (type == 'Склады WB') {
          final dateStr = row[dateColIdx].toString().trim();
          DateTime? orderDate;
          try {
            orderDate = DateTime.parse(dateStr);
            orderDate = DateTime(orderDate.year, orderDate.month, orderDate.day);
          } catch (_) {}
          if (orderDate != null) {
            final wbName = _orderWarehouseMapping.containsKey(warehouseRaw)
                ? _orderWarehouseMapping[warehouseRaw]!
                : warehouseRaw;
            _ordersTimeSeriesByWarehouse.putIfAbsent(wbName, () => {});
            _ordersTimeSeriesByWarehouse[wbName]!.putIfAbsent(nmId, () => {});
            _ordersTimeSeriesByWarehouse[wbName]![nmId]![orderDate] =
                (_ordersTimeSeriesByWarehouse[wbName]![nmId]![orderDate] ?? 0) + 1;
          }
        }
      }

      final wbName = _orderWarehouseMapping.containsKey(warehouseRaw)
          ? _orderWarehouseMapping[warehouseRaw]!
          : warehouseRaw;

      warehouseArticles.putIfAbsent(warehouseRaw, () => {}).add(nmId);
      warehouseNmIdOrders.putIfAbsent(warehouseRaw, () => {});
      warehouseNmIdOrders[warehouseRaw]![nmId] = (warehouseNmIdOrders[warehouseRaw]![nmId] ?? 0) + 1;
      warehouseOrdersCount[warehouseRaw] = (warehouseOrdersCount[warehouseRaw] ?? 0) + 1;
      totalOrders++;

      if (statusColIdx != null && row.length > statusColIdx) {
        final status = row[statusColIdx].toString().trim();
        switch (status) {
          case 'Отказ':
            cancellationsByWB.putIfAbsent(wbName, () => {});
            cancellationsByWB[wbName]![nmId] = (cancellationsByWB[wbName]![nmId] ?? 0) + 1;
            break;
          case 'Возврат':
            returnsByWB.putIfAbsent(wbName, () => {});
            returnsByWB[wbName]![nmId] = (returnsByWB[wbName]![nmId] ?? 0) + 1;
            break;
          case 'Выкуплен':
            salesByWB.putIfAbsent(wbName, () => {});
            salesByWB[wbName]![nmId] = (salesByWB[wbName]![nmId] ?? 0) + 1;
            break;
        }
      }
    }

    final Map<String, int> ordersByWB = {};
    final Map<String, Set<int>> articlesByWB = {};
    final Map<String, Map<int, int>> ordersNmIdCountByWB = {};

    for (final entry in warehouseNmIdOrders.entries) {
      final rawName = entry.key;
      final wbName = _orderWarehouseMapping.containsKey(rawName)
          ? _orderWarehouseMapping[rawName]!
          : rawName;

      ordersNmIdCountByWB.putIfAbsent(wbName, () => {});
      for (final nmEntry in entry.value.entries) {
        ordersNmIdCountByWB[wbName]![nmEntry.key] =
            (ordersNmIdCountByWB[wbName]![nmEntry.key] ?? 0) + nmEntry.value;
      }
    }

    for (final entry in warehouseOrdersCount.entries) {
      final rawName = entry.key;
      final wbName = _orderWarehouseMapping.containsKey(rawName)
          ? _orderWarehouseMapping[rawName]!
          : rawName;
      ordersByWB[wbName] = (ordersByWB[wbName] ?? 0) + entry.value;
    }

    for (final entry in warehouseArticles.entries) {
      final rawName = entry.key;
      final wbName = _orderWarehouseMapping.containsKey(rawName)
          ? _orderWarehouseMapping[rawName]!
          : rawName;
      articlesByWB.putIfAbsent(wbName, () => <int>{}).addAll(entry.value);
    }

    setState(() {
      _ordersWarehouseCount = ordersByWB.length;
      _totalOrdersCount = totalOrders;
      _ordersUniqueArticlesCount = ordersNmIdCountByWB.values
          .expand((map) => map.keys)
          .toSet()
          .length;
      _ordersNmIdCountByWB = ordersNmIdCountByWB;
      _ordersWarehouseCountMap = ordersByWB;
      _ordersWarehouseArticlesMap = articlesByWB;
      _cancellationsByWB = cancellationsByWB;
      _returnsByWB = returnsByWB;
      _salesByWB = salesByWB;
    });

    _buildDataMapsForSelectedWarehouse();
  }

  Future<void> _loadPrecomputedOrdersData() async {
    debugPrint('🔄 Загрузка предвычисленного CSV...');

    try {
      final response = await http.get(
        Uri.parse('https://hide_domain.com/order-feed/latest'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final csvString = utf8.decode(response.bodyBytes);
        final csvRows = const CsvToListConverter().convert(csvString, eol: '\n');
        _processOrdersCsv(csvRows);
        setState(() {
          _ordersLoadedFromPrecomputed = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _tableKey.currentState?.setSort('orders_per_day', descending: true);
        });
        debugPrint('✅ Заказы загружены из предвычисленного CSV (${csvRows.length} строк)');
      } else {
        debugPrint('⚠️ Ошибка ${response.statusCode}, загружаем через экспорт...');
        await _loadOrdersData();
      }
    } catch (e) {
      debugPrint('❌ Ошибка загрузки предвычисленного CSV: $e');
      await _loadOrdersData();
    }
  }

  Future<void> _loadStockHistory() async {
    setState(() {
      _isLoadingStockHistory = true;
      _stockHistoryError = null;
    });

    try {
      final url = Uri.parse('https://hide_domain.com/warehouse-stock-history/export?days=21');
      final response = await http.get(url, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки истории остатков: ${response.statusCode}');
      }

      final csvString = utf8.decode(response.bodyBytes);
      final csvRows = const CsvToListConverter().convert(csvString, eol: '\n');
      if (csvRows.isEmpty || csvRows.length < 2) return;

      final headers = csvRows.first.map((e) => e.toString().trim().toLowerCase()).toList();
      int dateIdx = headers.indexOf('date');
      int nmIdIdx = headers.indexOf('nm_id');
      int whIdx = headers.indexOf('warehouse_name');
      int qtyIdx = headers.indexOf('quantity');
      if (dateIdx == -1 || nmIdIdx == -1 || whIdx == -1 || qtyIdx == -1) {
        throw Exception('Неверный формат CSV истории остатков');
      }

      final Map<String, Map<int, Map<DateTime, int>>> tempMap = {};

      for (int i = 1; i < csvRows.length; i++) {
        final row = csvRows[i];
        if (row.length <= qtyIdx) continue;

        final dateStr = row[dateIdx].toString().trim();
        final nmIdRaw = row[nmIdIdx];
        final whRaw = row[whIdx].toString().trim();
        final qtyRaw = row[qtyIdx];

        int nmId = 0;
        if (nmIdRaw is int) nmId = nmIdRaw;
        else if (nmIdRaw is String) nmId = int.tryParse(nmIdRaw) ?? 0;
        if (nmId <= 0) continue;

        int qty = 0;
        if (qtyRaw is int) qty = qtyRaw;
        else if (qtyRaw is String) qty = int.tryParse(qtyRaw) ?? 0;
        if (qty < 0) continue;

        DateTime date;
        try {
          date = DateTime.parse(dateStr);
          date = DateTime(date.year, date.month, date.day);
        } catch (_) {
          continue;
        }

        final wbName = _warehouseMapping.containsKey(whRaw) ? _warehouseMapping[whRaw]! : whRaw;

        if (!_warehouses.any((w) => w.name == wbName)) continue;

        tempMap.putIfAbsent(wbName, () => {});
        tempMap[wbName]!.putIfAbsent(nmId, () => {});
        tempMap[wbName]![nmId]![date] = qty;
      }

      setState(() {
        _stockTimeSeriesByWarehouse = tempMap;
        _isLoadingStockHistory = false;
      });
      _buildDataMapsForSelectedWarehouse();
    } catch (e) {
      setState(() {
        _stockHistoryError = e.toString();
        _isLoadingStockHistory = false;
      });
    }
  }

  Future<List<int>> _getOrdersTimeSeriesCached(int nmId) {
    if (!_ordersTimeSeriesFutures.containsKey(nmId)) {
      _ordersTimeSeriesFutures[nmId] = Future(() {
        final dayMap = _currentOrdersTimeSeriesMap[nmId] ?? {};
        final dates = _getLastNDates(21);
        return dates.map((date) => dayMap[date] ?? 0).toList();
      });
    }
    return _ordersTimeSeriesFutures[nmId]!;
  }

  Future<List<int>> _getStockTimeSeriesCached(int nmId) {
    if (!_stockTimeSeriesFutures.containsKey(nmId)) {
      _stockTimeSeriesFutures[nmId] = Future(() {
        final dayMap = _currentStockTimeSeriesMap[nmId] ?? {};
        final dates = _getLastNDates(21);
        return dates.map((date) => dayMap[date] ?? 0).toList();
      });
    }
    return _stockTimeSeriesFutures[nmId]!;
  }

  void _reorderWarehouses() {
    if (_warehouses.isEmpty) return;
    _warehouses.sort((a, b) {
      final stockA = _useMapping
          ? (_mappedStockSum[a.name] ?? 0)
          : _warehouseStockSum[a.name] ?? 0;
      final stockB = _useMapping
          ? (_mappedStockSum[b.name] ?? 0)
          : _warehouseStockSum[b.name] ?? 0;
      return stockB.compareTo(stockA);
    });
    if (_selectedWarehouse != null && !_warehouses.contains(_selectedWarehouse)) {
      _selectedWarehouse = _warehouses.isNotEmpty ? _warehouses.first : null;
    }
  }

  void _buildDataMapsForSelectedWarehouse() {
    _checkStatus.clear();
    final sourceStockMap = _useMapping ? _mappedNmIdQuantityMap : _warehouseNmIdQuantityMap;
    final sourceOrdersMap = _ordersNmIdCountByWB;

    if (_selectedWarehouse == null) {
      _currentStockMap = {};
      for (final whStock in sourceStockMap.values) {
        for (final entry in whStock.entries) {
          _currentStockMap[entry.key] = (_currentStockMap[entry.key] ?? 0) + entry.value;
        }
      }
      _currentOrdersMap = {};
      for (final whOrders in sourceOrdersMap.values) {
        for (final entry in whOrders.entries) {
          _currentOrdersMap[entry.key] = (_currentOrdersMap[entry.key] ?? 0) + entry.value;
        }
      }
      _currentCancellationsMap = _aggregateStatusMaps(_cancellationsByWB);
      _currentReturnsMap = _aggregateStatusMaps(_returnsByWB);
      _currentSalesMap = _aggregateStatusMaps(_salesByWB);
    } else {
      final whName = _selectedWarehouse!.name;
      _currentStockMap = Map<int, int>.from(sourceStockMap[whName] ?? {});
      _currentOrdersMap = Map<int, int>.from(sourceOrdersMap[whName] ?? {});
      _currentCancellationsMap = Map<int, int>.from(_cancellationsByWB[whName] ?? {});
      _currentReturnsMap = Map<int, int>.from(_returnsByWB[whName] ?? {});
      _currentSalesMap = Map<int, int>.from(_salesByWB[whName] ?? {});
    }

    if (_selectedDateRange != null) {
      _currentDaysRange = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays + 1;
    } else {
      _currentDaysRange = 1;
    }

    _currentOrdersTimeSeriesMap.clear();
    if (_selectedWarehouse == null) {
      for (final whMap in _ordersTimeSeriesByWarehouse.values) {
        for (final nmEntry in whMap.entries) {
          final nmId = nmEntry.key;
          final dayMap = nmEntry.value;
          _currentOrdersTimeSeriesMap.putIfAbsent(nmId, () => {});
          for (final dayEntry in dayMap.entries) {
            final date = dayEntry.key;
            final count = dayEntry.value;
            _currentOrdersTimeSeriesMap[nmId]![date] =
                (_currentOrdersTimeSeriesMap[nmId]![date] ?? 0) + count;
          }
        }
      }
    } else {
      final whName = _selectedWarehouse!.name;
      final whData = _ordersTimeSeriesByWarehouse[whName];
      if (whData != null) {
        for (final nmEntry in whData.entries) {
          _currentOrdersTimeSeriesMap[nmEntry.key] = Map.from(nmEntry.value);
        }
      }
    }

    _currentStockTimeSeriesMap.clear();
    if (_selectedWarehouse == null) {
      for (final whMap in _stockTimeSeriesByWarehouse.values) {
        for (final nmEntry in whMap.entries) {
          final nmId = nmEntry.key;
          final dayMap = nmEntry.value;
          _currentStockTimeSeriesMap.putIfAbsent(nmId, () => {});
          for (final dayEntry in dayMap.entries) {
            final date = dayEntry.key;
            final count = dayEntry.value;
            _currentStockTimeSeriesMap[nmId]![date] =
                (_currentStockTimeSeriesMap[nmId]![date] ?? 0) + count;
          }
        }
      }
    } else {
      final whName = _selectedWarehouse!.name;
      final whData = _stockTimeSeriesByWarehouse[whName];
      if (whData != null) {
        for (final nmEntry in whData.entries) {
          _currentStockTimeSeriesMap[nmEntry.key] = Map.from(nmEntry.value);
        }
      }
    }

    _stockTimeSeriesFutures.clear();
    _updateCurrentInTransitData();
    _refreshProviderData();
  }

  Map<int, int> _aggregateStatusMaps(Map<String, Map<int, int>> source) {
    final result = <int, int>{};
    for (final whMap in source.values) {
      for (final entry in whMap.entries) {
        result[entry.key] = (result[entry.key] ?? 0) + entry.value;
      }
    }
    return result;
  }

  void _refreshProviderData() {
    _provider.updateData(
      newStockMap: _currentStockMap,
      newOrdersMap: _currentOrdersMap,
      newCancellationsMap: _currentCancellationsMap,
      newReturnsMap: _currentReturnsMap,
      newSalesMap: _currentSalesMap,
      newBarcodeMap: _barcodeMap,
      newDaysRange: _currentDaysRange,
      newCheckStatusMap: _checkStatus,
      newSupplyPeriodDays: _supplyPeriodDays,
      newInTransitMap: _currentInTransitMap,
      newBatchData: _batchData,
    );
    _tableController.refreshData();
  }

  Widget _buildDebugStats() {
    if (_isLoadingRemainsStats || _isLoadingOrders) {
      return const Row(
        children: [
          SizedBox(width: 8, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Загрузка статистики...', style: TextStyle(fontSize: 12)),
        ],
      );
    }
    if (_remainsStatsError != null || _ordersError != null) {
      return Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _remainsStatsError ?? _ordersError ?? '',
              style: const TextStyle(fontSize: 12, color: Colors.red),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Склады(остатки): $_uniqueWarehouseCount | Остатки(остатки): $_totalStockSum | Артикулы(остатки): $_uniqueArticleCount',
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          'Склады(заказы): $_ordersWarehouseCount | Заказы(заказы): $_totalOrdersCount | Артикулы(заказы): $_ordersUniqueArticlesCount',
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Future<void> _retryLoadWarehouses() async {
    await _loadWarehouses();
  }

  void _showAddressDialog(String address) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Адрес склада'),
        content: Text(address),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    Color activeColor = Colors.green,
    Color inactiveColor = Colors.grey,
  }) {
    const double fixedWidth = 50;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: fixedWidth,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.2) : inactiveColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? activeColor : inactiveColor,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: isActive ? activeColor : inactiveColor),
            const SizedBox(width: 2),
            Text(
              isActive ? 'Да' : 'Нет',
              style: TextStyle(
                fontSize: 10,
                color: isActive ? activeColor : inactiveColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCombinedStatsChip({
    required int articleCount,
    required int stockSum,
    bool hasData = true,
  }) {
    const double combinedWidth = 100;
    return SizedBox(
      width: combinedWidth,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: hasData ? Colors.grey.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasData ? Colors.grey.shade400 : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Tooltip(
              message: 'Количество артикулов',
              child: Text(
                articleCount.toString(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: hasData ? Colors.green.shade800 : Colors.grey.shade600,
                ),
              ),
            ),
            Container(
              width: 1,
              height: 14,
              color: Colors.grey.shade400,
            ),
            Tooltip(
              message: 'Сумма остатков',
              child: Text(
                stockSum.toString(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: hasData ? Colors.orange.shade800 : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersStatsChip({
    required int articleCount,
    required int ordersCount,
    bool hasData = true,
  }) {
    const double combinedWidth = 100;
    return SizedBox(
      width: combinedWidth,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: hasData ? Colors.blue.shade50.withOpacity(0.5) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasData ? Colors.blue.shade300 : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Tooltip(
              message: 'Уникальные артикулы в заказах',
              child: Text(
                articleCount.toString(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: hasData ? Colors.blue.shade800 : Colors.grey.shade600,
                ),
              ),
            ),
            Container(
              width: 1,
              height: 14,
              color: Colors.grey.shade400,
            ),
            Tooltip(
              message: 'Количество заказов',
              child: Text(
                ordersCount.toString(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: hasData ? Colors.red.shade800 : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarehouseItem(Warehouse? warehouse) {
    if (warehouse == null) {
      if (_isLoadingRemainsStats) {
        return const Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Все склады (загрузка...)', style: TextStyle(fontSize: 14)),
          ],
        );
      }

      final Set<int> allArticles = {};
      int stockSum = 0;
      int warehousesWithStock = 0;
      for (final wh in _warehouses) {
        final articlesSet = _useMapping
            ? _mappedArticlesSets[wh.name]
            : _warehouseArticlesSets[wh.name];
        if (articlesSet != null && articlesSet.isNotEmpty) {
          allArticles.addAll(articlesSet);
        }
        final whStock = _useMapping
            ? (_mappedStockSum[wh.name] ?? 0)
            : _warehouseStockSum[wh.name] ?? 0;
        stockSum += whStock;
        if (whStock > 0) {
          warehousesWithStock++;
        }
      }
      final int articleCount = allArticles.length;
      final bool hasData = articleCount > 0 || stockSum > 0;

      final int warehousesWithOrders = _warehouses.where((w) {
        return (_ordersWarehouseCountMap[w.name] ?? 0) > 0;
      }).length;

      return Container(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Все склады',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            _buildCombinedStatsChip(
              articleCount: articleCount,
              stockSum: stockSum,
              hasData: hasData,
            ),
            const SizedBox(width: 6),
            Builder(builder: (_) {
              final int allOrders = _warehouses.fold<int>(0, (sum, wh) => sum + (_ordersWarehouseCountMap[wh.name] ?? 0));
              final Set<int> allOrderArticles = {};
              for (final wh in _warehouses) {
                final articles = _ordersWarehouseArticlesMap[wh.name];
                if (articles != null) allOrderArticles.addAll(articles);
              }
              final int ordersArticleCount = allOrderArticles.length;
              final bool hasOrders = allOrders > 0;

              return _buildOrdersStatsChip(
                articleCount: ordersArticleCount,
                ordersCount: allOrders,
                hasData: hasOrders,
              );
            }),
            const SizedBox(width: 6),
            SizedBox(
              width: 100,
              child: Tooltip(
                message: 'Количество складов с остатками',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: warehousesWithStock > 0 ? Colors.blue.shade50 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: warehousesWithStock > 0 ? Colors.blue.shade300 : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    '$warehousesWithStock склад(-ов)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: warehousesWithStock > 0 ? Colors.blue.shade800 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 100,
              child: Tooltip(
                message: 'Количество складов с заказами',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: warehousesWithOrders > 0 ? Colors.blue.shade50 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: warehousesWithOrders > 0 ? Colors.blue.shade300 : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    '$warehousesWithOrders склад(-ов)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: warehousesWithOrders > 0 ? Colors.blue.shade800 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final articleCount = _useMapping
        ? (_mappedArticlesSets[warehouse.name]?.length ?? 0)
        : _warehouseArticleCount[warehouse.name] ?? 0;
    final stockSum = _useMapping
        ? (_mappedStockSum[warehouse.name] ?? 0)
        : _warehouseStockSum[warehouse.name] ?? 0;
    final hasData = articleCount > 0 || stockSum > 0;

    return Container(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Row(
        children: [
          Expanded(
            child: Text(
              warehouse.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          _buildCombinedStatsChip(
            articleCount: articleCount,
            stockSum: stockSum,
            hasData: hasData,
          ),
          const SizedBox(width: 6),
          Builder(builder: (_) {
            final ordersCount = _ordersWarehouseCountMap[warehouse.name] ?? 0;
            final ordersArticleCount = _ordersWarehouseArticlesMap[warehouse.name]?.length ?? 0;
            final hasOrders = ordersCount > 0;

            return _buildOrdersStatsChip(
              articleCount: ordersArticleCount,
              ordersCount: ordersCount,
              hasData: hasOrders,
            );
          }),
          const SizedBox(width: 6),
          _buildStatusChip(
            icon: Icons.transfer_within_a_station,
            tooltip: warehouse.isTransitActive ? 'Транзит разрешен' : 'Транзит недоступен',
            isActive: warehouse.isTransitActive,
          ),
          const SizedBox(width: 6),
          _buildStatusChip(
            icon: Icons.check_circle,
            tooltip: warehouse.isActive ? 'Поставки разрешены' : 'Поставки недоступны',
            isActive: warehouse.isActive,
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Адрес склада',
            child: GestureDetector(
              onTap: () => _showAddressDialog(warehouse.address),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.location_on, size: 16, color: Colors.blue),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingStatusWidget() {
    final isLoading = _isLoadingWarehouses ||
        _isLoadingRemainsStats ||
        _isLoadingOrders ||
        _isLoadingMapping;

    if (isLoading) {
      List<String> parts = [];
      if (_isLoadingWarehouses) parts.add('Склады');
      if (_isLoadingRemainsStats) parts.add('Остатки');
      if (_isLoadingOrders) parts.add('Заказы');
      if (_isLoadingMapping) parts.add('Маппинг');
      final loadingText = parts.isEmpty ? 'Загрузка' : parts.join('/');
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.blue,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            loadingText,
            style: const TextStyle(fontSize: 14, color: Colors.blue),
          ),
        ],
      );
    } else {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.check_circle, color: Colors.green, size: 20),
          SizedBox(width: 8),
          Text('Готово', style: TextStyle(fontSize: 14, color: Colors.green)),
        ],
      );
    }
  }

  List<ColumnDefinition> _buildColumns() {
    return [
      ColumnDefinition(
        field: 'supplier_article',
        title: 'Артикул поставщика',
        dataType: ColumnDataType.text,
        width: 150,
      ),
      ColumnDefinition(
        field: 'wb_article',
        title: 'Артикул WB',
        dataType: ColumnDataType.number,
        width: 100,
      ),
      ColumnDefinition(
        field: 'name',
        title: 'Наименование',
        dataType: ColumnDataType.text,
        width: 300,
      ),
      ColumnDefinition(
        field: 'subject',
        title: 'Предмет',
        dataType: ColumnDataType.text,
        width: 150,
      ),
      ColumnDefinition(
        field: 'tags',
        title: 'Тэги',
        dataType: ColumnDataType.text,
        width: 200,
      ),
      ColumnDefinition(
        field: 'preview_photo',
        title: 'Превью',
        dataType: ColumnDataType.text,
        width: 80,
        minWidth: 30,
        hideTitle: true,
        showStatistics: false,
        showAggregation: false,
        showChart: false,
        showSort: false,
        showFilter: false,
        showDataType: false,
        cellPadding: EdgeInsets.zero,
      ),
      ColumnDefinition(
        field: 'barcode',
        title: 'Штрихкод',
        dataType: ColumnDataType.text,
        width: 140,
      ),
      ColumnDefinition(
        field: 'stock',
        title: 'Остаток',
        dataType: ColumnDataType.number,
        width: 80,
      ),
      ColumnDefinition(
        field: 'orders',
        title: 'Заказов',
        dataType: ColumnDataType.number,
        width: 80,
      ),
      ColumnDefinition(
        field: 'orders_per_day',
        title: 'Заказов в день',
        dataType: ColumnDataType.number,
        width: 100,
      ),
      ColumnDefinition(
        field: 'cancellations',
        title: 'Отмены',
        dataType: ColumnDataType.number,
        width: 80,
      ),
      ColumnDefinition(
        field: 'returns',
        title: 'Возвраты',
        dataType: ColumnDataType.number,
        width: 80,
      ),
      ColumnDefinition(
        field: 'sales',
        title: 'Продажи',
        dataType: ColumnDataType.number,
        width: 80,
      ),
      ColumnDefinition(
        field: 'stock_days',
        title: 'На сколько дней хватит остатков',
        dataType: ColumnDataType.number,
        width: 180,
      ),
      ColumnDefinition(
        field: 'in_transit',
        title: 'В пути в поставках на WB',
        dataType: ColumnDataType.number,
        width: 100,
      ),
      ColumnDefinition(
        field: 'demand',
        title: 'Потребность',
        dataType: ColumnDataType.number,
        width: 100,
      ),
      ColumnDefinition(
        field: 'ready_to_ship',
        title: 'Готово к отгрузке',
        dataType: ColumnDataType.number,
        width: 100,
      ),
      ColumnDefinition(
        field: 'to_supply',
        title: 'К поставке',
        dataType: ColumnDataType.number,
        width: 100,
      ),
      ColumnDefinition(
        field: 'check_status',
        title: 'Проверка',
        dataType: ColumnDataType.text,
        width: 100,
      ),
      ColumnDefinition(
        field: 'dynamic_prices',
        title: 'Динамика цен',
        dataType: ColumnDataType.text,
        width: 120,
        showSort: false,
      ),
      ColumnDefinition(
        field: 'dynamic_orders',
        title: 'Динамика заказов',
        dataType: ColumnDataType.text,
        width: 120,
        showSort: false,
      ),
      ColumnDefinition(
        field: 'dynamic_stocks',
        title: 'Динамика остатков',
        dataType: ColumnDataType.text,
        width: 120,
        showSort: false,
      ),
      ColumnDefinition(
        field: 'dynamic_queries',
        title: 'Динамика запросов',
        dataType: ColumnDataType.text,
        width: 120,
        showSort: false,
      ),
      ColumnDefinition(
        field: 'dynamic_transitions',
        title: 'Динамика переходов',
        dataType: ColumnDataType.text,
        width: 120,
        showSort: false,
      ),
    ];
  }

  Map<String, Widget Function(PlutoRow)> _buildCustomCellBuilders() {
    Widget numericCellBuilder(PlutoRow row, String field) {
      final value = row.cells[field]?.value;
      String display = '';
      if (value != null) {
        if (value is num) {
          if (value == 0) {
            display = '';
          } else if (value is double) {
            display = value.toStringAsFixed(2);
          } else {
            display = value.toString();
          }
        } else {
          display = value.toString();
        }
      }
      return Center(
        child: Text(
          display,
          style: const TextStyle(fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    final Map<String, Widget Function(PlutoRow)> builders = {
      'tags': (row) {
        final tagsData = row.cells['tags']?.value;
        if (tagsData == null) return const SizedBox.shrink();
        List<dynamic> tagsList;
        if (tagsData is String) {
          try {
            tagsList = json.decode(tagsData) as List<dynamic>;
          } catch (_) {
            tagsList = [];
          }
        } else if (tagsData is List<dynamic>) {
          tagsList = tagsData;
        } else {
          tagsList = [];
        }
        if (tagsList.isEmpty) return const SizedBox.shrink();

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: tagsList.map<Widget>((tag) {
              if (tag is! Map<String, dynamic>) return const SizedBox.shrink();
              final name = tag['name']?.toString() ?? '';
              if (name.isEmpty) return const SizedBox.shrink();
              String colorHex = tag['color']?.toString() ?? 'D1CFD7';
              if (colorHex.startsWith('#')) colorHex = colorHex.substring(1);
              Color bgColor;
              try {
                bgColor = Color(int.parse('FF$colorHex', radix: 16));
              } catch (_) {
                bgColor = Colors.grey;
              }
              final isDark = bgColor.computeLuminance() < 0.5;
              return Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '#$name',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
      'preview_photo': (row) {
        final url = row.cells['preview_photo']?.value as String?;
        return ImagePreviewCell(imageUrl: url, width: 80);
      },
      'ready_to_ship': (row) {
        final nmId = row.cells['wb_article']?.value as int;
        final entry = _batchData[nmId];
        return BatchDetailsCell(nmId: nmId, entry: entry);
      },
      'demand': (row) {
        final value = row.cells['demand']?.value;
        final displayValue = (value is num) ? (value == 0 ? '' : value.toString()) : '';
        if (displayValue.isEmpty) return const SizedBox.shrink();

        final nmId = row.cells['wb_article']?.value as int;
        final ordersPerDay = (row.cells['orders_per_day']?.value as num?)?.toDouble() ?? 0;
        final stock = (row.cells['stock']?.value as num?)?.toDouble() ?? 0;
        final cancellations = (row.cells['cancellations']?.value as num?)?.toDouble() ?? 0;
        final returns = (row.cells['returns']?.value as num?)?.toDouble() ?? 0;
        final inTransit = (row.cells['in_transit']?.value as num?)?.toDouble() ?? 0;
        final supplyPeriod = _supplyPeriodDays.toDouble();

        double stockDays = 0;
        if (ordersPerDay > 0) {
          stockDays = (stock + cancellations + returns + inTransit) / ordersPerDay;
        }
        double toSupply = 0;
        if (ordersPerDay > 0) {
          final deficitDays = supplyPeriod - stockDays;
          if (deficitDays > 0) {
            toSupply = deficitDays * ordersPerDay;
          }
        }

        final formulaText = '(Период поставки - На сколько хватит остатков) × Заказов в день';
        final valuesText = '($supplyPeriod - ${stockDays.toStringAsFixed(2)}) × ${ordersPerDay.toStringAsFixed(2)}';
        final resultText = '= ${toSupply.toStringAsFixed(2)}';

        return Tooltip(
          message: '$formulaText\n$valuesText\n$resultText',
          preferBelow: false,
          child: Center(
            child: Text(
              displayValue,
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
      'stock': (row) => numericCellBuilder(row, 'stock'),
      'orders': (row) => numericCellBuilder(row, 'orders'),
      'orders_per_day': (row) => numericCellBuilder(row, 'orders_per_day'),
      'cancellations': (row) => numericCellBuilder(row, 'cancellations'),
      'returns': (row) => numericCellBuilder(row, 'returns'),
      'sales': (row) => numericCellBuilder(row, 'sales'),
      'stock_days': (row) => _buildStockDaysCell(row),
      'in_transit': (row) {
        final nmId = row.cells['wb_article']?.value as int;
        final total = _currentInTransitMap[nmId] ?? 0;
        final details = _currentInTransitDetails[nmId] ?? [];
        return InTransitCell(
          nmId: nmId,
          totalQuantity: total,
          details: details,
        );
      },
      'to_supply': (row) {
        final nmId = row.cells['wb_article']?.value as int;
        final maxReady = _batchTotalMap[nmId] ?? 0;
        final autoValue = _getCappedToSupply(nmId);
        final manualValue = _manualToSupply[nmId];
        final rawValue = manualValue ?? autoValue;
        final initialCapped = rawValue > maxReady ? maxReady : rawValue;

        return EditableToSupplyCell(
          nmId: nmId,
          initialValue: initialCapped,
          maxValue: maxReady,
          onChanged: (newValue) {
            setState(() {
              if (newValue == null) {
                _manualToSupply.remove(nmId);
              } else {
                _manualToSupply[nmId] = newValue;
              }
            });
            final newDisplay = newValue ?? _getCappedToSupply(nmId);
            _tableKey.currentState?.updateCell(nmId, 'to_supply', newDisplay);
          },
        );
      },
      'check_status': (row) {
        final nmId = row.cells['wb_article']?.value as int;
        final status = _checkStatus[nmId] ?? '';
        if (status.isEmpty) return const SizedBox.shrink();
        final isAllowed = status == 'Разрешено';
        return Tooltip(
          message: isAllowed ? 'Разрешено' : 'Недоступно',
          child: Container(
            alignment: Alignment.center,
            child: Icon(
              isAllowed ? Icons.check_circle : Icons.cancel,
              color: isAllowed ? Colors.green : Colors.red,
              size: 24,
            ),
          ),
        );
      },
      'margin': (row) => numericCellBuilder(row, 'margin'),
      'dynamic_prices': (row) {
        final nmId = row.cells['wb_article']?.value as int;
        return FutureBuilder<List<int>>(
          future: _getPriceHistoryFuture(nmId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
            }
            if (!snapshot.hasData) return const SizedBox.shrink();

            List<int> history = snapshot.data!;
            final currentPrice = _currentPrices[nmId];
            if (currentPrice != null && currentPrice > 0 && history.isNotEmpty) {
              history = List.from(history);
              history[history.length - 1] = currentPrice;
            }

            final values = history.map((e) => e.toDouble()).toList();
            final dates = _getLastNDates(21);
            final labels = dates.map((d) => DateFormat('dd.MM').format(d)).toList();

            if (values.every((v) => v == 0)) return const SizedBox.shrink();

            return SimpleBarChart(
              values: values,
              labels: labels,
              dates: dates,
              barCount: 21,
              barWidth: 4,
              maxHeight: 40,
              barColor: Colors.blue,
            );
          },
        );
      },
      'dynamic_queries': (row) {
        final nmId = row.cells['wb_article']?.value as int;
        return FutureBuilder<List<int>>(
          future: _getSearchFrequenciesCached(nmId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
            }
            if (!snapshot.hasData) return const SizedBox.shrink();
            final values = snapshot.data!.map((e) => e.toDouble()).toList();
            final dates = _getLastNDates(21);
            final labels = dates.map((d) => DateFormat('dd.MM').format(d)).toList();
            if (values.every((v) => v == 0)) return const SizedBox.shrink();
            return SimpleBarChart(
              values: values,
              labels: labels,
              dates: dates,
              barCount: 21,
              barWidth: 4,
              maxHeight: 40,
              barColor: Colors.blue,
              onBarTap: (index) => _showQueriesDialog(nmId, dates[index]),
            );
          },
        );
      },
      'dynamic_stocks': (row) {
        final nmId = row.cells['wb_article']?.value as int;
        return FutureBuilder<List<int>>(
          future: _getStockTimeSeriesCached(nmId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
            }
            if (!snapshot.hasData) return const SizedBox.shrink();
            final values = snapshot.data!.map((e) => e.toDouble()).toList();
            final dates = _getLastNDates(21);
            final labels = dates.map((d) => DateFormat('dd.MM').format(d)).toList();
            if (values.every((v) => v == 0)) return const SizedBox.shrink();
            return SimpleBarChart(
              values: values,
              labels: labels,
              dates: dates,
              barCount: 21,
              barWidth: 4,
              maxHeight: 40,
              barColor: Colors.blue,
            );
          },
        );
      },
      'dynamic_orders': (row) {
        final nmId = row.cells['wb_article']?.value as int;
        return FutureBuilder<List<int>>(
          future: _getOrdersTimeSeriesCached(nmId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
            }
            if (!snapshot.hasData) return const SizedBox.shrink();
            final values = snapshot.data!.map((e) => e.toDouble()).toList();
            final dates = _getLastNDates(21);
            final labels = dates.map((d) => DateFormat('dd.MM').format(d)).toList();
            if (values.every((v) => v == 0)) return const SizedBox.shrink();
            return SimpleBarChart(
              values: values,
              labels: labels,
              dates: dates,
              barCount: 21,
              barWidth: 4,
              maxHeight: 40,
              barColor: Colors.blue,
              onBarTap: (index) => _showOrdersDialog(nmId, dates[index]),
            );
          },
        );
      },
      'dynamic_transitions': (row) {
        final nmId = row.cells['wb_article']?.value as int;
        return FutureBuilder<List<double>>(
          future: _getTransitionsCached(nmId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
            }
            if (!snapshot.hasData) return const SizedBox.shrink();
            final values = snapshot.data!;
            final dates = _getLastNDates(21);
            final labels = dates.map((d) => DateFormat('dd.MM').format(d)).toList();
            if (values.every((v) => v == 0)) return const SizedBox.shrink();
            return SimpleBarChart(
              values: values,
              labels: labels,
              dates: dates,
              barCount: 21,
              barWidth: 4,
              maxHeight: 40,
              barColor: Colors.blue,
            );
          },
        );
      },
      'abc': (row) => const AbcPlaceholderWidget(),
    };

    return builders;
  }

  void _showOrdersDialog(int nmId, DateTime tappedDate) async {
    final count = _currentOrdersTimeSeriesMap[nmId]?[tappedDate] ?? 0;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Заказы за ${DateFormat('dd MMMM yyyy', 'ru').format(tappedDate)}'),
        content: Text('Количество заказов: $count'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  int _getAutoToSupplyForNmId(int nmId) {
    final ordersTotal = _currentOrdersMap[nmId] ?? 0;
    if (ordersTotal == 0) return 0;
    if (_currentDaysRange == 0) return 0;

    final ordersPerDay = ordersTotal / _currentDaysRange;

    final stock = _currentStockMap[nmId] ?? 0;
    final cancellations = _currentCancellationsMap[nmId] ?? 0;
    final returns = _currentReturnsMap[nmId] ?? 0;
    final inTransit = _currentInTransitMap[nmId] ?? 0;

    final stockDays = (stock + cancellations + returns + inTransit) / ordersPerDay;
    final deficitDays = _supplyPeriodDays - stockDays;
    if (deficitDays <= 0) return 0;

    final rawToSupply = deficitDays * ordersPerDay;
    return rawToSupply.round();
  }

  void _showQueriesDialog(int nmId, DateTime tappedDate) async {
    final queries = await _searchQueryService.getSearchTextsForDay(nmId, tappedDate);
    if (queries == null || queries.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Запросы за ${DateFormat('dd MMMM yyyy', 'ru').format(tappedDate)}'),
          content: const Text('Нет данных по поисковым запросам.'),
        ),
      );
      return;
    }
    final sortedEntries = queries.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Ключевые запросы\n${DateFormat('dd MMMM yyyy', 'ru').format(tappedDate)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: sortedEntries.map((entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(child: Text(entry.key, style: const TextStyle(fontSize: 13))),
                          const SizedBox(width: 8),
                          Text(entry.value.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _buildRowMap(Product product) {
    final photos = product.getPhotoUrls();
    final previewUrl = photos.isNotEmpty ? photos.first : null;

    final nmId = product.nmID;
    final stock = _currentStockMap[nmId] ?? 0;
    final orders = _currentOrdersMap[nmId] ?? 0;
    final ordersPerDay = _currentDaysRange > 0 ? orders / _currentDaysRange : 0.0;
    final cancellations = _currentCancellationsMap[nmId] ?? 0;
    final returns = _currentReturnsMap[nmId] ?? 0;
    final sales = _currentSalesMap[nmId] ?? 0;

    final inTransit = _currentInTransitMap[nmId] ?? 0;
    final stockDays = ordersPerDay > 0
        ? (stock + cancellations + returns + inTransit) / ordersPerDay
        : 0.0;

    double toSupply = 0.0;
    if (ordersPerDay > 0) {
      final deficitDays = _supplyPeriodDays - stockDays;
      if (deficitDays > 0) {
        toSupply = deficitDays * ordersPerDay;
      }
    }

    return {
      'supplier_article': product.vendorCode,
      'wb_article': nmId,
      'name': product.title,
      'subject': product.subjectName,
      'tags': product.tags,
      'preview_photo': previewUrl,
      'barcode': _barcodeMap[nmId] ?? '',
      'stock': stock,
      'orders': orders,
      'orders_per_day': ordersPerDay,
      'cancellations': cancellations,
      'returns': returns,
      'sales': sales,
      'stock_days': stockDays,
      'in_transit': _currentInTransitMap[nmId] ?? 0,
      'ready_to_ship': _batchTotalMap[nmId] ?? 0,
      'to_supply': _getCappedToSupply(nmId),
      'check_status': _checkStatus[product.nmID] ?? '',
      'dynamic_prices': null,
      'dynamic_orders': null,
      'dynamic_stocks': null,
      'dynamic_queries': null,
      'dynamic_transitions': null,
      'abc': null,
      'margin': 0,
      'demand': _getAutoToSupplyForNmId(nmId),
    };
  }

  Widget _buildStockDaysCell(PlutoRow row) {
    final stock = (row.cells['stock']?.value as num?)?.toDouble() ?? 0;
    final ordersPerDay = (row.cells['orders_per_day']?.value as num?)?.toDouble() ?? 0;
    final cancellations = (row.cells['cancellations']?.value as num?)?.toDouble() ?? 0;
    final returns = (row.cells['returns']?.value as num?)?.toDouble() ?? 0;
    final inTransit = (row.cells['in_transit']?.value as num?)?.toDouble() ?? 0;

    double stockDays = 0;
    bool formulaValid = ordersPerDay > 0;

    if (formulaValid) {
      stockDays = (stock + cancellations + returns + inTransit) / ordersPerDay;
    }

    final formulaText = '(Остаток + Отмены + Возвраты + В пути) / Заказов в день';
    final valuesText = '($stock + $cancellations + $returns + $inTransit) / $ordersPerDay';
    final resultText = formulaValid ? '= ${stockDays.toStringAsFixed(2)}' : '= 0 (недостаточно данных)';

    final tooltipMessage = '$formulaText\n$valuesText\n$resultText';

    final displayValue = stockDays == 0 ? '' : stockDays.toStringAsFixed(2);

    return Tooltip(
      message: tooltipMessage,
      preferBelow: false,
      child: Center(
        child: Text(
          displayValue,
          style: const TextStyle(fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildToSupplyCell(PlutoRow row) {
    final ordersPerDay = (row.cells['orders_per_day']?.value as num?)?.toDouble() ?? 0;
    final stock = (row.cells['stock']?.value as num?)?.toDouble() ?? 0;
    final cancellations = (row.cells['cancellations']?.value as num?)?.toDouble() ?? 0;
    final returns = (row.cells['returns']?.value as num?)?.toDouble() ?? 0;
    final supplyPeriod = _supplyPeriodDays.toDouble();

    double stockDays = 0;
    if (ordersPerDay > 0) {
      stockDays = (stock + cancellations + returns) / ordersPerDay;
    }

    double toSupply = 0;
    if (ordersPerDay > 0) {
      final deficitDays = supplyPeriod - stockDays;
      if (deficitDays > 0) {
        toSupply = deficitDays * ordersPerDay;
      }
    }

    final displayValue = toSupply == 0 ? '' : toSupply.toStringAsFixed(2);

    final formulaText = '(Период поставки - На сколько хватит остатков) × Заказов в день';
    final valuesText = '($supplyPeriod - ${stockDays.toStringAsFixed(2)}) × ${ordersPerDay.toStringAsFixed(2)}';
    final resultText = '= ${toSupply.toStringAsFixed(2)}';

    return Tooltip(
      message: '$formulaText\n$valuesText\n$resultText',
      preferBelow: false,
      child: Center(
        child: Text(
          displayValue,
          style: const TextStyle(fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Future<void> _exportToExcel() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      final stockMap = _currentStockMap;
      final ordersMap = _currentOrdersMap;
      final cancellationsMap = _currentCancellationsMap;
      final returnsMap = _currentReturnsMap;
      final barcodeMap = _barcodeMap;
      final daysRange = _currentDaysRange;

      final allNmIds = <int>{};
      allNmIds.addAll(stockMap.keys);
      allNmIds.addAll(ordersMap.keys);
      allNmIds.addAll(cancellationsMap.keys);
      allNmIds.addAll(returnsMap.keys);
      final nmIdList = allNmIds.toList()..sort();

      if (nmIdList.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нет данных для экспорта'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      var excel = Excel.createExcel();
      var sheet = excel['Sheet1'];

      final headers = [
        'Баркод',
        'Количество',
        'Склад',
        'Артикул поставщика',
        'Артикул WB',
        'Наименование',
        'Предмет',
        'Тэги',
        'Остаток',
        'Заказов',
        'Заказов в день',
        'Отмены',
        'Возвраты',
        'На сколько дней хватит',
        'В пути',
      ];

      for (int i = 0; i < headers.length; i++) {
        var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = headers[i];
        if (i == 0 || i == 1) {
          cell.cellStyle = CellStyle(
            bold: true,
            backgroundColorHex: 'FF90EE90',
          );
        }
      }

      final productManager = ProductManager();
      if (!productManager.isInitialized) await productManager.initialize();

      int rowIndex = 1;
      for (final nmId in nmIdList) {
        Product? product;
        for (final p in productManager.allProducts) {
          if (p.nmID == nmId) {
            product = p;
            break;
          }
        }
        final title = product?.title ?? '';
        final subject = product?.subjectName ?? '';
        String tagsString = '';
        final tagsRaw = product?.tags;
        if (tagsRaw is List<dynamic>) {
          final tagNames = tagsRaw.map((tag) {
            if (tag is Map<String, dynamic>) return tag['name']?.toString() ?? '';
            return tag.toString();
          }).where((n) => n.isNotEmpty).toList();
          tagsString = tagNames.join(', ');
        }

        final barcode = barcodeMap[nmId] ?? '';
        final stock = stockMap[nmId] ?? 0;
        final orders = ordersMap[nmId] ?? 0;
        final ordersPerDay = daysRange > 0 ? orders / daysRange : 0.0;
        final cancellations = cancellationsMap[nmId] ?? 0;
        final returns = returnsMap[nmId] ?? 0;

        final inTransit = _currentInTransitMap[nmId] ?? 0;

        double stockDays = 0;
        if (ordersPerDay > 0) {
          stockDays = (stock + cancellations + returns + inTransit) / ordersPerDay;
        }

        double autoToSupply = 0;
        if (ordersPerDay > 0) {
          final deficitDays = _supplyPeriodDays - stockDays;
          if (deficitDays > 0) {
            autoToSupply = deficitDays * ordersPerDay;
          }
        }

        final int finalToSupply = _getCappedToSupply(nmId, _manualToSupply[nmId]);
        if (finalToSupply <= 0) continue;

        final rowData = [
          barcode,
          finalToSupply,
          _selectedWarehouse?.name ?? 'Сумма',
          product?.vendorCode ?? '',
          nmId.toString(),
          title,
          subject,
          tagsString,
          stock,
          orders,
          ordersPerDay.toStringAsFixed(2),
          cancellations,
          returns,
          stockDays >= 9999 ? '∞' : stockDays.toStringAsFixed(1),
          _currentInTransitMap[nmId] ?? 0,
        ];

        for (int col = 0; col < rowData.length; col++) {
          var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex));
          cell.value = rowData[col];
          if (col == 0 || col == 1) {
            cell.cellStyle = CellStyle(
              backgroundColorHex: 'FF90EE90',
            );
          }
        }
        rowIndex++;
      }

      final bytes = excel.save();
      if (bytes == null) throw Exception('Ошибка сохранения Excel');

      final now = DateTime.now();
      final warehouseName = _selectedWarehouse?.name ?? 'Все';
      final fileName = 'Поставка_${warehouseName}_${DateFormat('dd.MM.yyyy').format(now)}_${DateFormat('HH.mm').format(now)}.xlsx';

      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить файл Excel',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsBytes(bytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Файл сохранён: ${path.basename(result)}'),
              backgroundColor: Colors.green,
            ),
          );
          await OpenFile.open(result);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _runCheck() async {
    if (_isChecking) return;
    if (_selectedWarehouse == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите склад для проверки'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (_selectedWarehouse!.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID склада не найден'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isChecking = true);
    _checkStatus.clear();
    _refreshProviderData();

    final token = await TokenManager().getToken();
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет токена авторизации'), backgroundColor: Colors.red),
      );
      setState(() => _isChecking = false);
      return;
    }

    final itemsToCheck = <Map<String, dynamic>>[];
    for (final nmId in {..._currentOrdersMap.keys, ..._currentStockMap.keys}) {
      final manual = _manualToSupply[nmId];
      final toSupply = _getCappedToSupply(nmId, manual);
      if (toSupply > 0) {
        final barcode = _barcodeMap[nmId];
        if (barcode != null && barcode.isNotEmpty) {
          itemsToCheck.add({
            "quantity": toSupply.clamp(1, 999999),
            "barcode": barcode,
          });
          _tempNmIdForBarcode[barcode] = nmId;
        }
      }
    }

    if (itemsToCheck.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет товаров с количеством к поставке > 0'), backgroundColor: Colors.orange),
      );
      setState(() => _isChecking = false);
      return;
    }

    final warehouseID = _selectedWarehouse!.id;
    final url = Uri.parse('https://supplies-api.wildberries.ru/api/v1/acceptance/options?warehouseID=$warehouseID');

    try {
      final requestBody = json.encode(itemsToCheck);
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: requestBody,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> resultList = data['result'] ?? [];

        for (var itemResult in resultList) {
          final barcode = itemResult['barcode'] as String?;
          final nmId = _tempNmIdForBarcode[barcode];
          if (barcode == null || nmId == null) continue;

          if (itemResult['isError'] == true) {
            final error = itemResult['error'];
            final title = error?['title'] ?? 'Ошибка';
            final detail = error?['detail'] ?? '';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$title: $detail'), backgroundColor: Colors.red, duration: const Duration(seconds: 3)),
            );
          } else {
            final warehouses = itemResult['warehouses'] as List<dynamic>?;
            if (warehouses != null) {
              final wh = warehouses.firstWhere(
                    (w) => w['warehouseID'] == warehouseID,
                orElse: () => null,
              );
              final status = (wh != null && wh['canBox'] == true) ? 'Разрешено' : 'Недоступно';
              _checkStatus[nmId] = status;
              _tableKey.currentState?.updateCell(nmId, 'check_status', status);
            } else {
              _checkStatus[nmId] = 'Недоступно';
              _tableKey.currentState?.updateCell(nmId, 'check_status', 'Недоступно');
            }
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка HTTP ${response.statusCode}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка проверки: $e'), backgroundColor: Colors.red),
      );
    }

    _tempNmIdForBarcode.clear();
    setState(() => _isChecking = false);
  }

  Widget _buildWarehouseDropdown() {
    if (_isLoadingWarehouses) {
      return Container(
        height: 40,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_warehousesError != null) {
      return Container(
        height: 40,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red[300]!),
          borderRadius: BorderRadius.circular(8),
          color: Colors.red[50],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _warehousesError!,
                style: const TextStyle(fontSize: 12, color: Colors.red),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: _retryLoadWarehouses,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              color: Colors.red,
            ),
          ],
        ),
      );
    }

    if (_warehouses.isEmpty) {
      return Container(
        height: 40,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: const Center(
          child: Text('Нет доступных складов', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButton<Warehouse?>(
        value: _selectedWarehouse,
        hint: const Text('Выберите склад'),
        isExpanded: true,
        underline: const SizedBox(),
        icon: const Icon(Icons.arrow_drop_down),
        items: [
          DropdownMenuItem<Warehouse?>(
            value: null,
            child: _buildWarehouseItem(null),
          ),
          ..._warehouses.map((warehouse) {
            return DropdownMenuItem<Warehouse?>(
              value: warehouse,
              child: _buildWarehouseItem(warehouse),
            );
          }).toList(),
        ],
        onChanged: (Warehouse? newValue) {
          setState(() {
            _selectedWarehouse = newValue;
            _manualToSupply.clear();
          });
          _buildDataMapsForSelectedWarehouse();
          _updateCurrentInTransitData();
        },
      ),
    );
  }

  void _showBatchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Загрузка партии'),
        content: const Text('Выберите действие:'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadTemplate();
            },
            child: const Text('Скачать шаблон'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _uploadBatch();
            },
            child: const Text('Загрузить партию'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadTemplate() async {
    var excel = Excel.createExcel();
    var sheet = excel['Sheet1'];

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = 'Артикул WB или Продавца';
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = 'Количество в коробе';
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0)).value = 'Количество коробов';

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = '12345678';
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value = 10;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1)).value = 5;

    final bytes = excel.save();
    if (bytes == null) return;

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить шаблон',
      fileName: 'template_upload_batch.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result != null) {
      final file = File(result);
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Шаблон сохранён'), backgroundColor: Colors.green),
        );
        await OpenFile.open(result);
      }
    }
  }

  Future<void> _uploadBatch() async {
    debugPrint('=== _uploadBatch started ===');

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );

    if (result == null) {
      debugPrint('❌ Пользователь отменил выбор файла');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Выбор файла отменён'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    final bytes = result.files.first.bytes;
    if (bytes == null) {
      debugPrint('❌ Файл пуст или не удалось прочитать байты');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось прочитать файл'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    debugPrint('✅ Файл загружен, размер: ${bytes.length} байт');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Обработка файла...'), duration: Duration(seconds: 2)),
      );
    }

    try {
      var excel = Excel.decodeBytes(bytes);
      var sheet = excel.tables['Sheet1'];
      if (sheet == null) {
        debugPrint('❌ Лист "Sheet1" не найден в файле');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Файл не содержит лист "Sheet1"'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      debugPrint('✅ Лист найден, строк: ${sheet.rows.length}');

      final productManager = ProductManager();
      if (!productManager.isInitialized) {
        debugPrint('⏳ Инициализация ProductManager...');
        await productManager.initialize();
      }
      debugPrint('✅ ProductManager инициализирован, товаров: ${productManager.allProducts.length}');

      final Map<int, BatchEntry> newBatchData = {};
      int processedRows = 0;
      int skippedRows = 0;

      for (int rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
        final row = sheet.rows[rowIndex];
        if (row.length < 3) {
          skippedRows++;
          continue;
        }

        var articleCell = row[0];
        String? articleStr;
        if (articleCell?.value != null) {
          articleStr = articleCell!.value.toString().trim();
        }
        if (articleStr == null || articleStr.isEmpty) {
          skippedRows++;
          continue;
        }

        var qtyInBoxCell = row[1];
        int qtyInBox = 0;
        if (qtyInBoxCell?.value != null) {
          final val = qtyInBoxCell!.value;
          if (val is int) qtyInBox = val;
          else if (val is double) qtyInBox = val.toInt();
          else if (val is String) qtyInBox = int.tryParse(val) ?? 0;
        }

        var boxesCountCell = row[2];
        int boxesCount = 0;
        if (boxesCountCell?.value != null) {
          final val = boxesCountCell!.value;
          if (val is int) boxesCount = val;
          else if (val is double) boxesCount = val.toInt();
          else if (val is String) boxesCount = int.tryParse(val) ?? 0;
        }

        if (qtyInBox <= 0 || boxesCount <= 0) {
          skippedRows++;
          continue;
        }

        processedRows++;

        int? nmId;

        final int? maybeNmId = int.tryParse(articleStr);
        if (maybeNmId != null) {
          for (final p in productManager.allProducts) {
            if (p.nmID == maybeNmId) {
              nmId = maybeNmId;
              break;
            }
          }
        }

        if (nmId == null) {
          for (final p in productManager.allProducts) {
            if (p.vendorCode == articleStr) {
              nmId = p.nmID;
              break;
            }
          }
        }

        if (nmId != null) {
          final detail = BatchDetail(boxesCount: boxesCount, qtyInBox: qtyInBox);
          newBatchData.putIfAbsent(nmId, () => BatchEntry()).addDetail(detail);
          debugPrint('   ✅ Строка $rowIndex: "$articleStr" → nmId=$nmId, +${detail.total} (всего ${newBatchData[nmId]!.total})');
        } else {
          debugPrint('   ❌ Строка $rowIndex: артикул "$articleStr" не найден');
        }
      }

      debugPrint('Итог: обработано строк $processedRows, пропущено $skippedRows, загружено позиций ${newBatchData.length}');

      setState(() {
        _batchData = newBatchData;
      });

      bool needRefresh = false;
      final toRemove = <int>[];
      final batchTotalMap = _batchTotalMap;
      for (final entry in _manualToSupply.entries) {
        final nmId = entry.key;
        final manualVal = entry.value;
        final maxReady = batchTotalMap[nmId] ?? 0;
        if (maxReady == 0) {
          toRemove.add(nmId);
          _tableKey.currentState?.updateCell(nmId, 'to_supply', 0);
          needRefresh = true;
        } else if (manualVal > maxReady) {
          _manualToSupply[nmId] = maxReady;
          _tableKey.currentState?.updateCell(nmId, 'to_supply', maxReady);
          needRefresh = true;
        }
      }
      for (var nmId in toRemove) {
        _manualToSupply.remove(nmId);
      }
      if (needRefresh) {
        _refreshProviderData();
      }
      _refreshProviderData();
      _tableController.refreshData();

      String message;
      Color backgroundColor;
      if (newBatchData.isEmpty) {
        message = 'Не найдено товаров. Обработано строк: $processedRows (пропущено $skippedRows). Проверьте артикулы в файле.';
        backgroundColor = Colors.orange;
      } else {
        message = 'Загружено ${newBatchData.length} позиций. Обработано строк: $processedRows, пропущено $skippedRows.';
        backgroundColor = Colors.green;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: backgroundColor, duration: const Duration(seconds: 5)),
        );
        if (newBatchData.isEmpty) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Ничего не загружено'),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e, stack) {
      debugPrint('❌ Ошибка парсинга XLSX: $e');
      debugPrint(stack.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 6)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 60,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(
                          _selectedDateRange != null
                              ? '${_formatDate(_selectedDateRange!.start)} – ${_formatDate(_selectedDateRange!.end)}'
                              : 'Выберите даты',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: InkWell(
                          onTap: () => _selectDateRange(context),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                          child: const Center(
                            child: Icon(Icons.calendar_today, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 600,
                  child: _buildWarehouseDropdown(),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.filter_alt_off, size: 28),
                  onPressed: () => _tableController.clearFilters(),
                  tooltip: 'Сбросить все фильтры',
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 150,
                  height: 40,
                  child: TextField(
                    controller: _supplyPeriodController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      labelText: 'Период поставки',
                      labelStyle: const TextStyle(fontSize: 10, color: Colors.grey),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () {
                              int val = int.tryParse(_supplyPeriodController.text) ?? 30;
                              if (val > 1) {
                                val--;
                                _supplyPeriodController.text = val.toString();
                                _supplyPeriodController.selection = TextSelection.fromPosition(
                                  TextPosition(offset: _supplyPeriodController.text.length),
                                );
                                _onSupplyPeriodTextChanged();
                              }
                            },
                            child: const Icon(Icons.remove, size: 16),
                          ),
                          InkWell(
                            onTap: () {
                              int val = int.tryParse(_supplyPeriodController.text) ?? 30;
                              val++;
                              _supplyPeriodController.text = val.toString();
                              _supplyPeriodController.selection = TextSelection.fromPosition(
                                TextPosition(offset: _supplyPeriodController.text.length),
                              );
                              _onSupplyPeriodTextChanged();
                            },
                            child: const Icon(Icons.add, size: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                InkWell(
                  onTap: _isExporting ? null : _exportToExcel,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Image.asset(
                      'assets/icons/excel.png',
                      width: 28,
                      height: 28,
                      errorBuilder: (_, __, ___) => const Icon(Icons.file_download, size: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.search, size: 28),
                      onPressed: _isChecking ? null : _runCheck,
                      tooltip: 'Проверить доступность коробов',
                    ),
                    if (_isChecking)
                      const Positioned(
                        right: 0,
                        top: 0,
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Tooltip(
                  message: 'Загрузить партию',
                  child: InkWell(
                    onTap: _showBatchDialog,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: Icon(Icons.upload_file, size: 28, color: Colors.blue),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                InkWell(
                  onTap: () {
                    if (_supplyDates.isEmpty && !_isCalendarLoading) {
                      _loadSuppliesCalendar().then((_) => _showSuppliesCalendar());
                    } else {
                      _showSuppliesCalendar();
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Icon(
                      Icons.local_shipping,
                      size: 28,
                      color: _isCalendarLoading ? Colors.grey : Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                _buildLoadingStatusWidget(),
              ],
            ),
          ),
          Expanded(
            child: UniversalDataTable<Product>(
              key: _tableKey,
              controller: _tableController,
              screenId: 'supplies_new',
              provider: _provider,
              columns: _buildColumns(),
              customCellBuilders: _buildCustomCellBuilders(),
              toMap: _buildRowMap,
              toolbarBuilder: (context, controller) => const SizedBox.shrink(),
              headerFeatures: const HeaderFeaturesConfig(
                showStatistics: false,
                showMenu: true,
                showAggregation: false,
                showChart: false,
                showSort: true,
                showFilter: true,
                showDataTypeAndDivider: false,
                showTitleAndDivider: true,
                showSettingsButton: false,
                showAddCustomColumnButton: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}