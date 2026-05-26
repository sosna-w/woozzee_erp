import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:math';

import '../models/product.dart';
import '../utils/product_manager.dart';
import '../utils/price_manager.dart';
import '../utils/stocks_manager.dart';
import '../utils/price_history_manager.dart';
import '../models/promo_actions_model.dart';
import '../models/promotion_goods_info.dart';
import '../models/promotion_extension.dart';
import '../services/promotion_goods_loader.dart';
import '../services/search_query_service.dart';
import '../utils/sales_funnel_manager.dart';
import '../utils/token_manager.dart';
import '../utils/private_token_manager.dart';
import '../providers/product_data_provider.dart';
import '../widgets/prices/simple_bar_chart.dart';
import '../widgets/prices/image_preview_cell.dart';
import '../widgets/prices/editable_price_cell.dart';
import '../widgets/prices/fbo_stocks_chart.dart';
import 'universal_data_table.dart';

class PricesScreenNew extends StatefulWidget {
  const PricesScreenNew({super.key});

  @override
  State<PricesScreenNew> createState() => _PricesScreenNewState();
}

class _PricesScreenNewState extends State<PricesScreenNew> {
  final GlobalKey<UniversalDataTableState> _tableKey = GlobalKey<UniversalDataTableState>();
  late ProductDataProvider _provider;
  late List<ColumnDefinition> _columns;
  late Map<String, Widget Function(PlutoRow row)> _customBuilders;
  bool _isInitialized = false;
  final Map<int, int> _draftDiscounts = {};
  final Map<int, int> _draftPrices = {};
  final Map<int, int> _draftClubDiscounts = {};
  List<CustomColumn> _customColumns = [];
  late UniversalDataTableController _tableController;
  late final SalesFunnelManager _salesManager;
  final Map<int, Future<List<int>>> _discountHistoryFutures = {};
  final PriceHistoryManager _priceHistoryManager = PriceHistoryManager();
  final Map<int, Future<List<int>>> _searchFrequenciesFutures = {};
  late Future<void> _priceHistoryLoadFuture;
  late Future<void> _priceHistoryLoad2Future;
  late Future<void> _currentPriceHistoryFuture;

  late SearchQueryService _searchQueryService;

  final Map<int, Future<List<StocksHistoryData>>> _stocksHistoryFutures = {};

  List<dynamic> _boxTariffs = [];
  String? _selectedFBSWarehouse;
  String? _selectedFBOWarehouse;
  Map<String, dynamic>? _selectedFBSTariff;
  Map<String, dynamic>? _selectedFBOTariff;
  double _localizationIndex = 1.00;
  late TextEditingController _localizationIndexController;
  List<String>? _cachedUniqueWarehouseNames;

  List<Promotion> _promotions = [];
  bool _isLoadingPromotions = false;
  String? _wbApiToken;
  late PromotionGoodsLoader _goodsLoader;
  final Map<int, bool> _promotionGoodsLoaded = {};

  final StocksManager _stocksManager = StocksManager();

  @override
  void initState() {
    super.initState();
    _salesManager = SalesFunnelManager();
    _tableController = UniversalDataTableController();
    _provider = ProductDataProvider();
    _searchQueryService = SearchQueryService();
    _initColumnsAndBuilders();
    _localizationIndexController = TextEditingController(text: _localizationIndex.toStringAsFixed(2));
    _initializeData();
  }

  Future<List<int>> _getDiscountHistoryFuture(int nmId) {
    if (!_discountHistoryFutures.containsKey(nmId)) {
      _discountHistoryFutures[nmId] = Future(() => _provider.getDiscountHistory(nmId, 21));
    }
    return _discountHistoryFutures[nmId]!;
  }

  void _updateDraftDiscount(int nmID, int newDiscount) {
    setState(() {
      _draftDiscounts[nmID] = newDiscount;
      _provider.updateDrafts(discounts: {nmID: newDiscount});
    });
    _refreshCustomColumns();
  }

  void _updateDraftPrice(int nmID, int newPrice) {
    setState(() {
      _draftPrices[nmID] = newPrice;
      _provider.updateDrafts(prices: {nmID: newPrice});
    });
    _refreshCustomColumns();
  }

  void _updateDraftClubDiscount(int nmID, int newClubDiscount) {
    setState(() {
      _draftClubDiscounts[nmID] = newClubDiscount;
      _provider.updateDrafts(clubDiscounts: {nmID: newClubDiscount});
    });
    _refreshCustomColumns();
  }

  void _syncLogisticsParamsToProvider() {
    _provider.updateLogisticsParams(
      localizationIndex: _localizationIndex,
      fbsTariff: _selectedFBSTariff,
      fboTariff: _selectedFBOTariff,
    );
    _refreshCustomColumns();
  }

  void _refreshCustomColumns() {
    _tableKey.currentState?.refreshCustomColumns();
  }

  void _clearSearchFrequenciesCache() {
    _searchFrequenciesFutures.clear();
  }

  Future<void> _loadSearchHistory() async {
    final localDates = await _searchQueryService.getLocalDates();
    final forceReload = localDates.isEmpty;
    await _searchQueryService.loadHistory(forceReload: forceReload);
    _clearSearchFrequenciesCache();
    print('✅ История поисковых запросов синхронизирована');
  }

  Future<void> _loadCurrentSearchData() async {
    await _searchQueryService.loadCurrentData();
    _clearSearchFrequenciesCache();
    print('✅ Текущие запросы загружены через сервис');
  }

