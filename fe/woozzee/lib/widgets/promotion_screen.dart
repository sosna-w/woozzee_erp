// promotion_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'universal_data_table.dart';
import '../models/product.dart';
import '../utils/product_manager.dart';
import '../utils/photo_cache_manager.dart';
import '../utils/token_manager.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'dart:async';
import '../services/campaign_service.dart';
import 'dart:math' as math;

// ============================================================================
// Упрощённый диалог выбора диапазона дат
// ============================================================================

class SimpleDateRangePickerDialog extends StatefulWidget {
  final DateTimeRange? initialRange;
  final void Function(DateTimeRange) onConfirm;

  const SimpleDateRangePickerDialog({
    Key? key,
    this.initialRange,
    required this.onConfirm,
  }) : super(key: key);

  @override
  State<SimpleDateRangePickerDialog> createState() =>
      _SimpleDateRangePickerDialogState();
}

class _SimpleDateRangePickerDialogState
    extends State<SimpleDateRangePickerDialog> {
  late DateTime _focusedDay;
  DateTime? _selectedStart;
  DateTime? _selectedEnd;
  DateTimeRange? _selectedRange;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  late final DateTime _minDate;
  late final DateTime _maxDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _minDate = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 30));
    _maxDate = DateTime(now.year, now.month, now.day);

    if (widget.initialRange != null) {
      _selectedStart = widget.initialRange!.start;
      _selectedEnd = widget.initialRange!.end;
      _selectedRange = widget.initialRange;
      _focusedDay = widget.initialRange!.start;
    } else {
      _focusedDay = _maxDate;
    }
  }

  String _formatDate(DateTime date) => DateFormat('dd.MM.yyyy').format(date);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Выберите диапазон дат',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              height: 360,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: TableCalendar(
                firstDay: _minDate,
                lastDay: _maxDate,
                focusedDay: _focusedDay,
                startingDayOfWeek: StartingDayOfWeek.monday,
                locale: 'ru_RU',
                calendarFormat: _calendarFormat,
                rangeSelectionMode: RangeSelectionMode.toggledOn,
                rangeStartDay: _selectedStart,
                rangeEndDay: _selectedEnd,
                enabledDayPredicate: (day) =>
                day.isAfter(_minDate.subtract(const Duration(days: 1))) &&
                    day.isBefore(_maxDate.add(const Duration(days: 1))),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    if (_selectedStart == null || _selectedEnd != null) {
                      _selectedStart = selectedDay;
                      _selectedEnd = null;
                      _selectedRange = null;
                    } else {
                      if (selectedDay.isBefore(_selectedStart!)) {
                        _selectedEnd = _selectedStart;
                        _selectedStart = selectedDay;
                      } else {
                        _selectedEnd = selectedDay;
                      }
                      _selectedRange = DateTimeRange(
                        start: _selectedStart!,
                        end: _selectedEnd!,
                      );
                    }
                    _focusedDay = focusedDay;
                  });
                },
                onPageChanged: (focusedDay) =>
                    setState(() => _focusedDay = focusedDay),
                onFormatChanged: (format) =>
                    setState(() => _calendarFormat = format),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, date, _) {
                    final bool isAvailable =
                        date.isAfter(_minDate.subtract(const Duration(days: 1))) &&
                            date.isBefore(_maxDate.add(const Duration(days: 1)));
                    final bool isSelected = date == _selectedStart ||
                        date == _selectedEnd ||
                        (_selectedStart != null &&
                            _selectedEnd != null &&
                            date.isAfter(_selectedStart!) &&
                            date.isBefore(_selectedEnd!));
                    final bool isToday =
                    DateUtils.isSameDay(date, DateTime.now());

                    Color backgroundColor;
                    Color borderColor;
                    Color textColor;

                    if (isSelected) {
                      backgroundColor = Theme.of(context).primaryColor;
                      borderColor = Theme.of(context).primaryColor;
                      textColor = Colors.white;
                    } else if (isToday) {
                      backgroundColor = Colors.blue[50]!;
                      borderColor = Colors.blue;
                      textColor = Colors.blue[800]!;
                    } else if (isAvailable) {
                      backgroundColor = Colors.green.withOpacity(0.1);
                      borderColor = Colors.green;
                      textColor = Colors.green[800]!;
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
                        boxShadow: isSelected
                            ? [
                          BoxShadow(
                            color: Theme.of(context)
                                .primaryColor
                                .withOpacity(0.3),
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
                  titleTextStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(fontWeight: FontWeight.bold),
                  weekendStyle: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.red),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                  style: TextButton.styleFrom(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _selectedRange != null
                      ? () {
                    widget.onConfirm(_selectedRange!);
                    Navigator.pop(context);
                  }
                      : null,
                  child: const Text('Выбрать диапазон'),
                  style: ElevatedButton.styleFrom(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Виджет превью фото с увеличением
// ============================================================================

class ImagePreviewCell extends StatefulWidget {
  final String? imageUrl;
  final double width;

  const ImagePreviewCell({
    Key? key,
    this.imageUrl,
    this.width = 50,
  }) : super(key: key);

  @override
  State<ImagePreviewCell> createState() => _ImagePreviewCellState();
}

class _ImagePreviewCellState extends State<ImagePreviewCell> {
  OverlayEntry? _overlayEntry;
  Timer? _hideTimer;
  final PhotoCacheManager _cacheManager = PhotoCacheManager();

  @override
  void initState() {
    super.initState();
    _cacheManager.initialize();
  }

  void _showPreview(Offset globalPosition) {
    if (_overlayEntry != null) return;
    _hideTimer?.cancel();

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: globalPosition.dx + 20,
        top: globalPosition.dy - 150,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: widget.imageUrl != null
                  ? Image.network(
                widget.imageUrl!,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (context, error, stack) => const Center(
                  child: Icon(Icons.broken_image,
                      size: 48, color: Colors.grey),
                ),
              )
                  : const Center(
                  child: Icon(Icons.image_not_supported, size: 48)),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _hidePreview() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 200), () {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  void _cancelHide() {
    _hideTimer?.cancel();
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) {
      return const SizedBox.shrink();
    }

    return MouseRegion(
      onEnter: (event) {
        _cancelHide();
        _showPreview(event.position);
      },
      onExit: (_) => _hidePreview(),
      child: Image.network(
        widget.imageUrl!,
        fit: BoxFit.contain,
        width: widget.width,
        height: 50,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const SizedBox.shrink();
        },
        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      ),
    );
  }
}

// ============================================================================
// Провайдер данных для таблицы
// ============================================================================

class PromotionDataProvider implements DataProvider<Product> {
  final ProductManager _productManager = ProductManager();
  final Map<int, String> barcodeMap;
  final Map<int, int> productCampaignCount;
  final Map<int, int> productActiveCount;
  final Map<int, int> productPausedCount;
  final Map<int, int> productSearchBid;
  final Map<int, int> productRecommendationBid;

  PromotionDataProvider({
    required this.barcodeMap,
    required this.productCampaignCount,
    required this.productActiveCount,
    required this.productPausedCount,
    this.productSearchBid = const {},
    this.productRecommendationBid = const {},
  });

  @override
  dynamic getFieldValue(Product product, String field) {
    switch (field) {
      case 'supplier_article':
        return product.vendorCode;
      case 'wb_article':
        return product.nmID;
      case 'name':
        return product.title;
      case 'subject':
        return product.subjectName;
      case 'tags':
        return product.tags;
      case 'preview_photo':
        final photos = product.getPhotoUrls();
        return photos.isNotEmpty ? photos.first : null;
      case 'barcode':
        return barcodeMap[product.nmID] ?? '';
      case 'campaigns_count':
        return productCampaignCount[product.nmID] ?? 0;
      case 'active_campaigns_count':
        return productActiveCount[product.nmID] ?? 0;
      case 'paused_campaigns_count':
        return productPausedCount[product.nmID] ?? 0;
      case 'search_bid':
        final bid = productSearchBid[product.nmID];
        return bid != null ? (bid / 100).toStringAsFixed(2) : '—';
      case 'recommendations_bid':
        final bid = productRecommendationBid[product.nmID];
        return bid != null ? (bid / 100).toStringAsFixed(2) : '—';
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

    // Для поля "tags" собираем теги из ВСЕХ товаров, игнорируя фильтры
    if (field == 'tags') {
      final allProducts = _productManager.allProducts;
      final Set<String> uniqueTags = {};
      for (var product in allProducts) {
        final tagsList = product.tags as List<dynamic>?;
        if (tagsList != null) {
          for (var tag in tagsList) {
            final name = tag['name']?.toString();
            if (name != null && name.isNotEmpty) {
              uniqueTags.add(name);
              if (uniqueTags.length >= maxValues) break;
            }
          }
        }
        if (uniqueTags.length >= maxValues) break;
      }
      values.addAll(uniqueTags);
      return values.take(maxValues).toList();
    }

    // Для всех остальных полей используем отфильтрованные товары
    final filtered = _applyFilters(_productManager.allProducts, filters);
    for (var product in filtered) {
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
        case 'barcode':
          val = barcodeMap[product.nmID];
          break;
        case 'campaigns_count':
          val = productCampaignCount[product.nmID] ?? 0;
          break;
        case 'active_campaigns_count':
          val = productActiveCount[product.nmID] ?? 0;
          break;
        case 'paused_campaigns_count':
          val = productPausedCount[product.nmID] ?? 0;
          break;
        case 'search_bid':
          final bid = productSearchBid[product.nmID];
          val = bid != null ? (bid / 100).toStringAsFixed(2) : '—';
          break;
        case 'recommendations_bid':
          final bid = productRecommendationBid[product.nmID];
          val = bid != null ? (bid / 100).toStringAsFixed(2) : '—';
          break;
        default:
          continue;
      }
      if (val != null && val.toString().isNotEmpty) {
        values.add(val);
      }
      if (values.length >= maxValues) break;
    }
    return values.take(maxValues).toList();
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
          case 'barcode':
            productValue = barcodeMap[product.nmID];
            break;
          case 'campaigns_count':
            productValue = productCampaignCount[product.nmID] ?? 0;
            break;
          case 'active_campaigns_count':
            productValue = productActiveCount[product.nmID] ?? 0;
            break;
          case 'paused_campaigns_count':
            productValue = productPausedCount[product.nmID] ?? 0;
            break;
          case 'search_bid':
            final bid = productSearchBid[product.nmID];
            productValue = bid != null ? (bid / 100).toStringAsFixed(2) : '—';
            break;
          case 'recommendations_bid':
            final bid = productRecommendationBid[product.nmID];
            productValue = bid != null ? (bid / 100).toStringAsFixed(2) : '—';
            break;
          default:
            productValue = null;
        }
        if (productValue == null) return false;
        if (!selectedValues.contains(productValue.toString())) return false;
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
          cmp = (barcodeMap[a.nmID] ?? '').compareTo(barcodeMap[b.nmID] ?? '');
          break;
        case 'campaigns_count':
          cmp = (productCampaignCount[a.nmID] ?? 0)
              .compareTo(productCampaignCount[b.nmID] ?? 0);
          break;
        case 'active_campaigns_count':
          cmp = (productActiveCount[a.nmID] ?? 0)
              .compareTo(productActiveCount[b.nmID] ?? 0);
          break;
        case 'paused_campaigns_count':
          cmp = (productPausedCount[a.nmID] ?? 0)
              .compareTo(productPausedCount[b.nmID] ?? 0);
          break;
        case 'search_bid':
          final aBid = productSearchBid[a.nmID];
          final bBid = productSearchBid[b.nmID];
          final aVal = aBid ?? -1;
          final bVal = bBid ?? -1;
          cmp = aVal.compareTo(bVal);
          break;
        case 'recommendations_bid':
          final aBid = productRecommendationBid[a.nmID];
          final bBid = productRecommendationBid[b.nmID];
          final aVal = aBid ?? -1;
          final bVal = bBid ?? -1;
          cmp = aVal.compareTo(bVal);
          break;
        default:
          cmp = 0;
      }
      return sortDesc ? -cmp : cmp;
    });
    return list;
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

// ============================================================================
// ЭКРАН ПРОДВИЖЕНИЯ
// ============================================================================

class PromotionScreen extends StatefulWidget {
  const PromotionScreen({Key? key}) : super(key: key);

  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  final GlobalKey<UniversalDataTableState> _tableKey = GlobalKey<UniversalDataTableState>();
  late final UniversalDataTableController _tableController;
  late PromotionDataProvider _provider;
  bool _initialSortApplied = false;

  Map<int, List<String>> _productAllCampaigns = {};
  Map<int, List<String>> _productActiveCampaigns = {};
  Map<int, List<String>> _productPausedCampaigns = {};

  DateTimeRange? _selectedDateRange;
  final TextEditingController _dateRangeController = TextEditingController();
  bool _isInitialized = false;

  Map<int, int> _campaignBudgets = {};
  bool _budgetsLoading = false;

  Map<int, Map<String, dynamic>> _campaignStats = {};
  bool _statsLoading = false;

  Map<String, dynamic> _balanceData = {};
  bool _balanceLoading = false;

  Map<int, String> _barcodeMap = {};

  List<CampaignShort> _allCampaignsShort = [];
  Map<int, CampaignDetails> _campaignsDetailsMap = {};
  bool _campaignsLoading = false;
  CampaignDetails? _selectedCampaign;

  Map<int, int> _productCampaignCount = {};
  Map<int, int> _productActiveCount = {};
  Map<int, int> _productPausedCount = {};

  @override
  void initState() {
    super.initState();
    _tableController = UniversalDataTableController();

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final weekAgo = yesterday.subtract(const Duration(days: 6));
    _selectedDateRange = DateTimeRange(
      start: DateTime(weekAgo.year, weekAgo.month, weekAgo.day),
      end: DateTime(yesterday.year, yesterday.month, yesterday.day),
    );
    _updateDateRangeController();

    _initializeData();
  }

  @override
  void dispose() {
    _dateRangeController.dispose();
    super.dispose();
  }

  void _updateCampaignStatus(int campaignId, int newStatus) {
    setState(() {
      final details = _campaignsDetailsMap[campaignId];
      if (details != null) {
        _campaignsDetailsMap[campaignId] = CampaignDetails(
          id: details.id,
          name: details.name,
          paymentType: details.paymentType,
          bidType: details.bidType,
          searchPlacement: details.searchPlacement,
          recommendationsPlacement: details.recommendationsPlacement,
          nmIds: details.nmIds,
          status: newStatus,
          updated: details.updated,
        );
      }
      final shortIndex = _allCampaignsShort.indexWhere((c) => c.id == campaignId);
      if (shortIndex != -1) {
        final oldShort = _allCampaignsShort[shortIndex];
        _allCampaignsShort[shortIndex] = CampaignShort(
          id: oldShort.id,
          type: oldShort.type,
          status: newStatus,
          changeTime: oldShort.changeTime,
        );
      }
      if (_selectedCampaign?.id == campaignId) {
        _selectedCampaign = _campaignsDetailsMap[campaignId];
      }
    });
  }

  Future<void> _pauseCampaign(CampaignDetails campaign) async {
    final tokenManager = TokenManager();
    await tokenManager.initialize();
    final token = await tokenManager.getToken();
    if (token == null) {
      _showError('Не удалось получить токен');
      return;
    }
    try {
      final service = CampaignService();
      await service.pauseCampaign(token, campaign.id);
      _updateCampaignStatus(campaign.id, 11);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Кампания поставлена на паузу'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      _showError('Ошибка паузы: $e');
    }
  }

  Widget _buildCampaignTypeWidget(CampaignDetails campaign) {
    final paymentTypeText = campaign.paymentType == 'cpm' ? 'CPM' : 'CPC';
    final paymentTooltip = campaign.paymentType == 'cpm' ? 'За показы' : 'За клики';
    final bidTypeText = campaign.bidTypeText;
    final bidTooltip = bidTypeText == 'Ручная' ? 'Ручное управление ставками' : 'Автоматическая ставка (Единая)';

    return SizedBox(
      width: 140, // общая фиксированная ширина
      child: Row(
        children: [
          // 1. Тип оплаты (CPM/CPC) – ширина 40
          SizedBox(
            width: 40,
            child: Tooltip(
              message: paymentTooltip,
              child: Text(
                paymentTypeText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          // 2. Тип ставки – ширина 60
          SizedBox(
            width: 60,
            child: Tooltip(
              message: bidTooltip,
              child: Text(
                bidTypeText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          // 3. Иконка поиска – всегда ширина 20
          SizedBox(
            width: 20,
            child: campaign.searchPlacement
                ? Tooltip(
              message: 'Показывается в поиске',
              child: const Center(child: Icon(Icons.search, size: 16)),
            )
                : const SizedBox.shrink(),
          ),
          // 4. Иконка рекомендаций – всегда ширина 20
          SizedBox(
            width: 20,
            child: campaign.recommendationsPlacement
                ? Tooltip(
              message: 'Показывается в рекомендациях',
              child: const Center(child: Icon(Icons.thumb_up, size: 16)),
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _startCampaign(CampaignDetails campaign) async {
    final tokenManager = TokenManager();
    await tokenManager.initialize();
    final token = await tokenManager.getToken();
    if (token == null) {
      _showError('Не удалось получить токен');
      return;
    }
    try {
      final service = CampaignService();
      await service.startCampaign(token, campaign.id);
      _updateCampaignStatus(campaign.id, 9);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Кампания запущена'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      _showError('Ошибка запуска: $e');
    }
  }

  Widget _buildStatsWidget(CampaignDetails campaign) {
    final stats = _campaignStats[campaign.id];
    const double chipWidth = 64;               // фиксированная ширина
    const double chipHeight = 42;              // увеличенная высота
    const double totalWidth = chipWidth * 9;   // 576 пикселей

    if (_statsLoading) {
      return SizedBox(
        width: totalWidth,
        height: chipHeight,
        child: const Center(
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (stats == null) {
      return SizedBox(
        width: totalWidth,
        height: chipHeight,
        child: const Center(child: Text('—', style: TextStyle(fontSize: 12))),
      );
    }

    String formatCurrency(dynamic v) =>
        v == null ? '—' : NumberFormat('#,###', 'ru_RU').format(v is int ? v : v as double);
    String formatPercent(dynamic v) =>
        v == null ? '—' : '${(v is double ? v : v.toDouble()).toStringAsFixed(2)}%';
    String formatInt(dynamic v) =>
        v == null ? '—' : NumberFormat('#,###', 'ru_RU').format(v);

    final sumPrice = stats['sum_price'];
    final sum = stats['sum'];
    final clicks = stats['clicks'];
    final cpc = stats['cpc'];
    final views = stats['views'];
    final atbs = stats['atbs'];
    final shks = stats['shks'];
    final ctr = stats['ctr'];
    final cr = stats['cr'];

    const valueStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
    const chipDecoration = BoxDecoration(
      color: Color(0xFFF5F5F5),
      borderRadius: BorderRadius.all(Radius.circular(16)),
      border: Border.fromBorderSide(BorderSide(color: Color(0xFFE0E0E0), width: 0.5)),
    );

    Widget buildChip(String tooltip, String value) {
      return Container(
        width: chipWidth,
        height: chipHeight,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        decoration: chipDecoration,
        child: Tooltip(
          message: tooltip,
          child: Text(value, style: valueStyle, textAlign: TextAlign.center),
        ),
      );
    }

    return SizedBox(
      width: totalWidth,
      height: chipHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          buildChip('Сумма заказов, ₽', formatCurrency(sumPrice)),
          buildChip('Затраты, ₽', formatCurrency(sum)),
          buildChip('Клики', formatInt(clicks)),
          buildChip('Цена за клик, ₽', formatCurrency(cpc)),
          buildChip('Показы', formatInt(views)),
          buildChip('В корзину', formatInt(atbs)),
          buildChip('Заказы, шт', formatInt(shks)),
          buildChip('CTR, %', formatPercent(ctr)),
          buildChip('CR, %', formatPercent(cr)),
        ],
      ),
    );
  }

  Future<void> _stopCampaign(CampaignDetails campaign) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Завершение кампании'),
        content: Text('Вы уверены, что хотите завершить кампанию "${campaign.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Завершить')),
        ],
      ),
    );
    if (confirm != true) return;

    final tokenManager = TokenManager();
    await tokenManager.initialize();
    final token = await tokenManager.getToken();
    if (token == null) {
      _showError('Не удалось получить токен');
      return;
    }
    try {
      final service = CampaignService();
      await service.stopCampaign(token, campaign.id);
      setState(() {
        _campaignsDetailsMap.remove(campaign.id);
        _allCampaignsShort.removeWhere((c) => c.id == campaign.id);
        if (_selectedCampaign?.id == campaign.id) _selectedCampaign = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Кампания завершена'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      _showError('Ошибка завершения: $e');
    }
  }

  Future<void> _fetchMinBidsForCampaign(CampaignDetails campaign) async {
    final tokenManager = TokenManager();
    await tokenManager.initialize();
    final token = await tokenManager.getToken();
    if (token == null || token.isEmpty) {
      print('❌ Не удалось получить токен для запроса минимальных ставок');
      return;
    }

    final paymentTypeStr = campaign.paymentType;
    if (paymentTypeStr != 'cpm' && paymentTypeStr != 'cpc') {
      print('❌ Неизвестный тип оплаты: $paymentTypeStr');
      return;
    }

    // Всегда запрашиваем все три типа размещения
    final List<String> placementTypes = ['search', 'recommendation', 'combined'];

    List<int> nmIds = campaign.nmIds;
    if (nmIds.isEmpty) {
      print('⚠️ В кампании нет товаров');
      return;
    }
    if (nmIds.length > 100) {
      print('⚠️ В кампании ${nmIds.length} товаров, но API принимает не более 100. Будут отправлены первые 100.');
      nmIds = nmIds.sublist(0, 100);
    }

    final body = {
      'advert_id': campaign.id,
      'nm_ids': nmIds,
      'payment_type': paymentTypeStr,
      'placement_types': placementTypes,
    };

    final uri = Uri.parse('https://advert-api.wildberries.ru/api/advert/v1/bids/min');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('\n✅ Минимальные ставки для кампании "${campaign.name}" (id: ${campaign.id}):');
        print(JsonEncoder.withIndent('  ').convert(data));
      } else {
        print('❌ Ошибка ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('❌ Исключение при запросе минимальных ставок: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildStatusIcon(CampaignDetails campaign) {
    final isActive = campaign.status == 9;
    return GestureDetector(
      onTap: () {
        if (isActive) {
          _pauseCampaign(campaign);
        } else if (campaign.status == 11) {
          _showCampaignActionMenu(campaign);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        child: isActive
            ? const Icon(Icons.play_arrow, color: Colors.green, size: 30)
            : const Icon(Icons.pause, color: Colors.orange, size: 30),
      ),
    );
  }

  Future<void> _loadCampaignStats() async {
    // 1. Проверка периода (максимум 31 день)
    if (_selectedDateRange == null) {
      setState(() => _campaignStats = {});
      return;
    }

    final difference = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays + 1;
    if (difference > 31) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Период не может превышать 31 день. Выберите меньший интервал.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // 2. Берём только активные/на паузе кампании
    final campaignsToLoad = _campaignsDetailsMap.values
        .where((c) => c.status == 9 || c.status == 11)
        .toList();

    if (campaignsToLoad.isEmpty) {
      setState(() => _campaignStats = {});
      return;
    }

    setState(() => _statsLoading = true);

    final tokenManager = TokenManager();
    await tokenManager.initialize();
    final token = await tokenManager.getToken();
    if (token == null) {
      setState(() => _statsLoading = false);
      return;
    }

    final service = CampaignService();
    final Map<int, Map<String, dynamic>> allStats = {};

    // 3. Разбиваем ID на пачки по 50
    final ids = campaignsToLoad.map((c) => c.id).toList();
    for (int i = 0; i < ids.length; i += 50) {
      final end = i + 50 > ids.length ? ids.length : i + 50;
      final chunk = ids.sublist(i, end);
      try {
        final stats = await service.fetchCampaignsStats(
          token,
          chunk,
          _selectedDateRange!.start,
          _selectedDateRange!.end,
        );
        allStats.addAll(stats);
      } catch (e) {
        debugPrint('❌ Ошибка загрузки статистики для пачки $chunk: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка загрузки статистики: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      // Задержка между пачками (1 сек — для разработки, для production при базовом тарифе нужен 1 час)
      if (i + 50 < ids.length) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    if (mounted) {
      setState(() {
        _campaignStats = allStats;
        _statsLoading = false;
      });
    }
  }

  void _showCampaignActionMenu(CampaignDetails campaign) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Управление кампанией'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow, color: Colors.green),
              title: const Text('Запустить кампанию'),
              onTap: () {
                Navigator.pop(context);
                _startCampaign(campaign);
              },
            ),
            ListTile(
              leading: const Icon(Icons.stop, color: Colors.red),
              title: const Text('Завершить кампанию'),
              onTap: () {
                Navigator.pop(context);
                _stopCampaign(campaign);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        ],
      ),
    );
  }

  Future<void> _initializeData() async {
    final productManager = ProductManager();
    if (!productManager.isInitialized) {
      await productManager.initialize();
    }
    _buildBarcodeMapFromProducts();

    _provider = PromotionDataProvider(
      barcodeMap: _barcodeMap,
      productCampaignCount: _productCampaignCount,
      productActiveCount: _productActiveCount,
      productPausedCount: _productPausedCount,
    );
    setState(() {
      _isInitialized = true;
    });

    await _loadCampaignData();
    _updateProvider();
    _tableController.refreshData();

    // Применяем начальную сортировку по столбцу "Всего кампаний"
    if (!_initialSortApplied) {
      _initialSortApplied = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tableKey.currentState?.setSort('campaigns_count', descending: true);
      });
    }
  }

  Future<void> _showDepositDialog(CampaignDetails campaign, int currentBudget) async {
    final tokenManager = TokenManager();
    await tokenManager.initialize();
    final token = await tokenManager.getToken();
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось получить токен')),
      );
      return;
    }

    final balanceAccount = (_balanceData['balance'] as int?) ?? 0;
    final balanceNet = (_balanceData['net'] as int?) ?? 0;
    final balanceBonus = (_balanceData['bonus'] as int?) ?? 0;

    int selectedType = 0;
    int depositSum = 0;
    final sumController = TextEditingController();

    int getLimitForType(int type) {
      switch (type) {
        case 0: return balanceAccount;
        case 1: return balanceNet;
        case 3: return balanceBonus;
        default: return 0;
      }
    }

    String getSourceName(int type) {
      switch (type) {
        case 0: return 'Счёт';
        case 1: return 'Баланс';
        case 3: return 'Бонусы';
        default: return '';
      }
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final limit = getLimitForType(selectedType);
            final sourceName = getSourceName(selectedType);
            String? errorText;

            final sumText = sumController.text;
            if (sumText.isNotEmpty) {
              final sum = int.tryParse(sumText);
              if (sum == null || sum <= 0) {
                errorText = 'Введите положительное число';
              } else if (sum > limit) {
                errorText = 'Превышает доступный лимит ($sourceName: ${_formatNumber(limit)} ₽)';
              }
            } else {
              errorText = null;
            }

            return AlertDialog(
              title: const Text('Пополнение бюджета кампании'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Бюджет кампании: ${_formatNumber(currentBudget)} ₽'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: sumController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Сумма пополнения (₽)',
                      hintText: 'Введите сумму',
                      border: const OutlineInputBorder(),
                      suffixText: '₽',
                      errorText: errorText,
                    ),
                    onChanged: (value) {
                      final sum = int.tryParse(value) ?? 0;
                      setStateDialog(() {
                        depositSum = sum;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: selectedType,
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Text('Счёт (${_formatNumber(balanceAccount)} ₽)'),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Text('Баланс (${_formatNumber(balanceNet)} ₽)'),
                      ),
                      DropdownMenuItem(
                        value: 3,
                        child: Text('Бонусы (${_formatNumber(balanceBonus)} ₽)'),
                      ),
                    ],
                    onChanged: (newType) {
                      if (newType != null) {
                        setStateDialog(() {
                          selectedType = newType;
                          depositSum = int.tryParse(sumController.text) ?? 0;
                        });
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Источник списания',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: errorText == null && depositSum > 0
                      ? () async {
                    Navigator.pop(context);
                    await _depositBudget(
                      token: token,
                      campaignId: campaign.id,
                      sum: depositSum,
                      type: selectedType,
                    );
                  }
                      : null,
                  child: const Text('Пополнить'),
                ),
              ],
            );
          },
        );
      },
    );
    sumController.dispose();
  }

  Future<void> _depositBudget({
    required String token,
    required int campaignId,
    required int sum,
    required int type,
  }) async {
    try {
      final service = CampaignService();
      final newBudget = await service.depositBudget(
        token: token,
        campaignId: campaignId,
        sum: sum,
        type: type,
        returnBudget: true,
      );

      if (newBudget != null) {
        setState(() {
          _campaignBudgets[campaignId] = newBudget;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Бюджет успешно пополнен! Новый бюджет: ${_formatNumber(newBudget)} ₽'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Не удалось получить обновлённый бюджет');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка пополнения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadCampaignBudgets(String token, List<CampaignDetails> campaigns) async {
    if (campaigns.isEmpty) return;

    setState(() {
      _budgetsLoading = true;
    });

    final service = CampaignService();
    final Map<int, int> budgets = {};

    for (int i = 0; i < campaigns.length; i++) {
      final campaign = campaigns[i];
      try {
        final budget = await service.fetchCampaignBudget(token, campaign.id);
        if (budget != null) {
          budgets[campaign.id] = budget;
        }
      } catch (e) {
        debugPrint('❌ Ошибка бюджета для кампании ${campaign.id}: $e');
      }

      if (i < campaigns.length - 1) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }

    setState(() {
      _campaignBudgets = budgets;
      _budgetsLoading = false;
    });
  }

  Future<void> _loadCampaignData() async {
    try {
      setState(() {
        _campaignsLoading = true;
        _balanceLoading = true;
      });

      final tokenManager = TokenManager();
      await tokenManager.initialize();
      final token = await tokenManager.getToken();
      if (token == null || token.isEmpty) {
        setState(() {
          _campaignsLoading = false;
          _balanceLoading = false;
        });
        return;
      }

      final service = CampaignService();

      final balance = await service.fetchBalance(token);
      setState(() {
        _balanceData = balance;
        _balanceLoading = false;
      });

      final result = await service.loadFullCampaignData(token);

      final Map<int, int> activeCount = {};
      final Map<int, int> pausedCount = {};

      for (final campaign in result.details.values) {
        final int status = campaign.status;
        for (final nmId in campaign.nmIds) {
          if (status == 9) {
            activeCount[nmId] = (activeCount[nmId] ?? 0) + 1;
          } else if (status == 11) {
            pausedCount[nmId] = (pausedCount[nmId] ?? 0) + 1;
          }
        }
      }

      _productAllCampaigns.clear();
      _productActiveCampaigns.clear();
      _productPausedCampaigns.clear();

      for (final campaign in result.details.values) {
        final name = campaign.name;
        final status = campaign.status;
        for (final nmId in campaign.nmIds) {
          _productAllCampaigns.putIfAbsent(nmId, () => []).add(name);
          if (status == 9) {
            _productActiveCampaigns.putIfAbsent(nmId, () => []).add(name);
          } else if (status == 11) {
            _productPausedCampaigns.putIfAbsent(nmId, () => []).add(name);
          }
        }
      }

      setState(() {
        _allCampaignsShort = result.short;
        _campaignsDetailsMap = result.details;
        _productCampaignCount = result.productCount;
        _productActiveCount = activeCount;
        _productPausedCount = pausedCount;
        _campaignsLoading = false; // UI разблокирован сразу
      });

      _updateProvider();
      _tableController.refreshData();

      final campaignsToLoad = result.details.values
          .where((c) => c.status == 9 || c.status == 11)
          .toList();

      if (campaignsToLoad.isNotEmpty) {
        setState(() {
          _budgetsLoading = true;   // 🔄 включаем спиннеры
        });
        try {
          final budgetStream = service.loadBudgetsStream(token, campaignsToLoad);
          await for (final entry in budgetStream) {
            if (mounted) {
              setState(() {
                _campaignBudgets[entry.key] = entry.value;
              });
              await Future.delayed(const Duration(milliseconds: 50));
            }
          }
        } finally {
          if (mounted) {
            setState(() {
              _budgetsLoading = false;  // ✅ загрузка бюджетов завершена
            });
          }
        }
      }

      if (mounted) {
        await _loadCampaignStats();   // загружаем статистику за выбранный период
      }

      debugPrint('✅ Загружено кампаний: ${result.short.length}, деталей: ${result.details.length}, бюджетов: ${_campaignBudgets.length}');
    } catch (e) {
      debugPrint('❌ Ошибка при загрузке данных кампаний: $e');
      if (mounted) {
        setState(() {
          _campaignsLoading = false;
          _balanceLoading = false;
          _budgetsLoading = false;
        });
      }
    }
  }

  void _buildBarcodeMapFromProducts() {
    final productManager = ProductManager();
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

  String _formatNumber(int? value) {
    if (value == null || value == 0) return '—';
    return NumberFormat('#,###', 'ru_RU').format(value);
  }

  void _updateProvider() {
    final timestamp = DateTime.now().toIso8601String();
    print('[$timestamp] _updateProvider START');
    final searchBidMap = _selectedCampaign?.searchBidMap ?? {};
    final recBidMap = _selectedCampaign?.recBidMap ?? {};
    _provider = PromotionDataProvider(
      barcodeMap: _barcodeMap,
      productCampaignCount: _productCampaignCount,
      productActiveCount: _productActiveCount,
      productPausedCount: _productPausedCount,
      productSearchBid: searchBidMap,
      productRecommendationBid: recBidMap,
    );
    print('[$timestamp] _updateProvider FINISH, searchBidMap size = ${searchBidMap.length}');
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
        onConfirm: (range) async {   // ← добавить async
          setState(() {
            _selectedDateRange = range;
            _updateDateRangeController();
          });
          await _loadCampaignStats(); // ← перезагрузить статистику
        },
      ),
    );
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
        field: 'campaigns_count',
        title: 'Всего кампаний',
        dataType: ColumnDataType.number,
        width: 130,
        cellPadding: EdgeInsets.zero,
      ),
      ColumnDefinition(
        field: 'active_campaigns_count',
        title: 'Активных',
        dataType: ColumnDataType.number,
        width: 100,
        cellPadding: EdgeInsets.zero,
      ),
      ColumnDefinition(
        field: 'paused_campaigns_count',
        title: 'На паузе',
        dataType: ColumnDataType.number,
        width: 100,
        cellPadding: EdgeInsets.zero,
      ),
      ColumnDefinition(
        field: 'search_bid',
        title: 'Ставка в поиске',
        dataType: ColumnDataType.text,
        width: 130,
        showSort: true,
        showFilter: true,
      ),
      ColumnDefinition(
        field: 'recommendations_bid',
        title: 'Ставка в рекомендациях',
        dataType: ColumnDataType.text,
        width: 150,
        showSort: true,
        showFilter: true,
      ),
    ];
  }

  Map<String, Widget Function(PlutoRow)> _buildCustomCellBuilders() {
    return {
      'campaigns_count': (row) => _buildCampaignCell(
        row,
        countField: 'campaigns_count',
        namesField: 'campaigns_names',
        chipColor: Colors.grey,
      ),
      'active_campaigns_count': (row) => _buildCampaignCell(
        row,
        countField: 'active_campaigns_count',
        namesField: 'active_campaigns_names',
        chipColor: Colors.green,
      ),
      'paused_campaigns_count': (row) => _buildCampaignCell(
        row,
        countField: 'paused_campaigns_count',
        namesField: 'paused_campaigns_names',
        chipColor: Colors.orange,
      ),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
    };
  }

  Widget _buildCampaignCell(PlutoRow row, {
    required String countField,
    required String namesField,
    required Color chipColor,
  }) {
    final count = row.cells[countField]?.value as int? ?? 0;
    final names = row.cells[namesField]?.value as List<String>? ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 10,
            child: Text(
              count.toString(),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: names.map((name) {
                  final campaign = _campaignsDetailsMap.values
                      .cast<CampaignDetails?>()
                      .firstWhere((c) => c?.name == name, orElse: () => null);
                  return InkWell(
                    onTap: campaign != null
                        ? () => _selectCampaign(campaign)
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Tooltip(
                      message: name,
                      child: Container(
                        margin: const EdgeInsets.only(right: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: chipColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: chipColor.withOpacity(0.3), width: 0.5),
                        ),
                        child: Text(
                          name.length > 20 ? '${name.substring(0, 20)}…' : name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: chipColor,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _selectCampaign(CampaignDetails? campaign) {
    final timestamp = DateTime.now().toIso8601String();
    print('[$timestamp] _selectCampaign START: ${campaign?.name} (id: ${campaign?.id})');

    if (_selectedCampaign == campaign) {
      print('[$timestamp] _selectCampaign: кампания не изменилась, выход');
      return;
    }

    setState(() {
      _selectedCampaign = campaign;
    });
    print('[$timestamp] _selectCampaign: _selectedCampaign обновлён');

    _updateProvider();
    print('[$timestamp] _selectCampaign: _updateProvider выполнен');

    _tableController.refreshData();
    print('[$timestamp] _selectCampaign: refreshData вызван');

    // ✨ НОВЫЙ ЗАПРОС К API МИНИМАЛЬНЫХ СТАВОК
    if (campaign != null) {
      _fetchMinBidsForCampaign(campaign);
    }

    // Принудительно сбрасываем и устанавливаем сортировку
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_selectedCampaign == campaign) {
        print('[$timestamp] _selectCampaign: сброс сортировки и установка search_bid descending');
        _tableKey.currentState?.clearSort();
        _tableKey.currentState?.setSort('search_bid', descending: true);
      } else {
        print('[$timestamp] _selectCampaign: кампания сменилась, сортировка отменена');
      }
    });
  }

  Map<String, dynamic> _buildRowMap(Product product) {
    final photos = product.getPhotoUrls();
    final previewUrl = photos.isNotEmpty ? photos.first : null;

    final searchBid = _selectedCampaign?.searchBidMap[product.nmID];
    final recBid = _selectedCampaign?.recBidMap[product.nmID];

    return {
      'supplier_article': product.vendorCode,
      'wb_article': product.nmID,
      'name': product.title,
      'subject': product.subjectName,
      'tags': product.tags,
      'preview_photo': previewUrl,
      'barcode': _barcodeMap[product.nmID] ?? '',
      'campaigns_count': _productCampaignCount[product.nmID] ?? 0,
      'active_campaigns_count': _productActiveCount[product.nmID] ?? 0,
      'paused_campaigns_count': _productPausedCount[product.nmID] ?? 0,
      'campaigns_names': _productAllCampaigns[product.nmID] ?? [],
      'active_campaigns_names': _productActiveCampaigns[product.nmID] ?? [],
      'paused_campaigns_names': _productPausedCampaigns[product.nmID] ?? [],
      'search_bid': searchBid != null ? (searchBid / 100).toStringAsFixed(2) : '—',
      'recommendations_bid': recBid != null ? (recBid / 100).toStringAsFixed(2) : '—',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final availableCampaigns = _campaignsDetailsMap.values
        .where((c) => c.status == 9 || c.status == 11)
        .toList();
    availableCampaigns.sort((a, b) {
      final aWeight = a.status == 9 ? 0 : 1;
      final bWeight = b.status == 9 ? 0 : 1;
      if (aWeight != bWeight) return aWeight.compareTo(bWeight);
      return b.updated.compareTo(a.updated);
    });

    return Scaffold(
      body: Column(
        children: [
          // Верхняя панель
          Container(
            height: 82,
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Выбор дат
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
                // Виджет баланса
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: _balanceLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 240,
                        height: 40,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _formatNumber(_balanceData['balance']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const Text(
                                    'Счёт',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _formatNumber(_balanceData['net']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const Text(
                                    'Баланс',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _formatNumber(_balanceData['bonus']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const Text(
                                    'Бонусы',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_balanceData['cashbacks'] != null &&
                          (_balanceData['cashbacks'] as List).isNotEmpty)
                        ..._buildCashbacksChips(_balanceData['cashbacks']),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.filter_alt_off, size: 28),
                  onPressed: () => _tableController.clearFilters(),
                  tooltip: 'Сбросить все фильтры',
                ),
                const SizedBox(width: 16),
                // Выпадающий список кампаний
                Expanded(
                  child: _campaignsLoading
                      ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                      :
                  // Изменённый DropdownButtonFormField<CampaignDetails> с увеличенной высотой
                  DropdownButtonFormField<CampaignDetails>(
                    icon: const SizedBox.shrink(),
                    autofocus: false,
                    focusColor: Colors.transparent,
                    isDense: false,                       // ← важно: отключаем плотный режим
                    isExpanded: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12), // увеличенная высота поля
                      hintText: 'Выберите кампанию',
                    ),
                    value: _selectedCampaign,
                    items: availableCampaigns.map((campaign) {
                      final budget = _campaignBudgets[campaign.id];
                      final Widget budgetWidget;
                      if (budget != null) {
                        budgetWidget = Text('${budget} ₽');
                      } else if (_budgetsLoading) {
                        budgetWidget = const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      } else {
                        budgetWidget = const Text('—');
                      }

                      return DropdownMenuItem<CampaignDetails>(
                        value: campaign,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12.0), // удвоенная высота пункта
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: _buildStatusIcon(campaign),
                              ),

                              // Бюджет
                              Container(
                                width: 110,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.amber.shade50, Colors.amber.shade100],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.amber.shade300, width: 0.5),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.account_balance_wallet, size: 14, color: Colors.amber.shade800),
                                    const SizedBox(width: 4),
                                    budgetWidget,
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: () => _showDepositDialog(campaign, budget ?? 0),
                                      child: Icon(Icons.add_circle_outline, size: 24, color: Colors.amber.shade800),
                                    ),
                                  ],
                                ),
                              ),

                              // Тип кампании
                              _buildCampaignTypeWidget(campaign),

                              const SizedBox(width: 4),

                              // Количество товаров
                              SizedBox(
                                width: 70,
                                child: _buildProductsCountWidget(campaign),
                              ),

                              // Название
                              SizedBox(
                                width: 220,
                                child: Text(
                                  campaign.name,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),

                              // Статистика
                              Flexible(child: _buildStatsWidget(campaign)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    selectedItemBuilder: (context) {
                      return availableCampaigns.map((campaign) {
                        final budget = _campaignBudgets[campaign.id];
                        final budgetText = budget != null ? '${budget} ₽' : (_budgetsLoading ? '...' : '—');

                        return Center(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: _buildStatusIcon(campaign),
                              ),
                              // Бюджет (сжатая версия)
                              Container(
                                width: 110,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.amber.shade50, Colors.amber.shade100],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.amber.shade300, width: 0.5),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.account_balance_wallet, size: 18, color: Colors.amber.shade800),
                                    const SizedBox(width: 4),
                                    Text(
                                      budgetText,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: () => _showDepositDialog(campaign, budget ?? 0),
                                      child: Icon(
                                        Icons.add_circle_outline,
                                        size: 16,
                                        color: Colors.amber.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _buildCampaignTypeWidget(campaign),
                              const SizedBox(width: 4),
                              SizedBox(
                                width: 70,
                                child: _buildProductsCountWidget(campaign),
                              ),
                              SizedBox(
                                width: 220,
                                child: Text(
                                  campaign.name,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                              Flexible(child: _buildStatsWidget(campaign)),
                            ],
                          ),
                        );
                      }).toList();
                    },
                    onChanged: (campaign) {
                      _selectCampaign(campaign);
                      debugPrint('Выбрана кампания: ${campaign?.name} (id: ${campaign?.id})');
                    },
                  )
                ),
              ],
            ),
          ),
          // Таблица
          Expanded(
            child: UniversalDataTable<Product>(
              key: _tableKey,
              controller: _tableController,
              screenId: 'promotion',
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

  List<Widget> _buildCashbacksChips(List<dynamic> cashbacks) {
    return cashbacks.map((cb) {
      final sum = cb['sum'] as int?;
      final percent = cb['percent'] as int?;
      final expiration = cb['expiration_date'] != null ? DateTime.tryParse(cb['expiration_date']) : null;
      final expirationStr = expiration != null ? DateFormat('dd.MM.yy').format(expiration) : '';
      return Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.purple.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.purple.shade200),
        ),
        child: Text(
          'Промо: ${_formatNumber(sum)}₽ (${percent ?? 0}% до $expirationStr)',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
      );
    }).toList();
  }

  Widget _buildProductsCountWidget(CampaignDetails campaign) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_bag_outlined, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 4),
          Text(
            '${campaign.nmIds.length}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}