  Future<List<int>> _getSearchFrequenciesCached(int nmId) {
    if (!_searchFrequenciesFutures.containsKey(nmId)) {
      _searchFrequenciesFutures[nmId] = _searchQueryService.getTotalFrequenciesForLastNDays(nmId, 21);
    }
    return _searchFrequenciesFutures[nmId]!;
  }

  void _initColumnsAndBuilders() {
    _columns = [
      ColumnDefinition(field: 'nmID', title: 'Артикул WB', dataType: ColumnDataType.number, width: 120),
      ColumnDefinition(field: 'vendorCode', title: 'Артикул продавца', dataType: ColumnDataType.text, width: 150),
      ColumnDefinition(field: 'title', title: 'Наименование', dataType: ColumnDataType.text, width: 300),
      ColumnDefinition(field: 'subjectName', title: 'Продукт', dataType: ColumnDataType.text, width: 150),
      ColumnDefinition(field: 'volume', title: 'Объем, л', dataType: ColumnDataType.text, width: 100),
      ColumnDefinition(field: 'tags', title: 'Тэги', dataType: ColumnDataType.text, width: 200),
      ColumnDefinition(
        field: 'preview',
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
      ColumnDefinition(field: 'price', title: 'Цена', dataType: ColumnDataType.number, width: 100),
      ColumnDefinition(field: 'discount', title: 'Скидка, %', dataType: ColumnDataType.number, width: 100),
      ColumnDefinition(
        field: 'select',
        title: '',
        dataType: ColumnDataType.checkbox,
        width: 50,
        minWidth: 40,
        showStatistics: false,
        showAggregation: false,
        showChart: false,
        showSort: false,
        showFilter: false,
        showDataType: false,
      ),
      ColumnDefinition(field: 'clubDiscount', title: 'Скидка WB Клуба, %', dataType: ColumnDataType.number, width: 120),
      ColumnDefinition(field: 'discountedPrice', title: 'Цена со скидкой', dataType: ColumnDataType.number, width: 120),
      ColumnDefinition(field: 'clubDiscountedPrice', title: 'Цена со скидкой Клуба', dataType: ColumnDataType.number, width: 150),
      ColumnDefinition(field: 'customerPrice', title: 'Цена для покупателя', dataType: ColumnDataType.number, width: 120),
      ColumnDefinition(field: 'totalPromotions', title: 'Всего акций', dataType: ColumnDataType.number, width: 100),
      ColumnDefinition(field: 'activePromotions', title: 'Активных акций', dataType: ColumnDataType.number, width: 120),
      ColumnDefinition(field: 'participationPercent', title: 'Процент участия, %', dataType: ColumnDataType.number, width: 130),
      ColumnDefinition(field: 'fbs_quantity', title: 'Остатки FBS', dataType: ColumnDataType.number, width: 100),
      ColumnDefinition(field: 'total_quantity', title: 'Остатки FBO', dataType: ColumnDataType.number, width: 100),
      ColumnDefinition(field: 'fbsCommission', title: 'FBS, %', dataType: ColumnDataType.number, width: 80),
      ColumnDefinition(field: 'fboCommission', title: 'FBO, %', dataType: ColumnDataType.number, width: 80),
      ColumnDefinition(field: 'costPrice', title: 'Себестоимость', dataType: ColumnDataType.number, width: 120),
      ColumnDefinition(field: 'additionalExpenses', title: 'Доп. расходы', dataType: ColumnDataType.number, width: 120),
      ColumnDefinition(field: 'fbsLogistics', title: 'Логистика FBS', dataType: ColumnDataType.number, width: 120),
      ColumnDefinition(field: 'fboLogistics', title: 'Логистика FBO', dataType: ColumnDataType.number, width: 120),
      ColumnDefinition(field: 'priceChart', title: 'Динамика цены для покупателей', dataType: ColumnDataType.text, width: 120),
      ColumnDefinition(field: 'discountHistory', title: 'Динамика скидки', dataType: ColumnDataType.text, width: 120),
      ColumnDefinition(field: 'ordersChart', title: 'Динамика заказов', dataType: ColumnDataType.text, width: 120),
      ColumnDefinition(field: 'stocksFboChart', title: 'Динамика остатков FBO', dataType: ColumnDataType.text, width: 120),
      ColumnDefinition(field: 'queriesChart', title: 'Динамика запросов', dataType: ColumnDataType.text, width: 120),
      ColumnDefinition(field: 'viewsChart', title: 'Динамика переходов', dataType: ColumnDataType.text, width: 120),
    ];

    _customBuilders = {
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
      'discountHistory': (row) {
        final nmId = row.cells['nmID']?.value as int;
        return FutureBuilder<List<int>>(
          future: _getDiscountHistoryFuture(nmId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final values = snapshot.data!;
            if (values.every((v) => v == 0)) return const SizedBox.shrink();
            final dates = _provider.getLastNDates(21);
            final labels = dates.map((d) => DateFormat('dd.MM').format(d)).toList();
            return SimpleBarChart(
              values: values.map((v) => v.toDouble()).toList(),
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
      'customerPrice': (row) => Center(
        child: Text(row.cells['customerPrice']?.value?.toString() ?? '0'),
      ),
      'preview': (row) {
        final url = row.cells['preview']?.value as String?;
        return ImagePreviewCell(imageUrl: url, width: 80);
      },
      'price': (row) {
        final nmID = row.cells['nmID']?.value as int;
        final chrtID = row.cells['chrtID']?.value as int? ?? 0;
        final value = row.cells['price']?.value;
        return EditablePriceCell(
          nmID: nmID,
          chrtID: chrtID,
          field: 'price',
          initialValue: value,
          onChanged: (nmID, chrtID, newValue) {
            row.cells['price'] = PlutoCell(value: newValue);
          },
          onSend: () {
            _provider.removeDraft(nmID, price: true);
            setState(() {
              _draftPrices.remove(nmID);
            });
            _refreshCustomColumns();
          },
          onDraftChanged: (newPrice) => _updateDraftPrice(nmID, newPrice),
        );
      },
      'discount': (row) {
        final nmID = row.cells['nmID']?.value as int;
        final chrtID = row.cells['chrtID']?.value as int? ?? 0;
        final value = row.cells['discount']?.value;
        return EditablePriceCell(
          nmID: nmID,
          chrtID: chrtID,
          field: 'discount',
          initialValue: value,
          onChanged: (nmID, chrtID, newValue) {
            row.cells['discount'] = PlutoCell(value: newValue);
          },
          onSend: () {
            _provider.removeDraft(nmID, discount: true);
            setState(() {
              _draftDiscounts.remove(nmID);
            });
            _refreshCustomColumns();
          },
          onDraftChanged: (newDiscount) => _updateDraftDiscount(nmID, newDiscount),
        );
      },
      'clubDiscount': (row) {
        final nmID = row.cells['nmID']?.value as int;
        final chrtID = row.cells['chrtID']?.value as int? ?? 0;
        final value = row.cells['clubDiscount']?.value;
        return EditablePriceCell(
          nmID: nmID,
          chrtID: chrtID,
          field: 'clubDiscount',
          initialValue: value,
          onChanged: (nmID, chrtID, newValue) {
            row.cells['clubDiscount'] = PlutoCell(value: newValue);
          },
          onSend: () {
            _provider.removeDraft(nmID, clubDiscount: true);
            setState(() {
              _draftClubDiscounts.remove(nmID);
            });
            _refreshCustomColumns();
          },
          onDraftChanged: (newClubDiscount) => _updateDraftClubDiscount(nmID, newClubDiscount),
        );
      },
      'discountedPrice': (row) {
        final nmID = row.cells['nmID']?.value as int;
        final realPrice = (row.cells['price']?.value as num?)?.toDouble() ?? 0.0;
        final draftPrice = _draftPrices[nmID]?.toDouble();
        final effectivePrice = draftPrice ?? realPrice;
        final realDiscount = (row.cells['discount']?.value as num?)?.toDouble() ?? 0.0;
        final draftDiscount = _draftDiscounts[nmID]?.toDouble();
        final effectiveDiscount = draftDiscount ?? realDiscount;
        final discounted = effectivePrice - (effectivePrice * effectiveDiscount / 100);
        return Center(child: Text(discounted.toStringAsFixed(2)));
      },
      'clubDiscountedPrice': (row) {
        final nmID = row.cells['nmID']?.value as int;
        final realPrice = (row.cells['price']?.value as num?)?.toDouble() ?? 0.0;
        final draftPrice = _draftPrices[nmID]?.toDouble();
        final effectivePrice = draftPrice ?? realPrice;
        final realDiscount = (row.cells['discount']?.value as num?)?.toDouble() ?? 0.0;
        final draftDiscount = _draftDiscounts[nmID]?.toDouble();
        final effectiveDiscount = draftDiscount ?? realDiscount;
        final realClubDiscount = (row.cells['clubDiscount']?.value as num?)?.toDouble() ?? 0.0;
        final draftClubDiscount = _draftClubDiscounts[nmID]?.toDouble();
        final effectiveClubDiscount = draftClubDiscount ?? realClubDiscount;
        final discounted = effectivePrice - (effectivePrice * effectiveDiscount / 100);
        final clubDiscounted = discounted - (discounted * effectiveClubDiscount / 100);
        return Center(child: Text(clubDiscounted.toStringAsFixed(2)));
      },
      'totalPromotions': (row) => Center(
        child: Tooltip(
          message: 'Общее количество акций, загруженных в систему',
          child: Text(row.cells['totalPromotions']?.value?.toString() ?? '0'),
        ),
      ),
      'activePromotions': (row) => Center(
        child: Tooltip(
          message: 'Количество акций, в которых участвует данный товар',
          child: Text(row.cells['activePromotions']?.value?.toString() ?? '0'),
        ),
      ),
      'participationPercent': (row) => Center(
        child: Tooltip(
          message: 'Доля активных акций от общего числа (округлено до целого)',
          child: Text('${row.cells['participationPercent']?.value?.toString() ?? '0'}%'),
        ),
      ),
      'fbs_quantity': (row) => Center(
        child: Text(row.cells['fbs_quantity']?.value?.toString() ?? '0'),
      ),
      'total_quantity': (row) => Center(
        child: Text(row.cells['total_quantity']?.value?.toString() ?? '0'),
      ),
      'fbsCommission': (row) {
        final value = row.cells['fbsCommission']?.value;
        final subjectId = row.cells['subjectID']?.value as int? ?? 0;
        return Tooltip(
          message: 'Комиссия FBS для subjectID $subjectId: $value%',
          child: Center(child: Text(value?.toString() ?? '0')),
        );
      },
      'fboCommission': (row) {
        final value = row.cells['fboCommission']?.value;
        final subjectId = row.cells['subjectID']?.value as int? ?? 0;
        return Tooltip(
          message: 'Комиссия FBO для subjectID $subjectId: $value%',
          child: Center(child: Text(value?.toString() ?? '0')),
        );
      },
      'costPrice': (row) {
        final value = row.cells['costPrice']?.value;
        return Tooltip(
          message: 'Себестоимость товара (загружена из hide_domain.com/cost)',
          child: Center(child: Text(value?.toString() ?? '0')),
        );
      },
      'additionalExpenses': (row) {
        final value = row.cells['additionalExpenses']?.value;
        return Tooltip(
          message: 'Дополнительные расходы на единицу товара',
          child: Center(child: Text(value?.toString() ?? '0')),
        );
      },
      'fbsLogistics': (row) => _buildLogisticsCell(row, true),
      'fboLogistics': (row) => _buildLogisticsCell(row, false),
      'priceChart': (row) {
        final nmId = row.cells['nmID']?.value as int;
        return FutureBuilder<List<int>>(
          future: _provider.getPriceHistory(nmId, 21),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final values = snapshot.data!.map((price) => price.toDouble()).toList();
            final dates = _provider.getLastNDates(21);
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
      'ordersChart': (row) {
        final nmId = row.cells['nmID']?.value as int;
        return FutureBuilder<List<double>>(
          future: _salesManager.getValuesForNmId(nmId, 21, open: false),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final values = snapshot.data!;
            final dates = _salesManager.getLastNDates(21);
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
      'stocksFboChart': (row) {
        final nmId = row.cells['nmID']?.value as int;
        return FBOStocksChart(
          nmId: nmId,
          futureHistory: _getStocksHistory(nmId),
        );
      },
      'queriesChart': (row) {
        final nmId = row.cells['nmID']?.value as int;
        return FutureBuilder<List<int>>(
          future: _getSearchFrequenciesCached(nmId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
            }
            if (!snapshot.hasData) return const SizedBox.shrink();
            final frequencies = snapshot.data!;
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final dates = List.generate(21, (i) => today.subtract(Duration(days: 20 - i)));
            final labels = dates.map((d) => DateFormat('dd.MM').format(d)).toList();
            final values = frequencies.map((v) => v.toDouble()).toList();
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
      'viewsChart': (row) {
        final nmId = row.cells['nmID']?.value as int;
        return FutureBuilder<List<double>>(
          future: _salesManager.getValuesForNmId(nmId, 21, open: true),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final values = snapshot.data!;
            final dates = _salesManager.getLastNDates(21);
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
    };
  }

  Future<void> _debugPrintFirstSalesFunnelRecord() async {
    try {
      final firstRecord = await _salesManager.getFirstRecord();
      if (firstRecord != null) {
        print('🔍 [DEBUG] Первая запись воронки продаж:');
        print('  nmId: ${firstRecord.nmId}');
        print('  date: ${firstRecord.date}');
        print('  openCount: ${firstRecord.openCount}');
        print('  orderCount: ${firstRecord.orderCount}');
      } else {
        print('⚠️ [DEBUG] Данные воронки продаж отсутствуют (нет записей).');
      }
    } catch (e) {
      print('❌ [DEBUG] Ошибка получения первой записи воронки: $e');
    }
  }

  Widget _buildLogisticsCell(PlutoRow row, bool isFBS) {
    final volumeStr = row.cells['volume']?.value?.toString() ?? '0';
    final volume = double.tryParse(volumeStr) ?? 0.0;
    final warehouseCoef = isFBS
        ? _getWarehouseCoefficient(_selectedFBSTariff, true)
        : _getWarehouseCoefficient(_selectedFBOTariff, false);
    final logistics = _calculateLogistics(volume, warehouseCoef, _localizationIndex);
    final formula = _getLogisticsFormulaText(volume, warehouseCoef, _localizationIndex, isFBS);
    return Tooltip(
      message: formula,
      child: Center(child: Text(logistics.toStringAsFixed(2))),
    );
  }

  void _rebuildColumnsWithPromotions() {
    final baseColumns = List<ColumnDefinition>.from(_columns.where((c) => !c.field.startsWith('promotion_')).toList());
    final promotionColumns = _promotions.map((promo) {
      return ColumnDefinition(
        field: promo.columnKey,
        title: promo.displayLabel,
        dataType: ColumnDataType.number,
        width: 70,
        minWidth: 50,
      );
    }).toList();

    int discountIndex = baseColumns.indexWhere((c) => c.field == 'discount');
    if (discountIndex == -1) discountIndex = baseColumns.length - 1;

    final newColumns = List<ColumnDefinition>.from(baseColumns);
    newColumns.insertAll(discountIndex + 1, promotionColumns);

    setState(() {
      _columns = newColumns;
    });

    _updateCustomBuildersForPromotions();
  }

  void _updateCustomBuildersForPromotions() {
    for (var promo in _promotions) {
      _customBuilders[promo.columnKey] = (row) {
        final nmID = row.cells['nmID']?.value as int;
        final realDiscount = row.cells['discount']?.value as int? ?? 0;
        final draftDiscount = _draftDiscounts[nmID];
        final effectiveDiscount = draftDiscount ?? realDiscount;
        final planDiscount = _provider.getPromotionDiscount(promo.id, nmID);
        final inAction = _provider.getPromotionInAction(promo.id, nmID);

        String display = '';
        Color textColor = Colors.grey;
        double fontSize = 12;
        FontWeight fontWeight = FontWeight.normal;

        if (planDiscount != null) {
          display = planDiscount.toString();
          if (promo.isRegularPromotion) {
            if (inAction == false && effectiveDiscount >= planDiscount) {
              textColor = Colors.red;
              fontSize = 20;
              fontWeight = FontWeight.bold;
            } else if (inAction == true && planDiscount <= effectiveDiscount) {
              textColor = Colors.green;
              fontSize = 20;
              fontWeight = FontWeight.bold;
            } else {
              textColor = Colors.black;
            }
          } else if (promo.isAutoPromotion) {
            if (planDiscount <= effectiveDiscount) {
              textColor = Colors.green;
              fontSize = 20;
              fontWeight = FontWeight.bold;
            } else {
              textColor = Colors.black;
            }
          }
        }

        return Tooltip(
          message: promo.tooltipText +
              (planDiscount != null
                  ? '\n\nРекомендуемая скидка: $planDiscount%\n'
                      'Текущая скидка: $effectiveDiscount% (${draftDiscount != null ? "черновик" : "сохранённая"})\n'
                      'Участвует в акции: ${inAction == true ? "Да" : "Нет"}'
                  : '\n\nТовар не участвует в акции'),
          child: Container(
            alignment: Alignment.center,
            child: Text(
              display,
              style: TextStyle(
                color: textColor,
                fontSize: fontSize,
                fontWeight: fontWeight,
              ),
            ),
          ),
        );
      };
    }
  }

  Future<void> _loadPromotions() async {
    if (_wbApiToken == null) {
      _wbApiToken = await TokenManager().getToken();
      if (_wbApiToken == null) return;
      _goodsLoader = PromotionGoodsLoader(wbApiToken: _wbApiToken);
    }
    if (_isLoadingPromotions) return;

    setState(() => _isLoadingPromotions = true);

    try {
      final now = DateTime.now().toUtc();
      final startDate = now.subtract(const Duration(days: 1));
      final endDate = now.add(const Duration(days: 1));
      final startStr = startDate.toIso8601String().substring(0, 19) + 'Z';
      final endStr = endDate.toIso8601String().substring(0, 19) + 'Z';

      final response = await http.get(
        Uri.parse(
          'https://dp-calendar-api.wildberries.ru/api/v1/calendar/promotions'
              '?startDateTime=$startStr&endDateTime=$endStr&allPromo=false&limit=100',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': _wbApiToken!,
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final promotionsData = data['data']['promotions'] as List<dynamic>;
        final List<Promotion> allPromotions = [];
        for (var promoData in promotionsData) {
          try {
            allPromotions.add(Promotion.fromJson(promoData));
          } catch (e) {
            print('Ошибка парсинга акции: $e');
          }
        }

        final filtered = allPromotions.where((p) {
          if (p.startDateTime == null) return false;
          final hoursUntilStart = p.startDateTime!.difference(now).inHours;
          final isActive = p.startDateTime!.isBefore(now) &&
              p.endDateTime != null &&
              p.endDateTime!.isAfter(now);
          final isStartingSoon = p.startDateTime!.isAfter(now) && hoursUntilStart <= 24;
          return isActive || isStartingSoon;
        }).toList();

        setState(() {
          _promotions = filtered;
        });
        _rebuildColumnsWithPromotions();
      }
    } catch (e) {
      print('Ошибка загрузки акций: $e');
    } finally {
      setState(() => _isLoadingPromotions = false);
    }
  }

  Future<void> _loadAllPromotionGoods() async {
    if (_promotions.isEmpty) return;

    final regular = _promotions.where((p) => p.isRegularPromotion).toList();
    final auto = _promotions.where((p) => p.isAutoPromotion).toList();

    const maxConcurrent = 3;
    for (int i = 0; i < regular.length; i += maxConcurrent) {
      final batch = regular.sublist(i, (i + maxConcurrent) > regular.length ? regular.length : i + maxConcurrent);
      await Future.wait(batch.map((promo) => _loadSinglePromotionGoods(promo)));
      if (i + maxConcurrent < regular.length) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    for (var promo in auto) {
      await _loadSinglePromotionGoods(promo);
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<void> _loadSinglePromotionGoods(Promotion promotion) async {
    if (_promotionGoodsLoaded[promotion.id] == true) return;
    final goods = await _goodsLoader.loadGoodsForPromotion(promotion);
    if (goods != null && goods.isNotEmpty) {
      _provider.updatePromotionGoods(promotion.id, goods);
      if (mounted) _refreshTable();
    }
    _promotionGoodsLoaded[promotion.id] = true;
  }

  Future<void> _initializeData() async {
    print('🔷 _initializeData: начало');
    await _provider.loadPrices();
    await _provider.loadCurrentPrices();
    await _provider.loadCosts();

    final sw = Stopwatch()..start();
    print('🔷 1. Начинаем _loadBoxTariffs()');
    await _loadBoxTariffs();
    print('🔷 1. _loadBoxTariffs() завершён за ${sw.elapsedMilliseconds} ms');
    sw.reset();

    print('🔷 2. Начинаем _provider.loadPriceHistory()');
    _priceHistoryLoadFuture = _provider.loadPriceHistory().then((_) {
      print('🔷 2. _provider.loadPriceHistory() завершён');
    });
    sw.reset();

    print('🔷 3. Начинаем _priceHistoryManager.loadAllPriceHistory()');
    _priceHistoryLoad2Future = _priceHistoryManager.loadAllPriceHistory().then((_) {
      print('🔷 3. _priceHistoryManager.loadAllPriceHistory() завершён');
    });
    sw.reset();

    print('🔷 4. Начинаем _provider.loadCurrentPriceHistory()');
    _currentPriceHistoryFuture = _provider.loadCurrentPriceHistory().then((_) {
      print('🔷 4. _provider.loadCurrentPriceHistory() завершён');
    });

    _syncLogisticsParamsToProvider();
    print('🔷 Цены загружены (синхронно после тарифов)');

    final now = DateTime.now();
    final utcNow = DateTime.now().toUtc();
    print('🔍 Локальное время: $now');
    print('🔍 UTC время: $utcNow');

    final allProducts = ProductManager().allProducts;
    final subjectIds = allProducts.map((p) => p.subjectID).where((id) => id > 0).toSet();
    if (subjectIds.isNotEmpty) {
      await _provider.loadCommissions(subjectIds);
      print('🔷 Комиссии загружены для ${subjectIds.length} subjectID');
    }

    await _loadPromotions();
    print('🔷 Акции загружены, количество: ${_promotions.length}');

    await _stocksManager.loadAllStocks();
    print('🔷 Остатки загружены');
    _provider.setStocksManager(_stocksManager);

    await _loadSearchHistory();
    await _loadCurrentSearchData();

    if (_promotions.isNotEmpty && _goodsLoader.wbApiToken != null) {
      _provider.updatePromotions(_promotions);
      print('🔷 Начинаем загрузку товаров акций...');
      _loadAllPromotionGoods();
    } else {
      print('⚠️ Не загружаем товары акций: промоций нет или токен null');
    }

    _customColumns = await _provider.getCustomColumns();
    print('🔷 Загружено кастомных колонок: ${_customColumns.length}');

    if (mounted) {
      setState(() => _isInitialized = true);
    }
    await _debugPrintFirstSalesFunnelRecord();
    print('🔷 _initializeData: завершено');
  }

  Future<List<int>> _getSearchFrequencies(int nmId) async {
    return await _searchQueryService.getTotalFrequenciesForLastNDays(nmId, 21);
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

  Future<void> _loadBoxTariffs() async {
    try {
      final response = await http.get(
        Uri.parse('https://hide_domain.com/box-tariffs'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tariffs = data['tariffs'] as List<dynamic>;
        setState(() {
          _boxTariffs = tariffs;
          _cachedUniqueWarehouseNames = _computeWarehouseNamesFast(tariffs);
        });
        await _loadSelectedWarehouses();
        await _loadLocalizationIndex();
        _updateSelectedTariffs();
      }
    } catch (e) {
      print('Ошибка загрузки тарифов: $e');
    }
  }

  List<String> _computeWarehouseNamesFast(List<dynamic> tariffs) {
    final Set<String> unique = {};
    for (var t in tariffs) {
      final name = t['warehouse_name']?.toString().trim();
      if (name != null && name.isNotEmpty && name.toLowerCase() != 'id' && !name.contains('nan')) {
        unique.add(name);
      }
    }
    final list = unique.toList()..sort();
    return list;
  }

  Future<void> _loadSelectedWarehouses() async {
    final prefs = await SharedPreferences.getInstance();
    final savedFBS = prefs.getString('selectedFBSWarehouse');
    final savedFBO = prefs.getString('selectedFBOWarehouse');
    setState(() {
      _selectedFBSWarehouse = savedFBS;
      _selectedFBOWarehouse = savedFBO;
    });
    _updateSelectedTariffs();
  }

  void _updateSelectedTariffs() {
    setState(() {
      _selectedFBSTariff = _findTariffByWarehouse(_selectedFBSWarehouse, isFBS: true);
      _selectedFBOTariff = _findTariffByWarehouse(_selectedFBOWarehouse, isFBS: false);
    });
    _syncLogisticsParamsToProvider();
  }

  Map<String, dynamic>? _findTariffByWarehouse(String? warehouseName, {required bool isFBS}) {
    if (warehouseName == null || warehouseName.isEmpty) return null;
    final normalized = _normalizeWarehouseName(warehouseName);
    if (normalized == null) return null;
    for (var tariff in _boxTariffs) {
      final tName = tariff['warehouse_name']?.toString();
      if (_normalizeWarehouseName(tName) == normalized) {
        return Map<String, dynamic>.from(tariff);
      }
    }
    return null;
  }

  String? _normalizeWarehouseName(String? name) {
    if (name == null || name.isEmpty) return null;
    return name.trim().toLowerCase().replaceAll(RegExp(r'[^\w\sа-яА-ЯёЁ]'), '');
  }

  Future<void> _loadLocalizationIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble('localizationIndex') ?? 1.00;
    setState(() {
      _localizationIndex = saved;
      _localizationIndexController.text = saved.toStringAsFixed(2);
    });
  }

  Future<void> _saveLocalizationIndex(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('localizationIndex', value);
  }

  Future<void> _saveSelectedWarehouses() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedFBSWarehouse', _selectedFBSWarehouse ?? '');
    await prefs.setString('selectedFBOWarehouse', _selectedFBOWarehouse ?? '');
  }

  double _calculateLogistics(double volume, double warehouseCoef, double localizationIndex) {
    if (volume <= 0 || warehouseCoef <= 0) return 0.0;
    double baseCost;
    if (volume <= 1.0) {
      if (volume <= 0.200) baseCost = 23.0;
      else if (volume <= 0.400) baseCost = 26.0;
      else if (volume <= 0.600) baseCost = 29.0;
      else if (volume <= 0.800) baseCost = 30.0;
      else baseCost = 32.0;
    } else {
      baseCost = 46.0 + (14.0 * (volume - 1));
    }
    double result = baseCost * (warehouseCoef / 100.0) * localizationIndex;
    return double.parse(result.toStringAsFixed(2));
  }

  double _getWarehouseCoefficient(Map<String, dynamic>? tariff, bool isFBS) {
    if (tariff == null) return 100.0;
    final coefExpr = isFBS
        ? tariff['box_delivery_marketplace_coef_expr']
        : tariff['box_delivery_coef_expr'];
    if (coefExpr != null) {
      final coefStr = coefExpr.toString().replaceAll('%', '').trim();
      return double.tryParse(coefStr) ?? 100.0;
    }
    return 100.0;
  }

  String _getLogisticsFormulaText(double volume, double warehouseCoef, double localizationIndex, bool isFBS) {
    if (volume <= 0 || warehouseCoef <= 0) return "Объём = 0 или коэффициент не задан";
    double baseCost;
    String formulaPart;
    if (volume <= 1.0) {
      if (volume <= 0.200) baseCost = 23.0;
      else if (volume <= 0.400) baseCost = 26.0;
      else if (volume <= 0.600) baseCost = 29.0;
      else if (volume <= 0.800) baseCost = 30.0;
      else baseCost = 32.0;
      formulaPart = "Фиксированная стоимость: $baseCost руб.";
    } else {
      baseCost = 46.0 + (14.0 * (volume - 1));
      formulaPart = "46 + (14 × (${volume.toStringAsFixed(3)} - 1))";
    }
    double result = baseCost * (warehouseCoef / 100.0) * localizationIndex;
    return "Логистика ${isFBS ? "FBS" : "FBO"}:\n"
        "База: $formulaPart = ${baseCost.toStringAsFixed(2)} руб.\n"
        "Коэф. склада: ${warehouseCoef.toStringAsFixed(1)}% = ${(warehouseCoef/100).toStringAsFixed(3)}\n"
        "Индекс локализации: ${localizationIndex.toStringAsFixed(2)}\n"
        "Итог: ${result.toStringAsFixed(2)} руб.";
  }

  String _getLocalizationIndexText() {
    if (_localizationIndex == 1.00) return "Базовый";
    if (_localizationIndex < 1.00) {
      final discount = (1.00 - _localizationIndex) * 100;
      return "Скидка ${discount.toStringAsFixed(1)}%";
    } else {
      final markup = (_localizationIndex - 1.00) * 100;
      return "Наценка ${markup.toStringAsFixed(1)}%";
    }
  }

  Future<List<StocksHistoryData>> _getStocksHistory(int nmId) {
    if (!_stocksHistoryFutures.containsKey(nmId)) {
      final dateFrom = DateTime.now().subtract(const Duration(days: 22));
      _stocksHistoryFutures[nmId] = StocksHistoryManager().getStocksHistory(
        nmId: nmId,
        dateFrom: dateFrom,
      ).catchError((error) {
        print('Ошибка загрузки истории остатков для $nmId: $error');
        return <StocksHistoryData>[];
      });
    }
    return _stocksHistoryFutures[nmId]!;
  }

  void _refreshTable() async {
    _customColumns = await _provider.getCustomColumns();
    if (mounted) setState(() {});
  }

  Future<void> _sendAllChanges() async {
    try {
      await PriceManager().sendAllChanges();
      await _provider.loadPrices();
      _provider.clearDrafts();
      setState(() {
        _draftPrices.clear();
        _draftDiscounts.clear();
        _draftClubDiscounts.clear();
      });
      _refreshCustomColumns();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Все изменения успешно отправлены'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Map<String, dynamic> _buildRowMap(Product product) {
    final chrtID = product.sizes.isNotEmpty ? product.sizes.first.chrtID : 0;
    final priceData = PriceManager().getPrices(product.nmID, chrtID);
    final volume = product.dimensionsLength * product.dimensionsWidth * product.dimensionsHeight / 1000.0;
    final photos = product.getPhotoUrls();
    final previewUrl = photos.isNotEmpty ? photos.first : null;

    final fbs = _stocksManager.getFBSQuantity(product.nmID);
    final fbo = _stocksManager.getFBOQuantity(product.nmID);

    final totalPromotionsCount = _provider.getTotalPromotionsCount(product);
    final activePromotionsCount = _provider.getActivePromotionsCount(product);
    final participationPercent = _provider.getParticipationPercent(product);

    final subjectId = product.subjectID;

    final fbsCommissionPercent = _provider.getFBSCommissionPercent(product);
    final fboCommissionPercent = _provider.getFBOCommissionPercent(product);

    final costPrice = _provider.getCostPrice(product);
    final additionalExpenses = _provider.getAdditionalExpenses(product);

    final fbsWarehouseCoef = _getWarehouseCoefficient(_selectedFBSTariff, true);
    final fboWarehouseCoef = _getWarehouseCoefficient(_selectedFBOTariff, false);
    final fbsLogistics = _calculateLogistics(volume, fbsWarehouseCoef, _localizationIndex);
    final fboLogistics = _calculateLogistics(volume, fboWarehouseCoef, _localizationIndex);

    final price = (priceData?['price'] as num?)?.toDouble() ?? 0.0;
    final discount = (priceData?['discount'] as num?)?.toDouble() ?? 0.0;
    final clubDiscount = (priceData?['clubDiscount'] as num?)?.toDouble() ?? 0.0;
    final discountedPrice = price - (price * discount / 100);
    final clubDiscountedPrice = discountedPrice - (discountedPrice * clubDiscount / 100);

    final map = {
      'nmID': product.nmID,
      'chrtID': chrtID,
      'vendorCode': product.vendorCode,
      'title': product.title,
      'subjectName': product.subjectName,
      'subjectID': subjectId,
      'volume': volume.toStringAsFixed(3),
      'tags': product.tags,
      'preview': previewUrl,
      'price': priceData?['price'],
      'discount': priceData?['discount'],
      'select': false,
      'clubDiscount': priceData?['clubDiscount'],
      'totalPromotions': totalPromotionsCount,
      'activePromotions': activePromotionsCount,
      'participationPercent': participationPercent,
      'fbs_quantity': fbs,
      'total_quantity': fbo,
      'fbsCommission': fbsCommissionPercent,
      'fboCommission': fboCommissionPercent,
      'costPrice': costPrice,
      'additionalExpenses': additionalExpenses,
      'fbsLogistics': fbsLogistics,
      'fboLogistics': fboLogistics,
      'discountedPrice': discountedPrice,
      'clubDiscountedPrice': clubDiscountedPrice,
      'customerPrice': _provider.getFieldValue(product, 'customerPrice'),
      'priceChart': null,
      'ordersChart': null,
      'stocksFboChart': null,
      'queriesChart': null,
      'viewsChart': null,
      'discountHistory': null,
    };

    for (var promo in _promotions) {
      final discount = _provider.getPromotionDiscount(promo.id, product.nmID);
      map[promo.columnKey] = discount;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _isLoadingPromotions) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildTopControls(),
          Expanded(
            child: UniversalDataTable<Product>(
              key: _tableKey,
              controller: _tableController,
              screenId: 'prices_screen_new',
              provider: _provider,
              columns: _columns,
              customCellBuilders: _customBuilders,
              toMap: _buildRowMap,
              headerFeatures: const HeaderFeaturesConfig(
                showSettingsButton: false,
                showAddCustomColumnButton: false,
              ),
              toolbarBuilder: (context, controller) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopControls() {
    final warehouseNames = _cachedUniqueWarehouseNames ?? [];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildWarehouseGroup(
            title: 'FBS',
            warehouse: _selectedFBSWarehouse,
            items: warehouseNames,
            onChanged: (val) {
              setState(() {
                _selectedFBSWarehouse = val;
                _updateSelectedTariffs();
              });
              _saveSelectedWarehouses();
              _refreshCustomColumns();
            },
            tariff: _selectedFBSTariff,
            isFBS: true,
          ),
          const SizedBox(width: 16),
          _buildWarehouseGroup(
            title: 'FBO',
            warehouse: _selectedFBOWarehouse,
            items: warehouseNames,
            onChanged: (val) {
              setState(() {
                _selectedFBOWarehouse = val;
                _updateSelectedTariffs();
              });
              _saveSelectedWarehouses();
              _refreshCustomColumns();
            },
            tariff: _selectedFBOTariff,
            isFBS: false,
          ),
          const SizedBox(width: 24),
          _buildLocalizationControlImproved(),
          const SizedBox(width: 16),
          _buildSendButton(),
          const SizedBox(width: 20),
          IconButton(
            icon: const Icon(Icons.settings, size: 22),
            onPressed: _tableController.showSettingsDialog,
            tooltip: 'Настройки таблицы',
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.add, size: 22),
            onPressed: _tableController.showCustomColumnManagementDialog,
            tooltip: 'Добавить кастомный столбец',
          ),
        ],
      ),
    );
  }

  Widget _buildWarehouseGroup({
    required String title,
    required String? warehouse,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required Map<String, dynamic>? tariff,
    required bool isFBS,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 160,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: warehouse,
              isExpanded: true,
              hint: const Text(
                'Выберите склад',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('—', style: TextStyle(fontSize: 12, color: Colors.black)),
                ),
                ...items.map(
                      (w) => DropdownMenuItem(
                    value: w,
                    child: Text(w, style: const TextStyle(fontSize: 12, color: Colors.black)),
                  ),
                ),
              ],
              onChanged: onChanged,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.black54),
              style: const TextStyle(fontSize: 12, color: Colors.black),
            ),
          ),
        ),
        if (tariff != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              isFBS
                  ? 'база: ${tariff['box_delivery_marketplace_base'] ?? '-'} ₽, коэф: ${tariff['box_delivery_marketplace_coef_expr'] ?? '-'}%'
                  : 'база: ${tariff['box_delivery_base'] ?? '-'} ₽, коэф: ${tariff['box_delivery_coef_expr'] ?? '-'}%',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _buildLocalizationControlImproved() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Индекс локализации',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 18, color: Colors.black54),
                onPressed: () {
                  final newVal = (_localizationIndex - 0.01).clamp(0.01, 4.00);
                  _localizationIndexController.text = newVal.toStringAsFixed(2);
                  _onLocalizationChanged(newVal);
                },
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              SizedBox(
                width: 60,
                child: TextFormField(
                  controller: _localizationIndexController,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.black),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    final doubleVal = double.tryParse(val);
                    if (doubleVal != null && doubleVal >= 0.01 && doubleVal <= 4.00) {
                      _onLocalizationChanged(doubleVal);
                    } else {
                      _localizationIndexController.text = _localizationIndex.toStringAsFixed(2);
                    }
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 18, color: Colors.black54),
                onPressed: () {
                  final newVal = (_localizationIndex + 0.01).clamp(0.01, 4.00);
                  _localizationIndexController.text = newVal.toStringAsFixed(2);
                  _onLocalizationChanged(newVal);
                },
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _getLocalizationIndexText(),
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildSendButton() {
    final hasDrafts = _draftPrices.isNotEmpty ||
        _draftDiscounts.isNotEmpty ||
        _draftClubDiscounts.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: hasDrafts ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(
          Icons.send,
          size: 22,
          color: hasDrafts ? Colors.green.shade700 : Colors.grey.shade400,
        ),
        onPressed: hasDrafts ? _sendAllChanges : null,
        tooltip: 'Отправить все изменения',
        padding: const EdgeInsets.all(8),
      ),
    );
  }

  void _onLocalizationChanged(double newValue) {
    setState(() {
      _localizationIndex = newValue;
    });
    _saveLocalizationIndex(newValue);
    _syncLogisticsParamsToProvider();
  }

  @override
  void dispose() {
    _localizationIndexController.dispose();
    super.dispose();
  }
}