import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;

double universalDataTableHeaderIconSize = 12.0;

// ============================================================================
// Конфигурация видимости элементов заголовка
// ============================================================================

class HeaderFeaturesConfig {
  final bool showStatistics;      // Значение статистики и символ (Σ, x̄ и т.д.)
  final bool showMenu;            // Кнопка меню (три точки)
  final bool showAggregation;     // Кнопка настройки агрегации (группировка, методы)
  final bool showChart;           // Кнопка добавления в график
  final bool showSort;            // Кнопка сортировки
  final bool showFilter;          // Кнопка фильтра
  final bool showDataTypeAndDivider; // Тип данных (123, ₽, %) и разделитель над ним
  final bool showTitleAndDivider;    // Название колонки и разделитель над ним
  final bool showSettingsButton;
  final bool showAddCustomColumnButton;

  const HeaderFeaturesConfig({
    this.showStatistics = true,
    this.showMenu = true,
    this.showAggregation = true,
    this.showChart = true,
    this.showSort = true,
    this.showFilter = true,
    this.showDataTypeAndDivider = true,
    this.showTitleAndDivider = true,
    this.showSettingsButton = true,
    this.showAddCustomColumnButton = true,
  });
}

// ============================================================================
// 1. Контракты для источника данных (расширены)
// ============================================================================

class ColumnDefinition {
  final String field;
  final String title;
  final ColumnDataType dataType;
  final bool isAggregatable;
  final bool isGroupable;
  double width;
  final String? formatPattern;
  final bool hideTitle;
  final double minWidth;

  // Флаги для управления элементами заголовка
  final bool showStatistics;
  final bool showAggregation;
  final bool showChart;
  final bool showSort;
  final bool showFilter;
  final bool showDataType;

  // Настраиваемые отступы внутри ячейки (если null — используются стандартные)
  final EdgeInsetsGeometry? cellPadding;

  ColumnDefinition({
    required this.field,
    required this.title,
    required this.dataType,
    this.isAggregatable = true,
    this.isGroupable = true,
    this.width = 120,
    this.formatPattern,
    this.hideTitle = false,
    this.minWidth = 68.0,
    this.showStatistics = true,
    this.showAggregation = true,
    this.showChart = true,
    this.showSort = true,
    this.showFilter = true,
    this.showDataType = true,
    this.cellPadding,
  });
}

enum ColumnDataType { text, number, date, currency, percent, checkbox }

class CustomColumn {
  final String name;
  final String displayName;
  final String formula;
  CustomColumn(this.name, this.displayName, this.formula);
}

class TimeSeriesPoint {
  final DateTime date;
  final double value;
  TimeSeriesPoint(this.date, this.value);
}

class FilterSet {
  final Map<String, List<dynamic>> filters;

  // Всегда делаем изменяемую копию
  FilterSet([Map<String, List<dynamic>>? filters])
      : filters = Map.from(filters ?? {});

  FilterSet copyWith(Map<String, List<dynamic>>? newFilters) =>
      FilterSet(newFilters ?? Map.from(filters));

  bool get isEmpty => filters.isEmpty;
  bool get isNotEmpty => filters.isNotEmpty;
  bool hasFilter(String field) => filters.containsKey(field) && filters[field]!.isNotEmpty;
}

abstract class DataProvider<T> {
  dynamic getFieldValue(T item, String field) => null;
  Future<int> getTotalCount({
    required FilterSet filters,
    String? groupByField,
  });

  Future<List<T>> fetchData({
    required int offset,
    required int limit,
    required FilterSet filters,
    String? sortField,
    bool sortDesc = true,
    String? groupByField,
    Map<String, String>? aggregationMethods,
  });

  Future<List<dynamic>> getUniqueValues({
    required String field,
    required FilterSet filters,
    int maxValues = 1000,
  });

  Future<List<TimeSeriesPoint>> getTimeSeriesData({
    required String dateField,
    required String valueField,
    required FilterSet filters,
  });

  Future<Map<String, dynamic>> getAggregatedTotals({
    required FilterSet filters,
    String? groupByField,
  });

  Future<List<DateTime>> getAvailableDates() async => [];

  // Кастомные колонки
  Future<void> addCustomColumn(String name, String formula) async {}
  Future<void> updateCustomColumn(String oldName, String newName, String formula) async {}
  Future<void> deleteCustomColumn(String name) async {}
  Future<List<CustomColumn>> getCustomColumns() async => [];

  // Дополнительно для группировки (если нужно)
  Future<int> getAggregatedGroupCount({
    required String groupByField,
    required FilterSet filters,
  }) async => 0;
}

// ============================================================================
// 2. Хранение настроек (расширено) с ленивой инициализацией
// ============================================================================

class TableSettingsService {
  static const String _prefix = 'univ_table_';
  SharedPreferences? _prefs;
  bool _initialized = false;

  TableSettingsService._();
  static final TableSettingsService instance = TableSettingsService._();
  static const String _keyHeaderHeightOffset = '_header_height_offset';

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  String _key(String screenId, String suffix) => '$_prefix$screenId$suffix';

  // Порядок колонок
  Future<void> saveColumnOrder(String screenId, List<String> order) async {
    await _ensureInitialized();
    await _prefs!.setStringList(_key(screenId, '_order'), order);
  }
  Future<List<String>?> loadColumnOrder(String screenId) async {
    await _ensureInitialized();
    return _prefs!.getStringList(_key(screenId, '_order'));
  }

  Future<void> saveHeaderHeightOffset(String screenId, int offset) async {
    await _ensureInitialized();
    await _prefs!.setInt(_key(screenId, _keyHeaderHeightOffset), offset);
  }

  Future<int> loadHeaderHeightOffset(String screenId) async {
    await _ensureInitialized();
    return _prefs!.getInt(_key(screenId, _keyHeaderHeightOffset)) ?? 0;
  }

  // Скрытые колонки
  Future<void> saveHiddenColumns(String screenId, Set<String> hidden) async {
    await _ensureInitialized();
    await _prefs!.setStringList(_key(screenId, '_hidden'), hidden.toList());
  }
  Future<Set<String>> loadHiddenColumns(String screenId) async {
    await _ensureInitialized();
    return Set.from(_prefs!.getStringList(_key(screenId, '_hidden')) ?? []);
  }

  // Закрепление
  Future<void> saveFrozen(String screenId, String field, String frozen) async {
    await _ensureInitialized();
    Map<String, String> frozenMap = await loadAllFrozen(screenId);
    if (frozen == 'none') frozenMap.remove(field);
    else frozenMap[field] = frozen;
    await _prefs!.setString(_key(screenId, '_frozen'), json.encode(frozenMap));
  }
  Future<Map<String, String>> loadAllFrozen(String screenId) async {
    await _ensureInitialized();
    final str = _prefs!.getString(_key(screenId, '_frozen'));
    if (str == null) return {};
    try { return Map<String, String>.from(json.decode(str)); } catch(_) { return {}; }
  }

  // Методы агрегации
  Future<void> saveAggregationMethod(String screenId, String field, String method) async {
    await _ensureInitialized();
    Map<String, String> methods = await loadAllAggMethods(screenId);
    if (method == 'none') methods.remove(field);
    else methods[field] = method;
    await _prefs!.setString(_key(screenId, '_aggr'), json.encode(methods));
  }
  Future<Map<String, String>> loadAllAggMethods(String screenId) async {
    await _ensureInitialized();
    final str = _prefs!.getString(_key(screenId, '_aggr'));
    if (str == null) return {};
    try { return Map<String, String>.from(json.decode(str)); } catch(_) { return {}; }
  }

  // Режим отображения статистики (sum, count, avg, max, min)
  Future<void> saveDisplayMode(String screenId, String field, String mode) async {
    await _ensureInitialized();
    Map<String, String> modes = await loadAllDisplayModes(screenId);
    modes[field] = mode;
    await _prefs!.setString(_key(screenId, '_display'), json.encode(modes));
  }
  Future<Map<String, String>> loadAllDisplayModes(String screenId) async {
    await _ensureInitialized();
    final str = _prefs!.getString(_key(screenId, '_display'));
    if (str == null) return {};
    try { return Map<String, String>.from(json.decode(str)); } catch(_) { return {}; }
  }

  // Поля для графика
  Future<void> saveChartFields(String screenId, List<String> fields) async {
    await _ensureInitialized();
    await _prefs!.setStringList(_key(screenId, '_chart_fields'), fields);
  }
  Future<List<String>> loadChartFields(String screenId) async {
    await _ensureInitialized();
    return _prefs!.getStringList(_key(screenId, '_chart_fields')) ?? [];
  }

  // Выбранная дата-колонка для графика
  Future<void> saveChartDateColumn(String screenId, String column) async {
    await _ensureInitialized();
    await _prefs!.setString(_key(screenId, '_chart_date'), column);
  }
  Future<String> loadChartDateColumn(String screenId) async {
    await _ensureInitialized();
    return _prefs!.getString(_key(screenId, '_chart_date')) ?? '';
  }

  // Видимость панели графика
  Future<void> saveChartVisible(String screenId, bool visible) async {
    await _ensureInitialized();
    await _prefs!.setBool(_key(screenId, '_chart_visible'), visible);
  }
  Future<bool> loadChartVisible(String screenId) async {
    await _ensureInitialized();
    return _prefs!.getBool(_key(screenId, '_chart_visible')) ?? false;
  }

  // Условное форматирование
  Future<void> saveConditionalFormatting(String screenId, String field, String scheme) async {
    await _ensureInitialized();
    Map<String, String> schemes = await loadAllConditionalFormatting(screenId);
    if (scheme == 'off') schemes.remove(field);
    else schemes[field] = scheme;
    await _prefs!.setString(_key(screenId, '_cond_format'), json.encode(schemes));
  }

  Future<Map<String, String>> loadAllConditionalFormatting(String screenId) async {
    await _ensureInitialized();
    final str = _prefs!.getString(_key(screenId, '_cond_format'));
    if (str == null) return {};
    try { return Map<String, String>.from(json.decode(str)); } catch(_) { return {}; }
  }

  // Сброс всех настроек
  Future<void> clearAll(String screenId) async {
    await _ensureInitialized();
    for (final key in [
      _key(screenId, '_order'),
      _key(screenId, '_hidden'),
      _key(screenId, '_frozen'),
      _key(screenId, '_aggr'),
      _key(screenId, '_display'),
      _key(screenId, '_chart_fields'),
      _key(screenId, '_chart_date'),
      _key(screenId, '_chart_visible'),
      _key(screenId, '_cond_format'),
      _key(screenId, '_row_height_offset'), // новый ключ
    ]) {
      await _prefs!.remove(key);
      await _prefs!.remove(_key(screenId, _keyHeaderHeightOffset));
    }
  }

  // Сохранение ширины колонок
  Future<void> saveColumnWidths(String screenId, Map<String, double> widths) async {
    await _ensureInitialized();
    final jsonStr = json.encode(widths.map((k, v) => MapEntry(k, v)));
    await _prefs!.setString(_key(screenId, '_widths'), jsonStr);
  }
  Future<Map<String, double>> loadColumnWidths(String screenId) async {
    await _ensureInitialized();
    final str = _prefs!.getString(_key(screenId, '_widths'));
    if (str == null) return {};
    try {
      final map = Map<String, dynamic>.from(json.decode(str));
      return map.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch(_) { return {}; }
  }

  // Высота строк (смещение относительно базовой 30)
  Future<void> saveRowHeightOffset(String screenId, int offset) async {
    await _ensureInitialized();
    await _prefs!.setInt(_key(screenId, '_row_height_offset'), offset);
  }

  Future<int> loadRowHeightOffset(String screenId) async {
    await _ensureInitialized();
    return _prefs!.getInt(_key(screenId, '_row_height_offset')) ?? 0;
  }
}

// ============================================================================
// 3. Статистика для колонки (расширена)
// ============================================================================

class ColumnStatistics {
  final String field;
  String displayName;
  double sum = 0.0;
  double avg = 0.0;
  double max = 0.0;
  double min = 0.0;
  int count = 0;
  int numericCount = 0;
  String displayMode = 'sum'; // sum, count, avg, max, min
  bool isAggregatedFromDB = false;

  ColumnStatistics(this.field, {this.displayName = ''});

  void updateFromRows(List<PlutoRow> rows, bool isNumeric) {
    sum = 0; avg = 0; max = 0; min = 0; count = 0; numericCount = 0;
    if (!isNumeric) return;
    for (final row in rows) {
      final cell = row.cells[field];
      if (cell?.value is num) {
        final val = (cell!.value as num).toDouble();
        sum += val;
        numericCount++;
        if (numericCount == 1) { max = val; min = val; }
        else { if (val > max) max = val; if (val < min) min = val; }
      }
      if (cell?.value != null) count++;
    }
    if (numericCount > 0) avg = sum / numericCount;
  }

  void updateFromTotals(Map<String, dynamic> totals) {
    isAggregatedFromDB = true;
    sum = (totals['sum_$field'] ?? 0.0).toDouble();
    avg = (totals['avg_$field'] ?? 0.0).toDouble();
    max = (totals['max_$field'] ?? 0.0).toDouble();
    min = (totals['min_$field'] ?? 0.0).toDouble();
    count = (totals['count_$field'] ?? 0) as int;
    numericCount = count;
  }

  String getFormattedValue() {
    if (numericCount == 0) return '';
    double v;
    switch (displayMode) {
      case 'sum': v = sum; break;
      case 'count': return NumberFormat('#,###', 'ru_RU').format(count);
      case 'avg': v = avg; break;
      case 'max': v = max; break;
      case 'min': v = min; break;
      default: return '';
    }
    if (v == 0) return '';
    return NumberFormat('#,###', 'ru_RU').format(v.round());
  }

  String getSymbol() {
    switch (displayMode) {
      case 'sum': return 'Σ';
      case 'count': return 'n';
      case 'avg': return 'x̄';
      case 'max': return '▲';
      case 'min': return '▼';
      default: return '';
    }
  }

  void cycleMode() {
    const modes = ['sum', 'count', 'avg', 'max', 'min'];
    displayMode = modes[(modes.indexOf(displayMode) + 1) % modes.length];
  }

  Color getModeColor() {
    if (!isAggregatedFromDB) return Colors.grey;
    switch (displayMode) {
      case 'sum': return Colors.blue;
      case 'count': return Colors.green;
      case 'avg': return Colors.orange;
      case 'max': return Colors.red;
      case 'min': return Colors.purple;
      default: return Colors.grey;
    }
  }
}


class UniversalDataTableController {
  VoidCallback? _showSettings;
  VoidCallback? _showCustomColumnDialog;
  VoidCallback? _refreshData;
  VoidCallback? _clearFilters;

  void showSettingsDialog() => _showSettings?.call();
  void showCustomColumnManagementDialog() => _showCustomColumnDialog?.call();
  void refreshData() => _refreshData?.call();
  void clearFilters() => _clearFilters?.call();

  void _attach(
      VoidCallback showSettings,
      VoidCallback showCustomColumnDialog,
      VoidCallback refreshData,
      VoidCallback clearFilters,
      ) {
    _showSettings = showSettings;
    _showCustomColumnDialog = showCustomColumnDialog;
    _refreshData = refreshData;
    _clearFilters = clearFilters;
  }

  void _detach() {
    _showSettings = null;
    _showCustomColumnDialog = null;
    _refreshData = null;
    _clearFilters = null;
  }
}


// ============================================================================
// 4. Основной виджет универсальной таблицы (с кастомным ресайзом)
// ============================================================================

class UniversalDataTable<T> extends StatefulWidget {
  final String screenId;
  final DataProvider<T> provider;
  final List<ColumnDefinition> columns;
  final Map<String, dynamic> Function(T item)? toMap;
  final T Function(Map<String, dynamic>)? fromMap;
  final Map<String, Widget Function(PlutoRow row)>? customCellBuilders;
  final HeaderFeaturesConfig headerFeatures;
  final UniversalDataTableController? controller;
  final Widget Function(BuildContext context, UniversalDataTableController controller)? toolbarBuilder;

  const UniversalDataTable({
    Key? key,
    required this.screenId,
    required this.provider,
    required this.columns,
    this.toMap,
    this.fromMap,
    this.customCellBuilders,
    this.headerFeatures = const HeaderFeaturesConfig(),
    this.controller,
    this.toolbarBuilder,
  }) : super(key: key);

  @override
  UniversalDataTableState<T> createState() => UniversalDataTableState<T>();
}

class UniversalDataTableState<T> extends State<UniversalDataTable<T>> {
  late PlutoGridStateManager _stateManager;
  late List<PlutoColumn> _plutoColumns;
  Map<String, ColumnStatistics> _statsMap = {};
  List<PlutoRow> _visibleRows = [];
  // Хранилище соответствия строк и исходных объектов
  final Map<PlutoRow, T> _rowToItem = {};
  late UniversalDataTableController _effectiveController;
  bool _isLoading = false;
  int _totalRecords = 0;
  int _currentOffset = 0;
  final int _pageSize = 50;
  bool _hasMore = false;
  FilterSet _filters = FilterSet();
  String? _sortField;
  bool _sortDesc = true;
  List<String>? _pendingOrder;
  bool _isSettingsLoaded = false;
  double _headerHeight = 0; // динамическая высота
  /// int _sortKey = 0; /// todo: убрали из-за перерисовки таблицы
  /// int _filterKey = 0; /// todo: убрали из-за перерисовки таблицы
  ///
  List<Map<String, dynamic>> _templates = [];

  // Группировка и агрегация
  String? _groupByField;
  Map<String, String> _aggregationMethods = {};
  bool _isGroupingMode = false;

  // Кастомные колонки
  List<CustomColumn> _customColumns = [];

  // График
  bool _isChartVisible = false;
  String _selectedDateColumn = '';
  List<String> _selectedChartFields = [];
  Map<String, Color> _fieldToColor = {};
  Map<String, List<FlSpot>> _chartSpots = {};
  bool _isChartLoading = false;

  // Настройки
  Set<String> _hiddenFields = {};
  int _rebuildKey = 0;
  bool _ignoreNextColumnMove = false;
  DateTime? _lastAppliedOrderTime;
  DateTime? _lastSavedTime;

  // Условное форматирование
  Map<String, String> _conditionalFormatting = {};

  // Высота строк (смещение относительно базовой 30)
  int _rowHeightOffset = 0;
  int _headerHeightOffset = 0;

  bool _allCheckedOnPage = false;
  bool _someCheckedOnPage = false;

  // Палитра цветов для графика
  static const List<Color> _chartPalette = [
    Colors.red, Colors.blue, Colors.green, Colors.orange, Colors.purple,
    Colors.pink, Colors.teal, Colors.brown, Colors.cyan,
  ];

  // Методы агрегации для меню
  final Map<String, String> _aggregationMethodsMap = {
    'none': 'Не агрегировать',
    'sum': 'Сумма',
    'avg': 'Среднее',
    'count_unique': 'Уникальных',
    'concat': 'Склеить',
    'first_non_empty': 'Первое непустое',
    'max': 'Максимум',
    'min': 'Минимум',
  };

  late Map<String, ColumnDefinition> _colDefMap;

  // Для кастомного ресайза
  PlutoColumn? _resizingColumn;
  double _resizeStartX = 0;
  double _resizeStartWidth = 0;

  // Стандартные отступы для ячеек
  static const EdgeInsets _defaultCellPadding = EdgeInsets.all(2);

  @override
  void initState() {
    super.initState();
    _effectiveController = widget.controller ?? UniversalDataTableController();
    _colDefMap = {for (var c in widget.columns) c.field: c};
    _loadTemplatesForScreen(widget.screenId).then((templates) {
      if (mounted) setState(() => _templates = templates);
    });
    _loadSettingsAndInit();
  }

  Future<void> _loadSettingsAndInit() async {
    await _loadSettings();
    if (mounted) {
      setState(() {
        _isSettingsLoaded = true;
        _initColumns();
        _headerHeight = _calculateHeaderHeight();
        _loadFirstPage();
        _effectiveController._attach(
          _showSettingsDialog,
          _showCustomColumnManagementDialog,
          _loadFirstPage,
          _clearFiltersAndRefresh,
        );
      });
    }
  }

  // В UniversalDataTableState добавить:

  void setSort(String field, {bool descending = false}) {
    final timestamp = DateTime.now().toIso8601String();
    print('[$timestamp] setSort called: field=$field, descending=$descending, current _sortField=$_sortField, _sortDesc=$_sortDesc');

    // Убираем условие if (_sortField == field && _sortDesc == descending) return;
    // Теперь всегда выполняем перезагрузку

    setState(() {
      _sortField = field;
      _sortDesc = descending;
    });
    print('[$timestamp] setSort: новое состояние, вызываем _loadFirstPage');
    _loadFirstPage();
    _updateAllColumnTitles();
  }

  void clearSort() {
    final timestamp = DateTime.now().toIso8601String();
    print('[$timestamp] clearSort called, current _sortField=$_sortField');
    if (_sortField == null) return;
    setState(() {
      _sortField = null;
      _sortDesc = true;
    });
    _loadFirstPage();
    _updateAllColumnTitles();
  }

  void _updateCheckboxHeaderState() {
    if (_visibleRows.isEmpty) {
      _allCheckedOnPage = false;
      _someCheckedOnPage = false;
      return;
    }
    int checkedCount = _visibleRows.where((row) => row.checked == true).length;
    _allCheckedOnPage = checkedCount == _visibleRows.length;
    _someCheckedOnPage = checkedCount > 0 && checkedCount < _visibleRows.length;
    if (mounted) setState(() {});
  }

  void _toggleSelectAllOnPage(bool? selectAll) {
    if (selectAll == null) return;
    for (var row in _visibleRows) {
      row.setChecked(selectAll);
    }
    if (_stateManager != null) {
      _stateManager.notifyListeners();
    }
    _updateCheckboxHeaderState();
  }

  Future<List<Map<String, dynamic>>> _loadTemplatesForScreen(String screenId) async {
    try {
      final jsonString = await rootBundle.loadString('assets/default_custom_columns_universal.json');
      final Map<String, dynamic> allTemplates = json.decode(jsonString);
      final List<dynamic> screenTemplates = allTemplates[screenId] ?? [];
      return screenTemplates.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('⚠️ Ошибка загрузки шаблонов для экрана $screenId: $e');
      return [];
    }
  }

  Future<void> _loadSettings() async {
    _hiddenFields = await TableSettingsService.instance.loadHiddenColumns(widget.screenId);

    final order = await TableSettingsService.instance.loadColumnOrder(widget.screenId);
    if (order != null && order.isNotEmpty) {
      _pendingOrder = order;
    }

    _aggregationMethods = await TableSettingsService.instance.loadAllAggMethods(widget.screenId);

    final displayModes = await TableSettingsService.instance.loadAllDisplayModes(widget.screenId);
    for (var entry in displayModes.entries) {
      if (_statsMap.containsKey(entry.key)) {
        _statsMap[entry.key]!.displayMode = entry.value;
      }
    }

    _isChartVisible = await TableSettingsService.instance.loadChartVisible(widget.screenId);
    _selectedDateColumn = await TableSettingsService.instance.loadChartDateColumn(widget.screenId);
    final savedChartFields = await TableSettingsService.instance.loadChartFields(widget.screenId);
    if (savedChartFields.isNotEmpty) {
      _selectedChartFields = savedChartFields;
      for (int i = 0; i < _selectedChartFields.length; i++) {
        _fieldToColor[_selectedChartFields[i]] = _chartPalette[i % _chartPalette.length];
      }
    }

    // Условное форматирование
    _conditionalFormatting = await TableSettingsService.instance.loadAllConditionalFormatting(widget.screenId);

    // Загрузка сохранённых ширин колонок
    final savedWidths = await TableSettingsService.instance.loadColumnWidths(widget.screenId);
    for (var def in widget.columns) {
      if (savedWidths.containsKey(def.field)) {
        def.width = savedWidths[def.field]!;
      }
    }

    // Высота строк
    _rowHeightOffset = await TableSettingsService.instance.loadRowHeightOffset(widget.screenId);
    _headerHeightOffset = await TableSettingsService.instance.loadHeaderHeightOffset(widget.screenId);

    if (widget.screenId == 'supplies_new' && _headerHeightOffset == 0) {
      _headerHeightOffset = 10;
      await TableSettingsService.instance.saveHeaderHeightOffset(widget.screenId, _headerHeightOffset);
    }

    await _loadCustomColumns();
  }

  Future<void> _loadCustomColumns() async {
    final custom = await widget.provider.getCustomColumns();
    if (mounted) {
      setState(() {
        _customColumns = custom;
        _initColumns();
        if (_pendingOrder != null && _pendingOrder!.isNotEmpty) {
          _reorderColumns(_pendingOrder!);
          _pendingOrder = null;
        }
      });
    }
  }

  void _reorderColumns(List<String> order) {
    final validOrder = order.where((field) =>
        _plutoColumns.any((col) => col.field == field)
    ).toList();

    final ordered = <PlutoColumn>[];
    for (var field in validOrder) {
      final col = _plutoColumns.firstWhereOrNull((c) => c.field == field);
      if (col != null) ordered.add(col);
    }
    for (var col in _plutoColumns) {
      if (!ordered.contains(col)) ordered.add(col);
    }
    _plutoColumns = ordered;
    _rebuildKey++;
  }

  void _initColumns() {
    // 1. Сначала заполняем _colDefMap базовыми колонками
    _colDefMap = {for (var c in widget.columns) c.field: c};

    // 2. Добавляем определения для кастомных колонок
    for (var custom in _customColumns) {
      _colDefMap[custom.name] = ColumnDefinition(
        field: custom.name,
        title: custom.displayName,
        dataType: ColumnDataType.number,
        isAggregatable: true,
        isGroupable: false,
        width: 68,
      );
    }

    // 3. Теперь создаём PlutoColumn для каждой колонки из _colDefMap
    _plutoColumns = [];
    _statsMap = {};
    for (var def in _colDefMap.values) {
      final stats = ColumnStatistics(def.field, displayName: def.title);
      _statsMap[def.field] = stats;
      final col = _buildPlutoColumn(def, stats);
      _plutoColumns.add(col);
    }

    if (_selectedDateColumn.isEmpty) {
      final dateField = widget.columns.firstWhere(
            (c) => c.dataType == ColumnDataType.date,
        orElse: () => widget.columns.first,
      ).field;
      _selectedDateColumn = dateField;
    }
  }

  PlutoColumn _buildPlutoColumn(ColumnDefinition def, ColumnStatistics stats) {
    return PlutoColumn(
      title: '',
      field: def.field,
      type: _mapColumnType(def),
      width: def.width,
      minWidth: def.minWidth,
      enableContextMenu: false,
      enableSorting: false,
      enableFilterMenuItem: false,
      enableDropToResize: false,  // отключаем стандартный ресайз
      enableColumnDrag: false,
      titleSpan: _buildTitleSpan(def.field, stats, null),
      renderer: (ctx) => _buildCellRenderer(ctx, def),
      formatter: (val) => _formatValue(val, def),
      cellPadding: def.cellPadding as EdgeInsets? ?? _defaultCellPadding,
    );
  }

  PlutoColumnType _mapColumnType(ColumnDefinition def) {
    switch (def.dataType) {
      case ColumnDataType.number:
      case ColumnDataType.currency:
      case ColumnDataType.percent:
        return PlutoColumnType.number();
      case ColumnDataType.date:
        return PlutoColumnType.date();
      case ColumnDataType.checkbox:
        return PlutoColumnType.text(); // тип не важен, свой рендерер
      default:
        return PlutoColumnType.text();
    }
  }

  Widget _buildCellRenderer(PlutoColumnRendererContext ctx, ColumnDefinition def) {
    if (def.dataType == ColumnDataType.checkbox) {
      return Center(
        child: Checkbox(
          value: ctx.row.checked,
          onChanged: (value) {
            ctx.row.setChecked(value ?? false);
            _stateManager?.notifyListeners();
            _updateCheckboxHeaderState();
          },
        ),
      );
    }
    final val = ctx.cell.value;
    final customBuilder = widget.customCellBuilders?[def.field];
    if (customBuilder != null) {
      return customBuilder(ctx.row);
    }
    if (val == null) return const SizedBox.shrink();
    if (val is num && val == 0) return const SizedBox.shrink();

    Color textColor = Colors.black;
    final formatted = _formatValue(val, def);
    final conditionalTextColor = _getConditionalTextColor(def.field, val, _statsMap[def.field]);
    if (conditionalTextColor != null) textColor = conditionalTextColor;

    final textWidget = Text(
      formatted,
      style: TextStyle(fontSize: 14, color: textColor),
    );

    // Проверяем, является ли колонка кастомной
    final bool isCustomColumn = _customColumns.any((c) => c.name == def.field);
    final alignment = isCustomColumn ? Alignment.center : Alignment.centerLeft;

    final padding = def.cellPadding ?? _defaultCellPadding;
    return Padding(
      padding: padding,
      child: Align(
        alignment: alignment,
        child: textWidget,
      ),
    );
  }

  String _formatValue(dynamic value, ColumnDefinition def) {
    if (def.dataType == ColumnDataType.checkbox) return '';
    if (value == null) return '';
    if (value is num) {
      if (value == 0) return '';
      switch (def.dataType) {
        case ColumnDataType.currency:
          return NumberFormat('#,##0.00', 'ru_RU').format(value);
        case ColumnDataType.percent:
          return NumberFormat('#,##0.00', 'ru_RU').format(value) + '%';
        case ColumnDataType.number:
          return NumberFormat('#,###', 'ru_RU').format(value);
        default:
          return value.toString();
      }
    }
    if (value is DateTime) {
      return DateFormat('dd.MM.yyyy').format(value);
    }
    return value.toString();
  }

  // ========================================================================
  // Условное форматирование
  // ========================================================================

  Color? _getConditionalTextColor(String field, dynamic value, ColumnStatistics? stats) {
    final scheme = _conditionalFormatting[field];
    if (scheme == null || scheme == 'off') return null;
    if (value is! num) return null;
    if (stats == null || stats.numericCount == 0) return null;
    final minVal = stats.min;
    final maxVal = stats.max;
    if (minVal == maxVal) return null; // нет диапазона

    final t = ((value - minVal) / (maxVal - minVal)).clamp(0.0, 1.0);

    switch (scheme) {
      case 'green-yellow-red':
        if (t <= 0.5) return Color.lerp(Colors.green, Colors.yellow, t * 2);
        else return Color.lerp(Colors.yellow, Colors.red, (t - 0.5) * 2);
      case 'red-yellow-green':
        if (t <= 0.5) return Color.lerp(Colors.red, Colors.yellow, t * 2);
        else return Color.lerp(Colors.yellow, Colors.green, (t - 0.5) * 2);
      case 'white-green':
        return Color.lerp(Colors.black, Colors.green, t);
      case 'green-white':
        return Color.lerp(Colors.green, Colors.black, t);
      case 'white-red':
        return Color.lerp(Colors.black, Colors.red, t);
      case 'red-white':
        return Color.lerp(Colors.red, Colors.black, t);
      default:
        return null;
    }
  }

  // ========================================================================
  // КАСТОМНЫЙ РЕСАЙЗ – ОБРАБОТЧИКИ
  // ========================================================================

  void _startResize(PlutoColumn column, Offset globalPosition) {
    _resizingColumn = column;
    _resizeStartX = globalPosition.dx;
    _resizeStartWidth = column.width;
  }

  void _updateResize(Offset globalPosition) {
    if (_resizingColumn == null) return;
    final delta = globalPosition.dx - _resizeStartX;
    double newWidth = (_resizeStartWidth + delta).clamp(
      _resizingColumn!.minWidth,
      double.infinity,
    );
    if (newWidth == _resizingColumn!.width) return;
    _resizingColumn!.width = newWidth;
    // Обновляем ширину в исходном определении для сохранения
    final def = _colDefMap[_resizingColumn!.field];
    if (def != null) def.width = newWidth;
    _stateManager?.notifyListeners();
  }

  void _endResize() async {
    if (_resizingColumn == null) return;
    // Сохраняем новую ширину
    final widths = <String, double>{};
    for (var col in _plutoColumns) {
      widths[col.field] = col.width;
    }
    await TableSettingsService.instance.saveColumnWidths(widget.screenId, widths);
    _resizingColumn = null;
  }

  // ========================================================================
  // ВСПОМОГАТЕЛЬНЫЙ МЕТОД ДЛЯ ВЫСОТЫ ЗАГОЛОВКА
  // ========================================================================
  double _getHeaderHeight() {
    return _headerHeight;
  }

  // ========================================================================
  // РАСЧЁТ ВЫСОТЫ ЗАГОЛОВКА НА ОСНОВЕ КОНФИГУРАЦИИ
  // ========================================================================
  double _calculateHeaderHeight() {
    final double rowHeight = universalDataTableHeaderIconSize + 12 + _headerHeightOffset;
    const double marginBottom = 4; // отступ после блока статистики
    const double extraPadding = 4; // верхний отступ (SizedBox(height:4) в начале)

    int visibleRows = 0;

    // Строка статистики (значение)
    if (widget.headerFeatures.showStatistics) visibleRows++;

    // Строка "символ статистики + меню"
    if (widget.headerFeatures.showStatistics || widget.headerFeatures.showMenu) visibleRows++;

    // Строка "агрегация + график"
    if (widget.headerFeatures.showAggregation || widget.headerFeatures.showChart) visibleRows++;

    // Строка "сортировка + фильтр"
    if (widget.headerFeatures.showSort || widget.headerFeatures.showFilter) visibleRows++;

    // Разделитель и тип данных
    if (widget.headerFeatures.showDataTypeAndDivider) {
      visibleRows++; // первый разделитель
      visibleRows++; // тип данных
    }

    // Разделитель и название
    if (widget.headerFeatures.showTitleAndDivider) {
      visibleRows++; // второй разделитель
      visibleRows++; // название
    }

    // Высота = количество строк * высота строки + отступы
    return visibleRows * rowHeight + marginBottom + extraPadding;
  }

  void _saveHeaderHeightOffset(int offset) {
    TableSettingsService.instance.saveHeaderHeightOffset(widget.screenId, offset);
  }

  // ========================================================================
  // КАСТОМНЫЙ ЗАГОЛОВОК С ПОЛЗУНКОМ И ПРИЖАТИЕМ К ВЕРХУ
  // ========================================================================

  Widget _buildResizeHandle(String field, PlutoColumn? column) {
    if (column == null) return const SizedBox.shrink();
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) => _startResize(column, event.position),
        onPointerMove: (event) => _updateResize(event.position),
        onPointerUp: (event) => _endResize(),
        child: Container(
          width: 5,
          height: double.infinity,
          color: Colors.transparent,
        ),
      ),
    );
  }

  InlineSpan _buildTitleSpan(String field, ColumnStatistics? stats, PlutoColumn? column) {
    final def = _colDefMap[field] ?? ColumnDefinition(field: field, title: field, dataType: ColumnDataType.text);
    final hasFilter = _filters.hasFilter(field);
    final isSorted = _sortField == field;
    final sortIcon = isSorted ? (_sortDesc ? Icons.arrow_downward : Icons.arrow_upward) : Icons.sort;
    final aggregationMethod = _aggregationMethods[field] ?? 'none';
    final isChartField = _selectedChartFields.contains(field);
    final isCustom = _customColumns.any((c) => c.name == field);

    final double containerSize = universalDataTableHeaderIconSize + 12;

    final List<Widget> children = [];

    // 1. Блок статистики (значение) – проверяем флаг колонки
    if (widget.headerFeatures.showStatistics && def.showStatistics && stats != null) {
      children.add(
        GestureDetector(
          onTap: () {
            setState(() {
              stats.cycleMode();
              _updateAllColumnTitles();
            });
            TableSettingsService.instance.saveDisplayMode(widget.screenId, field, stats.displayMode);
          },
          child: Container(
            width: containerSize * 2 + 8,
            height: containerSize,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: stats.getModeColor().withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: stats.getModeColor().withOpacity(0.3)),
            ),
            child: Center(
              child: AutoSizeText(
                stats.getFormattedValue(),
                maxLines: 1,
                minFontSize: 6,
                maxFontSize: 14,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      );
    }

    // 👇 НОВЫЙ БЛОК – заголовок для чекбокс-колонки (только чекбокс + меню)
    if (def.dataType == ColumnDataType.checkbox) {
      final containerSize = universalDataTableHeaderIconSize + 12;
      return WidgetSpan(
        child: SizedBox(
          height: _headerHeight,
          child: Align(
            alignment: Alignment.topCenter,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 4),
                      // Чекбокс "выбрать все"
                      Checkbox(
                        value: _someCheckedOnPage ? null : _allCheckedOnPage,
                        tristate: true,
                        onChanged: _toggleSelectAllOnPage,
                      ),
                      const SizedBox(height: 8),
                      // Меню (три точки)
                      PopupMenuButton<dynamic>(
                        itemBuilder: (context) => _buildColumnMenuItems(
                          field,
                          column,
                          isCustom: _customColumns.any((c) => c.name == field),
                        ),
                        onSelected: (value) => _handleColumnMenuSelection(field, value, column),
                        child: Container(
                          width: containerSize,
                          height: containerSize,
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.withOpacity(0.3)),
                          ),
                          child: Center(
                            child: Icon(Icons.menu, size: universalDataTableHeaderIconSize),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildResizeHandle(field, column),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 2. Строка: символ статистики + меню
    final rowStatsAndMenu = <Widget>[];
    if (widget.headerFeatures.showStatistics && def.showStatistics && stats != null) {
      rowStatsAndMenu.add(
        GestureDetector(
          onTap: () {
            setState(() {
              stats.cycleMode();
              _updateAllColumnTitles();
            });
            TableSettingsService.instance.saveDisplayMode(widget.screenId, field, stats.displayMode);
          },
          child: Container(
            width: containerSize,
            height: containerSize,
            decoration: BoxDecoration(
              color: stats.getModeColor().withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: stats.getModeColor().withOpacity(0.3)),
            ),
            child: Center(
              child: Text(
                stats.getSymbol(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      );
    }
    if (widget.headerFeatures.showMenu) {
      if (rowStatsAndMenu.isNotEmpty) rowStatsAndMenu.add(const SizedBox(width: 6));
      rowStatsAndMenu.add(
        PopupMenuButton<dynamic>(
          itemBuilder: (context) => _buildColumnMenuItems(field, column, isCustom: isCustom),
          onSelected: (value) => _handleColumnMenuSelection(field, value, column),
          child: Container(
            width: containerSize,
            height: containerSize,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
            ),
            child: Center(child: Icon(Icons.menu, size: universalDataTableHeaderIconSize)),
          ),
        ),
      );
    }
    if (rowStatsAndMenu.isNotEmpty) {
      children.add(Row(mainAxisAlignment: MainAxisAlignment.center, children: rowStatsAndMenu));
      children.add(const SizedBox(height: 4));
    }

    // 3. Строка: агрегация + график – проверяем флаги колонки
    final rowAggAndChart = <Widget>[];
    if (widget.headerFeatures.showAggregation && def.showAggregation) {
      rowAggAndChart.add(
        PopupMenuButton<String>(
          itemBuilder: (context) => _buildAggregationMenuItems(field),
          onSelected: (value) => _handleAggregationSelection(field, value),
          offset: const Offset(0, 40),
          child: Container(
            width: containerSize,
            height: containerSize,
            decoration: BoxDecoration(
              color: aggregationMethod != 'none' ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: aggregationMethod != 'none' ? Colors.green.withOpacity(0.5) : Colors.grey.withOpacity(0.3)),
            ),
            child: Center(
              child: Icon(Icons.group_work, size: universalDataTableHeaderIconSize, color: aggregationMethod != 'none' ? Colors.green : Colors.black),
            ),
          ),
        ),
      );
    }
    if (widget.headerFeatures.showChart && def.showChart) {
      if (rowAggAndChart.isNotEmpty) rowAggAndChart.add(const SizedBox(width: 8));
      rowAggAndChart.add(
        GestureDetector(
          onTap: () {
            setState(() {
              _isChartVisible = true;
            });
            _toggleChartField(field);
          },
          child: Container(
            width: containerSize,
            height: containerSize,
            decoration: BoxDecoration(
              color: isChartField ? _fieldToColor[field]?.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isChartField ? (_fieldToColor[field] ?? Colors.grey) : Colors.grey.withOpacity(0.3)),
            ),
            child: Center(
              child: Icon(Icons.show_chart, size: universalDataTableHeaderIconSize, color: isChartField ? (_fieldToColor[field] ?? Colors.grey) : Colors.grey[700]),
            ),
          ),
        ),
      );
    }
    if (rowAggAndChart.isNotEmpty) {
      children.add(Row(mainAxisAlignment: MainAxisAlignment.center, children: rowAggAndChart));
      children.add(const SizedBox(height: 4));
    }

    // 4. Строка: сортировка + фильтр – проверяем флаги колонки
    final rowSortAndFilter = <Widget>[];
    if (widget.headerFeatures.showSort && def.showSort) {
      rowSortAndFilter.add(
        GestureDetector(
          onTap: () => _toggleSort(field),
          child: Container(
            width: containerSize,
            height: containerSize,
            decoration: BoxDecoration(
              color: isSorted ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isSorted ? Colors.green.withOpacity(0.5) : Colors.grey.withOpacity(0.3)),
            ),
            child: Center(
              child: Icon(sortIcon, size: universalDataTableHeaderIconSize, color: isSorted ? Colors.green : Colors.grey[700]),
            ),
          ),
        ),
      );
    }
    if (widget.headerFeatures.showFilter && def.showFilter) {
      if (rowSortAndFilter.isNotEmpty) rowSortAndFilter.add(const SizedBox(width: 8));
      rowSortAndFilter.add(
        GestureDetector(
          onTapDown: (details) => _showFilterPopup(field, details.globalPosition),
          child: Container(
            width: containerSize,
            height: containerSize,
            decoration: BoxDecoration(
              color: hasFilter ? Colors.blue.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: hasFilter ? Colors.blue.withOpacity(0.5) : Colors.grey.withOpacity(0.3)),
            ),
            child: Center(
              child: Icon(Icons.filter_alt, size: universalDataTableHeaderIconSize, color: hasFilter ? Colors.blue : Colors.grey[700]),
            ),
          ),
        ),
      );
    }
    if (rowSortAndFilter.isNotEmpty) {
      children.add(Row(mainAxisAlignment: MainAxisAlignment.center, children: rowSortAndFilter));
      children.add(const SizedBox(height: 4));
    }

    // 5. Разделитель и тип данных – проверяем флаг колонки
    if (widget.headerFeatures.showDataTypeAndDivider && def.showDataType) {
      children.add(_buildFadingDivider());
      children.add(_buildTypeLabel(field));
      children.add(_buildFadingDivider());
    }

    // 6. Название колонки – с возможностью скрыть текст, но оставить draggable
    if (widget.headerFeatures.showTitleAndDivider) {
      // Добавляем разделитель, если тип данных отключен или разделитель ещё не добавлен
      if (!widget.headerFeatures.showDataTypeAndDivider || !def.showDataType) {
        children.add(_buildFadingDivider());
      }

      if (!def.hideTitle) {
        // Видимое название с перетаскиванием
        if (column != null) {
          children.add(
            MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Draggable<PlutoColumn>(
                data: column,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: PlutoShadowContainer(
                    alignment: Alignment.center,
                    width: PlutoGridSettings.minColumnWidth,
                    height: _stateManager.columnHeight,
                    backgroundColor: _stateManager.configuration.style.gridBackgroundColor,
                    borderColor: _stateManager.configuration.style.gridBorderColor,
                    child: Text(
                      def.title,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: AutoSizeText(
                    def.title,
                    maxLines: 5,
                    minFontSize: 7,
                    maxFontSize: 13,
                    textAlign: TextAlign.center,
                    wrapWords: false,
                    overflowReplacement: Text(
                      def.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 8,
                        color: Colors.black,
                        fontWeight: FontWeight.normal,
                        height: 1.1,
                      ),
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.normal,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ),
          );
        } else {
          children.add(
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AutoSizeText(
                def.title,
                maxLines: 5,
                minFontSize: 7,
                maxFontSize: 13,
                textAlign: TextAlign.center,
                wrapWords: false,
                overflowReplacement: Text(
                  def.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 8,
                    color: Colors.black,
                    fontWeight: FontWeight.normal,
                    height: 1.1,
                  ),
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.normal,
                  height: 1.1,
                ),
              ),
            ),
          );
        }
      } else {
        // Название скрыто, но draggable остаётся для перетаскивания колонки
        if (column != null) {
          children.add(
            MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Draggable<PlutoColumn>(
                data: column,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: PlutoShadowContainer(
                    alignment: Alignment.center,
                    width: PlutoGridSettings.minColumnWidth,
                    height: _stateManager.columnHeight,
                    backgroundColor: _stateManager.configuration.style.gridBackgroundColor,
                    borderColor: _stateManager.configuration.style.gridBorderColor,
                    child: const SizedBox.shrink(),
                  ),
                ),
                child: Container(
                  width: double.infinity,
                  height: 20,
                  color: Colors.transparent,
                ),
              ),
            ),
          );
        } else {
          children.add(const SizedBox(height: 20));
        }
      }
    }

    // Верхний отступ
    children.insert(0, const SizedBox(height: 4));

    return WidgetSpan(
      child: SizedBox(
        height: _headerHeight,                     // ← вся высота заголовка
        child: Align(
          alignment: Alignment.topCenter,          // ← прижимаем к верху
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: children,
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: _buildResizeHandle(field, column),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFadingDivider() {
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.grey.withOpacity(0.3), Colors.transparent],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  Widget _buildTypeLabel(String field) {
    final def = _colDefMap[field];
    String typeLabel = '';
    if (def != null) {
      switch (def.dataType) {
        case ColumnDataType.number:
          typeLabel = '123';
          break;
        case ColumnDataType.currency:
          typeLabel = '₽';
          break;
        case ColumnDataType.percent:
          typeLabel = '%';
          break;
        case ColumnDataType.date:
          typeLabel = 'ДАТА';
          break;
        case ColumnDataType.text:
          typeLabel = 'ТЕКСТ';
          break;
        case ColumnDataType.checkbox:
          typeLabel = '☑'; // или оставить пустым
          break;
      }
    }
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Center(
        child: Text(
          typeLabel,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.grey[700]),
        ),
      ),
    );
  }

  List<PopupMenuEntry<dynamic>> _buildColumnMenuItems(String field, PlutoColumn? column, {required bool isCustom}) {
    if (column == null) return [];
    final isFrozenLeft = column.frozen == PlutoColumnFrozen.start;
    final isFrozenRight = column.frozen == PlutoColumnFrozen.end;
    final isHidden = column.hide;

    return [
      PopupMenuItem<dynamic>(
        value: 'freeze_left',
        child: Row(
          children: [
            Icon(Icons.pin_end, size: universalDataTableHeaderIconSize, color: isFrozenLeft ? Colors.blue : Colors.grey[700]),
            const SizedBox(width: 8),
            Text('Закрепить слева', style: TextStyle(color: isFrozenLeft ? Colors.blue : null)),
          ],
        ),
      ),
      PopupMenuItem<dynamic>(
        value: 'freeze_right',
        child: Row(
          children: [
            Icon(Icons.pin_end, size: universalDataTableHeaderIconSize, color: isFrozenRight ? Colors.blue : Colors.grey[700]),
            const SizedBox(width: 8),
            Text('Закрепить справа', style: TextStyle(color: isFrozenRight ? Colors.blue : null)),
          ],
        ),
      ),
      PopupMenuItem<dynamic>(
        value: 'unfreeze',
        enabled: isFrozenLeft || isFrozenRight,
        child: Row(
          children: [
            Icon(Icons.unfold_more, size: universalDataTableHeaderIconSize),
            const SizedBox(width: 8),
            const Text('Снять закрепление'),
          ],
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<dynamic>(
        value: 'toggle_hide',
        child: Row(
          children: [
            Icon(isHidden ? Icons.visibility : Icons.visibility_off, size: universalDataTableHeaderIconSize),
            const SizedBox(width: 8),
            Text(isHidden ? 'Показать столбец' : 'Скрыть столбец'),
          ],
        ),
      ),
      if (!isCustom)
        PopupMenuItem<dynamic>(
          value: 'show_all',
          child: Row(
            children: [
              Icon(Icons.view_column, size: universalDataTableHeaderIconSize),
              const SizedBox(width: 8),
              const Text('Показать все столбцы'),
            ],
          ),
        ),
      if (isCustom)
        PopupMenuItem<dynamic>(
          value: 'delete_custom',
          child: Row(
            children: [
              Icon(Icons.delete, size: universalDataTableHeaderIconSize, color: Colors.red[700]),
              const SizedBox(width: 8),
              Text('Удалить столбец', style: TextStyle(color: Colors.red[700])),
            ],
          ),
        ),
      const PopupMenuDivider(),
      // Условное форматирование – подменю
      PopupMenuItem<dynamic>(
        enabled: false,
        child: PopupMenuButton<String>(
          offset: const Offset(150, 0),
          child: Row(
            children: [
              Icon(Icons.format_color_text, size: universalDataTableHeaderIconSize),
              const SizedBox(width: 8),
              const Text('Условное форматирование'),
              const Spacer(),
              Icon(Icons.chevron_right, size: 16),
            ],
          ),
          itemBuilder: (context) => _buildConditionalFormattingItems(field),
          onSelected: (scheme) {
            _applyConditionalFormatting(field, scheme);
            Navigator.of(context).pop(); // закрываем основное меню
          },
        ),
      ),
    ];
  }

  List<PopupMenuItem<String>> _buildConditionalFormattingItems(String field) {
    final currentScheme = _conditionalFormatting[field] ?? 'off';
    final schemes = {
      'off': 'Выключено',
      'green-yellow-red': 'Зеленый → Желтый → Красный',
      'red-yellow-green': 'Красный → Желтый → Зеленый',
      'white-green': 'Белый → Зеленый',
      'green-white': 'Зеленый → Белый',
      'white-red': 'Белый → Красный',
      'red-white': 'Красный → Белый',
    };
    return schemes.entries.map((entry) {
      return PopupMenuItem<String>(
        value: entry.key,
        child: Row(
          children: [
            if (currentScheme == entry.key)
              Icon(Icons.check, size: 16, color: Colors.blue),
            const SizedBox(width: 8),
            Text(entry.value),
          ],
        ),
      );
    }).toList();
  }

  void _applyConditionalFormatting(String field, String scheme) {
    setState(() {
      if (scheme == 'off') _conditionalFormatting.remove(field);
      else _conditionalFormatting[field] = scheme;
    });
    TableSettingsService.instance.saveConditionalFormatting(widget.screenId, field, scheme);
    _stateManager?.notifyListeners();
  }

  void _handleColumnMenuSelection(String field, dynamic value, PlutoColumn? column) {
    if (column == null) return;

    switch (value) {
      case 'freeze_left':
        _freezeColumnLeft(column);
        break;
      case 'freeze_right':
        _freezeColumnRight(column);
        break;
      case 'unfreeze':
        _unfreezeColumn(column);
        break;
      case 'toggle_hide':
        _toggleHideColumn(column);
        break;
      case 'show_all':
        _showAllColumns();
        break;
      case 'delete_custom':
        _deleteCustomColumn(field);
        break;
    }
  }

  void _freezeColumnLeft(PlutoColumn column) {
    if (_stateManager != null) {
      _stateManager.toggleFrozenColumn(column, PlutoColumnFrozen.start);
      TableSettingsService.instance.saveFrozen(widget.screenId, column.field, 'start');
    }
  }

  void _freezeColumnRight(PlutoColumn column) {
    if (_stateManager != null) {
      _stateManager.toggleFrozenColumn(column, PlutoColumnFrozen.end);
      TableSettingsService.instance.saveFrozen(widget.screenId, column.field, 'end');
    }
  }

  void _unfreezeColumn(PlutoColumn column) {
    if (_stateManager != null) {
      _stateManager.toggleFrozenColumn(column, PlutoColumnFrozen.none);
      TableSettingsService.instance.saveFrozen(widget.screenId, column.field, 'none');
    }
  }

  void _toggleHideColumn(PlutoColumn column) {
    if (column.hide) {
      _stateManager.hideColumns([column], false);
      _hiddenFields.remove(column.field);
    } else {
      _stateManager.hideColumns([column], true);
      _hiddenFields.add(column.field);
    }
    TableSettingsService.instance.saveHiddenColumns(widget.screenId, _hiddenFields);
    _updateAllColumnTitles();
  }

  void _showAllColumns() {
    if (_stateManager == null) return;

    if (_hiddenFields.isNotEmpty) {
      final toShow = _plutoColumns.where((c) => _hiddenFields.contains(c.field)).toList();
      if (toShow.isNotEmpty) {
        _stateManager.hideColumns(toShow, false);
        _hiddenFields.clear();
        TableSettingsService.instance.saveHiddenColumns(widget.screenId, _hiddenFields);
        _updateAllColumnTitles();
        setState(() {});
        debugPrint('✅ Показаны колонки через _hiddenFields: ${toShow.map((c)=>c.field).toList()}');
        return;
      }
    }

    final hidden = _stateManager.refColumns.where((col) => col.hide).toList();
    if (hidden.isNotEmpty) {
      _stateManager.hideColumns(hidden, false);
      _hiddenFields.clear();
      TableSettingsService.instance.saveHiddenColumns(widget.screenId, _hiddenFields);
      _updateAllColumnTitles();
      setState(() {});
      debugPrint('✅ Показаны колонки через col.hide: ${hidden.map((c)=>c.field).toList()}');
    } else {
      debugPrint('⚠️ Не найдено скрытых колонок ни в _hiddenFields, ни в col.hide. Пересоздаём колонки.');
      _initColumns();
      _rebuildKey++;
      _updateTable();
      _updateAllColumnTitles();
      setState(() {});
    }
  }

  Future<void> _deleteCustomColumn(String field) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удаление столбца'),
        content: Text('Удалить столбец "${_colDefMap[field]?.title ?? field}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red)),
        ],
      ),
    );
    if (confirm == true) {
      await widget.provider.deleteCustomColumn(field);
      await _loadCustomColumns();
      if (_sortField == field) setState(() { _sortField = null; });
      _loadFirstPage();
      setState(() => _rebuildKey++);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Столбец удалён')));
    }
  }

  List<PopupMenuEntry<String>> _buildAggregationMenuItems(String field) {
    final current = _aggregationMethods[field] ?? 'none';
    final items = <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'group_by',
        child: Row(
          children: [
            Icon(Icons.group_work, size: universalDataTableHeaderIconSize, color: Colors.grey[700]),
            const SizedBox(width: 8),
            const Text('Агрегировать по столбцу'),
          ],
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem<String>(
        value: 'rules_header',
        enabled: false,
        child: Text('Правила агрегации', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
      ),
    ];
    _aggregationMethodsMap.forEach((key, value) {
      items.add(PopupMenuItem<String>(
        value: key,
        child: Row(
          children: [
            if (current == key) const Icon(Icons.check, size: 16, color: Colors.blue),
            const SizedBox(width: 8),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: current == key ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ));
    });
    return items;
  }

  void _handleAggregationSelection(String field, String value) {
    if (value == 'group_by') {
      _toggleGroupBy(field);
    } else if (value != 'rules_header') {
      setState(() {
        if (value == 'none') _aggregationMethods.remove(field);
        else _aggregationMethods[field] = value;
      });
      TableSettingsService.instance.saveAggregationMethod(widget.screenId, field, value);
      if (_groupByField != null) _loadFirstPage();
      _updateAllColumnTitles();
    }
  }

  void _toggleGroupBy(String field) {
    setState(() {
      if (_groupByField == field) {
        _groupByField = null;
        _isGroupingMode = false;
      } else {
        _groupByField = field;
        _isGroupingMode = true;
      }
      _currentOffset = 0;
    });
    _loadFirstPage();
  }

  void _toggleChartField(String field) {
    setState(() {
      if (_selectedChartFields.contains(field)) {
        _selectedChartFields.remove(field);
        _fieldToColor.remove(field);
        _chartSpots.remove(field);
      } else if (_selectedChartFields.length < 9) {
        _selectedChartFields.add(field);
        _fieldToColor[field] = _chartPalette[_selectedChartFields.length % _chartPalette.length];
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Максимум 9 линий')));
        return;
      }
    });
    TableSettingsService.instance.saveChartFields(widget.screenId, _selectedChartFields);
    if (_isChartVisible) _loadChartData();
    _updateAllColumnTitles();
  }

  Future<void> _loadChartData() async {
    if (_selectedChartFields.isEmpty) return;
    setState(() => _isChartLoading = true);
    try {
      final Map<String, List<FlSpot>> newSpots = {};
      for (final field in _selectedChartFields) {
        final points = await widget.provider.getTimeSeriesData(
          dateField: _selectedDateColumn,
          valueField: field,
          filters: _filters,
        );
        newSpots[field] = points.map((p) => FlSpot(p.date.millisecondsSinceEpoch.toDouble(), p.value)).toList();
      }
      if (mounted) setState(() => _chartSpots = newSpots);
    } finally {
      if (mounted) setState(() => _isChartLoading = false);
    }
  }

  dynamic _evaluateFormula(String formula, T item) {
    try {
      final variables = <String, double>{};
      final identifierRegex = RegExp(r'[a-zA-Z_][a-zA-Z0-9_]*');
      final matches = identifierRegex.allMatches(formula);
      for (var match in matches) {
        final field = match.group(0)!;
        if (variables.containsKey(field)) continue;
        final value = widget.provider.getFieldValue(item, field);
        if (value is num) {
          variables[field] = value.toDouble();
        }
      }
      final parser = ExpressionParser(formula, variables);
      final result = parser.parse();
      return result;
    } catch (e) {
      debugPrint('Ошибка вычисления формулы "$formula": $e');
      return null;
    }
  }

  double? _evaluateFormulaForRow(String formula, Map<String, PlutoCell> cells) {
    try {
      final variables = <String, double>{};
      final identifierRegex = RegExp(r'[a-zA-Z_][a-zA-Z0-9_]*');
      final matches = identifierRegex.allMatches(formula);
      for (var match in matches) {
        final field = match.group(0)!;
        if (variables.containsKey(field)) continue;
        final cell = cells[field];
        if (cell == null) continue;
        final value = cell.value;
        if (value is num) {
          variables[field] = value.toDouble();
        }
      }
      final parser = ExpressionParser(formula, variables);
      return parser.parse();
    } catch (e) {
      debugPrint('Ошибка вычисления формулы "$formula": $e');
      return null;
    }
  }

  dynamic _getValueForCustomColumn(T item, CustomColumn custom) {
    // 1. Найти все идентификаторы полей в формуле
    final regex = RegExp(r'[a-zA-Z_][a-zA-Z0-9_]*');
    final matches = regex.allMatches(custom.formula);
    final usedFields = matches.map((m) => m.group(0)!).toSet();

    // 2. Получить актуальные значения полей через провайдер (учитывает черновики)
    final cells = <String, PlutoCell>{};
    for (final field in usedFields) {
      final value = widget.provider.getFieldValue(item, field);
      cells[field] = PlutoCell(value: value);
    }

    // 3. Вычислить формулу с помощью существующего парсера
    return _evaluateFormulaForRow(custom.formula, cells);
  }

  void _clearFiltersAndRefresh() {
    setState(() {
      _filters = FilterSet();
      _currentOffset = 0;
    });
    _loadFirstPage();
  }

  void _toggleSort(String field) {
    print('🔽 _toggleSort: field=$field, current _sortField=$_sortField, _sortDesc=$_sortDesc');
    setState(() {
      if (_sortField == field) {
        _sortDesc = !_sortDesc;
        print('🔄 _toggleSort: меняем направление для того же поля, _sortDesc теперь $_sortDesc');
      } else {
        _sortField = field;
        _sortDesc = true;
        print('🆕 _toggleSort: новое поле, _sortField=$_sortField, _sortDesc=true');
      }
      /// _sortKey++;  // todo: причины выше
    });
    print('📞 _toggleSort: вызываем _loadFirstPage()');
    _updateAllColumnTitles();
    _loadFirstPage();
  }

  // ========================================================================
  // ФИЛЬТР С ПОЗИЦИОНИРОВАНИЕМ ВОЗЛЕ ИКОНКИ
  // ========================================================================
  Future<void> _showFilterPopup(String field, Offset tapPosition) async {
    try {
      final current = _filters.filters[field] ?? [];
      final values = await widget.provider.getUniqueValues(
        field: field,
        filters: _filters,
        maxValues: 500,
      );
      if (!mounted) return;

      final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
      if (overlay == null) {
        // fallback: обычный диалог по центру
        final selected = await showDialog<List<dynamic>>(
          context: context,
          builder: (_) => SimpleMultiSelectDialog(
            title: _colDefMap[field]!.title,
            items: values,
            initialSelected: current,
          ),
        );
        // Внутри _showFilterPopup, после получения selected
        if (selected != null && mounted) {
          setState(() {
            Map<String, List<dynamic>> newFilters = Map.from(_filters.filters);
            if (selected.isEmpty) {
              newFilters.remove(field);
            } else {
              newFilters[field] = selected;
            }
            _filters = _filters.copyWith(newFilters);
            _currentOffset = 0;
            /// _filterKey++; /// todo: причины выше
          });
          _updateAllColumnTitles();
          _loadFirstPage();
        }
        return;
      }

      const double dialogWidth = 280;
      const double dialogMaxHeight = 400;

      Offset position = Offset(tapPosition.dx + 8, tapPosition.dy);
      final screenSize = MediaQuery.of(context).size;

      if (position.dx + dialogWidth > screenSize.width) {
        position = Offset(tapPosition.dx - dialogWidth - 8, tapPosition.dy);
      }
      if (position.dy + dialogMaxHeight > screenSize.height) {
        position = Offset(position.dx, tapPosition.dy - dialogMaxHeight - 8);
      }

      final selected = await showGeneralDialog<List<dynamic>>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        barrierColor: Colors.transparent,
        pageBuilder: (ctx, anim, secondaryAnim) => Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(ctx, null),
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
            Positioned(
              left: position.dx,
              top: position.dy,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: dialogWidth,
                    constraints: BoxConstraints(maxHeight: dialogMaxHeight),
                    child: PopupFilterDialog(
                      title: _colDefMap[field]!.title,
                      items: values,
                      initialSelected: current,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

      if (selected != null && mounted) {
        setState(() {
          if (selected.isEmpty) _filters.filters.remove(field);
          else _filters.filters[field] = selected;
          _currentOffset = 0;
          /// _filterKey++;
        });
        _loadFirstPage();
      }
    } catch (e, stack) {
      debugPrint('Ошибка открытия фильтра: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось загрузить значения для фильтра: $e')),
        );
      }
    }
  }

  // ========================================================================
  // Загрузка данных и пагинация
  // ========================================================================

  Future<void> _loadFirstPage() async {
    final timestamp = DateTime.now().toIso8601String();
    print('[$timestamp] _loadFirstPage START, sortField=$_sortField, sortDesc=$_sortDesc');

    setState(() { _isLoading = true; _currentOffset = 0; });
    _rowToItem.clear();
    try {
      _totalRecords = await widget.provider.getTotalCount(
        filters: _filters,
        groupByField: _groupByField,
      );
      final rows = await _fetchPage(0);
      if (mounted) {
        setState(() {
          _visibleRows = rows;
          _updateCheckboxHeaderState();
          _currentOffset = rows.length;
          _hasMore = rows.length < _totalRecords;
        });
        print('[$timestamp] _loadFirstPage: загружено строк = ${rows.length}, total=$_totalRecords');

        if (_stateManager != null) {
          _stateManager.refRows.clear();
          _stateManager.refRows.addAll(_visibleRows);
          _stateManager.notifyListeners();
          print('[$timestamp] _loadFirstPage: stateManager обновлён, уведомление отправлено');
        }
      }
      await _updateStatisticsFromTotals();
      if (_isChartVisible && _selectedChartFields.isNotEmpty) _loadChartData();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    _updateTable();
    print('[$timestamp] _loadFirstPage FINISH');
  }

  Future<List<PlutoRow>> _fetchPage(int offset) async {
    final data = await widget.provider.fetchData(
      offset: offset,
      limit: _pageSize,
      filters: _filters,
      sortField: _sortField,
      sortDesc: _sortDesc,
      groupByField: _groupByField,
      aggregationMethods: _aggregationMethods,
    );
    final rows = <PlutoRow>[];
    for (var item in data) {
      final map = widget.toMap != null ? widget.toMap!(item) : item as Map<String, dynamic>;
      final cells = <String, PlutoCell>{};
      // Сохраняем ВСЕ поля из map (не только определённые в columns)
      for (var entry in map.entries) {
        cells[entry.key] = PlutoCell(value: entry.value);
      }
      // Пересчитываем кастомные колонки на основе уже заполненных cells
      for (var custom in _customColumns) {
        final value = _evaluateFormulaForRow(custom.formula, cells);
        cells[custom.name] = PlutoCell(value: value);
      }
      final row = PlutoRow(cells: cells);
      _rowToItem[row] = item;   // <-- сохраняем связь
      rows.add(row);
    }
    return rows;
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      final newRows = await _fetchPage(_currentOffset);

      if (mounted && newRows.isNotEmpty) {
        setState(() {
          _visibleRows.addAll(newRows);
          _updateCheckboxHeaderState();
          _currentOffset += newRows.length;
          _hasMore = _currentOffset < _totalRecords;
        });

        // Добавляем новые строки в PlutoGrid без очистки существующих
        _stateManager.refRows.addAll(newRows);
        _stateManager.notifyListeners();

        // (Опционально) пересчитать статистику для новых строк
        await _updateStatisticsFromTotals();
      }
    } catch (e, stack) {
      debugPrint('Ошибка загрузки ещё строк: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateTable() {
    if (_stateManager == null) return;
    _updateAllColumnTitles();
  }

  Future<void> _updateStatisticsFromTotals() async {
    final totals = await widget.provider.getAggregatedTotals(
      filters: _filters,
      groupByField: _groupByField,
    );
    for (var def in widget.columns) {
      if (_statsMap.containsKey(def.field)) {
        _statsMap[def.field]!.updateFromTotals(totals);
      }
    }
    for (var custom in _customColumns) {
      if (_statsMap.containsKey(custom.name)) {
        _statsMap[custom.name]!.updateFromTotals(totals);
      }
    }
    if (mounted) setState(() {});
    if (_stateManager != null) {
      _updateAllColumnTitles();
      _stateManager!.notifyListeners();
    }
  }

  void _updateAllColumnTitles() {
    if (_stateManager == null) return;
    for (final col in _stateManager.refColumns) {
      final stats = _statsMap[col.field];
      col.titleSpan = _buildTitleSpan(col.field, stats, col);
    }
    _stateManager.notifyListeners();
  }

  void _saveColumnOrder({String source = 'unknown'}) {
    if (_stateManager == null) return;
    if (_isLoading) return;
    if (_lastSavedTime != null && DateTime.now().difference(_lastSavedTime!) < const Duration(milliseconds: 500)) return;
    if (_lastAppliedOrderTime != null && DateTime.now().difference(_lastAppliedOrderTime!) < const Duration(seconds: 5)) return;
    _lastSavedTime = DateTime.now();
    final order = _stateManager.refColumns.originalList.map((c) => c.field).toList();
    TableSettingsService.instance.saveColumnOrder(widget.screenId, order);
  }

  // ========================================================================
  // Панель графика
  // ========================================================================

  Widget _buildChartPanel() {
    return Container(
      height: 350,
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, color: Colors.blue),
              const SizedBox(width: 8),
              const Text('Аналитика по дням', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              Container(
                width: 180,
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: DropdownButton<String>(
                  value: _selectedDateColumn,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: widget.columns.map((def) {
                    return DropdownMenuItem(value: def.field, child: Text(def.title, style: const TextStyle(fontSize: 12)));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedDateColumn = value);
                      TableSettingsService.instance.saveChartDateColumn(widget.screenId, value);
                      _loadChartData();
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _selectedChartFields.map((field) {
                      final color = _fieldToColor[field] ?? Colors.grey;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Chip(
                          label: Text(_colDefMap[field]?.title ?? field, style: const TextStyle(fontSize: 11)),
                          backgroundColor: color.withOpacity(0.2),
                          labelStyle: TextStyle(color: color),
                          deleteIcon: Icon(Icons.close, size: 16, color: color),
                          onDeleted: () => _toggleChartField(field),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isChartVisible = false;
                    _selectedChartFields.clear();
                    _fieldToColor.clear();
                    _chartSpots.clear();
                  });
                  TableSettingsService.instance.saveChartVisible(widget.screenId, false);
                  TableSettingsService.instance.saveChartFields(widget.screenId, []);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isChartLoading
                ? const Center(child: CircularProgressIndicator())
                : _chartSpots.isEmpty
                ? const Center(child: Text('Нажмите на иконку графика в заголовке колонки'))
                : LineChart(
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) {
                    final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                    return Text(DateFormat('dd.MM').format(date), style: const TextStyle(fontSize: 10));
                  })),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                ),
                lineBarsData: _selectedChartFields.map((field) {
                  return LineChartBarData(
                    spots: _chartSpots[field] ?? [],
                    color: _fieldToColor[field] ?? Colors.blue,
                    barWidth: 2,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                        radius: 2,
                        color: _fieldToColor[field] ?? Colors.blue,
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

  // ========================================================================
  // КОМПАКТНЫЙ ДИАЛОГ НАСТРОЙКИ РАЗМЕРА ИКОНОК И ВЫСОТЫ СТРОК
  // ========================================================================

  Future<void> _showSettingsDialog() async {
    double tempIconSize = universalDataTableHeaderIconSize;
    int tempRowOffset = _rowHeightOffset;
    int tempHeaderOffset = _headerHeightOffset;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Настройки таблицы', style: TextStyle(fontSize: 16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        content: StatefulBuilder(
          builder: (context, setStateDialog) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ползунок для размера иконок
                Row(
                  children: [
                    const Icon(Icons.format_size, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider(
                        value: tempIconSize,
                        min: 12.0,
                        max: 20.0,
                        divisions: 8,
                        onChanged: (val) {
                          setStateDialog(() {
                            tempIconSize = val;
                            universalDataTableHeaderIconSize = val;
                            _rebuildTable();
                          });
                        },
                      ),
                    ),
                    Text('${tempIconSize.toInt()}px', style: const TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 16),
                // Ползунок для высоты строк (без цифр)
                Row(
                  children: [
                    const Icon(Icons.height, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider(
                        value: tempRowOffset.toDouble(),
                        min: -5.0,
                        max: 20.0,
                        divisions: 50, // шаг 1
                        onChanged: (val) {
                          setStateDialog(() {
                            tempRowOffset = val.round();
                            _rowHeightOffset = tempRowOffset;
                            _saveRowHeightOffset(tempRowOffset);
                            _rebuildTable();
                          });
                        },
                      ),
                    ),
                    // Без цифр, только ползунок (можно добавить пустой SizedBox для отступа)
                    const SizedBox(width: 40), // чтобы сохранить отступ справа
                  ],
                ),
                const SizedBox(height: 16),
// Новый ползунок для высоты заголовка
                Row(
                  children: [
                    const Icon(Icons.title, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider(
                        value: tempHeaderOffset.toDouble(),
                        min: -10.0,
                        max: 40.0,
                        divisions: 50,
                        onChanged: (val) {
                          setStateDialog(() {
                            tempHeaderOffset = val.round();
                            _headerHeightOffset = tempHeaderOffset;
                            _saveHeaderHeightOffset(tempHeaderOffset);
                            _rebuildTable();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _saveRowHeightOffset(int offset) {
    TableSettingsService.instance.saveRowHeightOffset(widget.screenId, offset);
  }

  void _rebuildTable() {
    _initColumns();
    _headerHeight = _calculateHeaderHeight();
    setState(() {
      _rebuildKey++;
    });
  }

  // ========================================================================
  // Верхняя панель инструментов
  // ========================================================================

  Widget _buildTopToolbar() {
    if (widget.toolbarBuilder != null) {
      return widget.toolbarBuilder!(context, _effectiveController);
    }

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Spacer(),
          if (widget.headerFeatures.showSettingsButton)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showSettingsDialog,
              tooltip: 'Настройки размера иконок и высоты строк',
            ),
          if (widget.headerFeatures.showAddCustomColumnButton)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showCustomColumnManagementDialog,
              tooltip: 'Добавить кастомный столбец',
            ),
          if (_filters.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.filter_alt_off),
              label: const Text('Сбросить фильтры'),
              onPressed: _clearFiltersAndRefresh,
            ),
        ],
      ),
    );
  }

  Future<void> _showCustomColumnManagementDialog() async {
    final availableFields = widget.columns.map((c) => c.field).toList();
    await showDialog(
      context: context,
      builder: (ctx) => _CustomColumnManagementDialogUniversal(
        provider: widget.provider,
        templates: _templates,
        availableFields: availableFields,
        columnDefinitions: _colDefMap,
        onColumnsChanged: () async {
          await _loadCustomColumns();
          _rebuildTable();
          _loadFirstPage();
        },
      ),
    );
  }

  Future<void> _showGroupByDialog() async {
    final groupable = widget.columns.where((c) => c.isGroupable).toList();
    final items = groupable.map((c) => c.title).toList();
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => SimpleListDialog(items: items),
    );
    if (selected != null) {
      final field = groupable.firstWhere((c) => c.title == selected).field;
      _toggleGroupBy(field);
    }
  }


  // ========================================================================
  // Основной build
  // ========================================================================

  @override
  Widget build(BuildContext context) {
    if (!_isSettingsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _buildTopToolbar(),
        if (_isChartVisible) _buildChartPanel(),
        Expanded(
          child: PlutoGrid(
            key: ValueKey(_rebuildKey), /// todo: было так: key: ValueKey('${_rebuildKey}_${_sortKey}_${_filterKey}'),
            columns: _plutoColumns,
            rows: _visibleRows,
            onLoaded: (e) {
              _stateManager = e.stateManager;
              _applyHidden();
              _applyFrozen();
              _updateAllColumnTitles();
            },
            onColumnsMoved: (e) => _saveColumnOrder(source: 'onColumnsMoved'),
            configuration: PlutoGridConfiguration(
              style: PlutoGridStyleConfig(
                gridBackgroundColor: Colors.white,
                columnHeight: _getHeaderHeight(),
                rowHeight: _rowHeightOffset + 30, // базовая высота + смещение
                defaultColumnTitlePadding: EdgeInsets.zero,
                defaultColumnFilterPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
        if (_hasMore) _buildLoadMoreButton(),
      ],
    );
  }

  void _applyHidden() {
    debugPrint('📌 _applyHidden: _hiddenFields = $_hiddenFields');
    if (_hiddenFields.isEmpty) {
      debugPrint('📌 _applyHidden: _hiddenFields пуст, скрытие не применяется');
      return;
    }
    final toHide = _plutoColumns.where((c) => _hiddenFields.contains(c.field)).toList();
    debugPrint('📌 _applyHidden: нужно скрыть ${toHide.length} колонок: ${toHide.map((c)=>c.field).toList()}');
    if (toHide.isNotEmpty) {
      _stateManager.hideColumns(toHide, true);
      debugPrint('✅ Скрытие применено');
      for (var col in toHide) {
        debugPrint('   после hideColumns: ${col.field} .hide = ${col.hide}');
      }
    }
  }

  void _applyFrozen() async {
    final frozenMap = await TableSettingsService.instance.loadAllFrozen(widget.screenId);
    for (final entry in frozenMap.entries) {
      final col = _plutoColumns.firstWhereOrNull((c) => c.field == entry.key);
      if (col != null) {
        final frozen = entry.value == 'start' ? PlutoColumnFrozen.start : (entry.value == 'end' ? PlutoColumnFrozen.end : PlutoColumnFrozen.none);
        if (frozen != PlutoColumnFrozen.none) {
          _stateManager.toggleFrozenColumn(col, frozen);
        }
      }
    }
  }

  Widget _buildLoadMoreButton() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: ElevatedButton(
        onPressed: _loadMore,
        child: Text('Показать еще ($_pageSize) • $_currentOffset из $_totalRecords'),
      ),
    );
  }

  void refreshCustomColumns() {
    if (_stateManager == null) return;
    if (_customColumns.isEmpty) return;

    final rows = List<PlutoRow>.from(_stateManager.refRows);
    bool changed = false;

    for (final row in rows) {
      final originalItem = _rowToItem[row];
      if (originalItem == null) continue;

      for (final custom in _customColumns) {
        final newValue = _getValueForCustomColumn(originalItem, custom);
        final oldCell = row.cells[custom.name];
        if (oldCell == null) {
          row.cells[custom.name] = PlutoCell(value: newValue);
          changed = true;
        } else if (oldCell.value != newValue) {
          oldCell.value = newValue;
          changed = true;
        }
      }
    }

    if (changed) {
      _stateManager.notifyListeners();
    }
  }

  /// Обновляет значение ячейки в существующей строке по nmId (поле 'wb_article').
  /// Не перезагружает таблицу, только перерисовывает изменённую ячейку.
  void updateCell(int nmId, String field, dynamic newValue) {
    if (_stateManager == null) return;
    final row = _stateManager.refRows.firstWhereOrNull((r) {
      final cell = r.cells['wb_article'];
      return cell != null && cell.value == nmId;
    });
    if (row != null) {
      final cell = row.cells[field];
      if (cell != null) {
        cell.value = newValue;
        _stateManager.notifyListeners();
      }
    }
  }



  @override
  void dispose() {
    _effectiveController._detach();
    super.dispose();
  }
}

// ============================================================================
// 5. Всплывающий диалог фильтра (с поиском, сортировкой, выбранными сверху и без overflow)
// ДОБАВЛЕНЫ: статичный чекбокс "Пустые" в начале списка и кнопка "Выделить все"
// ============================================================================

class PopupFilterDialog extends StatefulWidget {
  final String title;
  final List<dynamic> items;
  final List<dynamic> initialSelected;

  const PopupFilterDialog({
    required this.title,
    required this.items,
    this.initialSelected = const [],
  });

  @override
  State<PopupFilterDialog> createState() => _PopupFilterDialogState();
}

class _PopupFilterDialogState extends State<PopupFilterDialog> {
  late Set<dynamic> selected;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Маркер для "Пустые" (используем null)
  static const dynamic _emptyMarker = null;

  // Все элементы для отображения (включая статичный "Пустые")
  List<dynamic> get _allDisplayItems {
    final items = <dynamic>[];
    // "Пустые" всегда первый
    items.add(_emptyMarker);
    // Добавляем все уникальные значения из данных, исключая дубликат null (если он есть)
    for (var item in widget.items) {
      if (item == _emptyMarker) continue; // чтобы не дублировать
      items.add(item);
    }
    return items;
  }

  // Отфильтрованные и отсортированные элементы (с учётом поиска, "Пустые" всегда первый)
  List<dynamic> get _filteredAndSortedItems {
    final filtered = _allDisplayItems.where((item) {
      if (_searchQuery.isEmpty) return true;
      final str = _itemToString(item);
      return str.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    // Сортировка: "Пустые" всегда первый, остальные по возрастанию
    final others = filtered.where((item) => item != _emptyMarker).toList();
    others.sort(_compareDynamic);

    final result = <dynamic>[];
    if (filtered.contains(_emptyMarker)) result.add(_emptyMarker);
    result.addAll(others);
    return result;
  }

  String _itemToString(dynamic item) {
    if (item == _emptyMarker) return 'Пустые';
    if (item == null) return '(null)';
    if (item is double) {
      // Если число целое (например, 5.0) – показываем без дробной части
      if (item == item.roundToDouble()) {
        return item.round().toString();
      }
      // Иначе – два знака после запятой
      return item.toStringAsFixed(2);
    }
    if (item is int) {
      return item.toString();
    }
    return item.toString();
  }

  int _compareDynamic(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    if (a is DateTime && b is DateTime) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }

  // Выделить все обычные значения (не "Пустые")
  void _selectAllRegular() {
    setState(() {
      final regularItems = _filteredAndSortedItems.where((item) => item != _emptyMarker).toList();
      selected = Set.from(regularItems);
    });
  }

  @override
  void initState() {
    super.initState();
    // initialSelected может содержать null (если ранее был выбран "Пустые")
    selected = Set.from(widget.initialSelected);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 280,
          constraints: const BoxConstraints(maxHeight: 450),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Заголовок
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  widget.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              // Поле поиска
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Поиск...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => _searchController.clear(),
                    )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                  ),
                ),
              ),
              // Кнопка "Выделить все" (обычные значения)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: _selectAllRegular,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Выделить все'),
                  ),
                ),
              ),
              const Divider(height: 1),
              // Список значений
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filteredAndSortedItems.length,
                  itemBuilder: (_, i) {
                    final val = _filteredAndSortedItems[i];
                    final isChecked = selected.contains(val);
                    final isSpecialEmpty = val == _emptyMarker;

                    return CheckboxListTile(
                      dense: true,
                      title: Text(
                        _itemToString(val),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSpecialEmpty ? FontWeight.bold : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      value: isChecked,
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            selected.add(val);
                          } else {
                            selected.remove(val);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              // Кнопки Отмена / Применить
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      child: const Text('Отмена'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, selected.toList()),
                      child: const Text('Применить'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 6. SimpleMultiSelectDialog – также с "Пустые" в начале и "Выделить все"
// ============================================================================

class SimpleMultiSelectDialog extends StatefulWidget {
  final String title;
  final List<dynamic> items;
  final List<dynamic> initialSelected;
  const SimpleMultiSelectDialog({
    required this.title,
    required this.items,
    this.initialSelected = const [],
  });

  @override
  State<SimpleMultiSelectDialog> createState() => _SimpleMultiSelectDialogState();
}

class _SimpleMultiSelectDialogState extends State<SimpleMultiSelectDialog> {
  late Set<dynamic> selected;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const dynamic _emptyMarker = null;

  List<dynamic> get _allDisplayItems {
    final items = <dynamic>[];
    items.add(_emptyMarker);
    for (var item in widget.items) {
      if (item == _emptyMarker) continue;
      items.add(item);
    }
    return items;
  }

  List<dynamic> get _filteredAndSortedItems {
    final filtered = _allDisplayItems.where((item) {
      if (_searchQuery.isEmpty) return true;
      final str = _itemToString(item);
      return str.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    final others = filtered.where((item) => item != _emptyMarker).toList();
    others.sort(_compareDynamic);

    final result = <dynamic>[];
    if (filtered.contains(_emptyMarker)) result.add(_emptyMarker);
    result.addAll(others);
    return result;
  }

  String _itemToString(dynamic item) {
    if (item == _emptyMarker) return 'Пустые';
    if (item == null) return '(null)';
    if (item is double) {
      // Если число целое (например, 5.0) – показываем без дробной части
      if (item == item.roundToDouble()) {
        return item.round().toString();
      }
      // Иначе – два знака после запятой
      return item.toStringAsFixed(2);
    }
    if (item is int) {
      return item.toString();
    }
    return item.toString();
  }

  int _compareDynamic(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    if (a is DateTime && b is DateTime) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }

  void _selectAllRegular() {
    setState(() {
      final regularItems = _filteredAndSortedItems.where((item) => item != _emptyMarker).toList();
      selected = Set.from(regularItems);
    });
  }

  @override
  void initState() {
    super.initState();
    selected = Set.from(widget.initialSelected);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 300,
        height: 450,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => _searchController.clear(),
                )
                    : null,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _selectAllRegular,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Выделить все (кроме Пустых)'),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredAndSortedItems.length,
                itemBuilder: (_, i) {
                  final val = _filteredAndSortedItems[i];
                  final isChecked = selected.contains(val);
                  final isSpecialEmpty = val == _emptyMarker;
                  return CheckboxListTile(
                    title: Text(
                      _itemToString(val),
                      style: TextStyle(
                        fontWeight: isSpecialEmpty ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    value: isChecked,
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          selected.add(val);
                        } else {
                          selected.remove(val);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, selected.toList()),
          child: const Text('Применить'),
        ),
      ],
    );
  }
}

class SimpleListDialog extends StatelessWidget {
  final List<String> items;
  const SimpleListDialog({required this.items});
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Группировка по...'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: items.map((title) => ListTile(
          title: Text(title),
          onTap: () => Navigator.pop(context, title),
        )).toList(),
      ),
    );
  }
}

// ============================================================================
// Парсер арифметических выражений для формул
// ============================================================================

class ExpressionParser {
  final String input;
  final Map<String, double> variables;
  int pos = 0;

  ExpressionParser(this.input, this.variables);

  double parse() {
    final result = _parseExpression();
    _skipWhitespace();
    if (pos < input.length) throw FormatException('Unexpected character: ${input[pos]}');
    return result;
  }

  void _skipWhitespace() {
    while (pos < input.length && _isWhitespace(input[pos])) pos++;
  }

  bool _isWhitespace(String ch) {
    return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
  }

  bool _isDigit(String ch) {
    final code = ch.codeUnitAt(0);
    return code >= 48 && code <= 57; // '0'..'9'
  }

  bool _isLetter(String ch) {
    final code = ch.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122); // A-Z a-z
  }

  bool _isLetterOrDigit(String ch) {
    return _isLetter(ch) || _isDigit(ch);
  }

  double _parseExpression() {
    double left = _parseTerm();
    _skipWhitespace();
    while (pos < input.length && (input[pos] == '+' || input[pos] == '-')) {
      final op = input[pos];
      pos++;
      final right = _parseTerm();
      if (op == '+') left += right;
      else left -= right;
      _skipWhitespace();
    }
    return left;
  }

  double _parseTerm() {
    double left = _parseFactor();
    _skipWhitespace();
    while (pos < input.length && (input[pos] == '*' || input[pos] == '/')) {
      final op = input[pos];
      pos++;
      final right = _parseFactor();
      if (op == '*') left *= right;
      else {
        if (right == 0) throw Exception('Division by zero');
        left /= right;
      }
      _skipWhitespace();
    }
    return left;
  }

  double _parseFactor() {
    _skipWhitespace();
    if (pos >= input.length) throw FormatException('Unexpected end of expression');

    if (input[pos] == '(') {
      pos++; // skip '('
      final expr = _parseExpression();
      _skipWhitespace();
      if (pos >= input.length || input[pos] != ')') throw FormatException('Missing closing parenthesis');
      pos++; // skip ')'
      return expr;
    }

    if (_isLetter(input[pos]) || input[pos] == '_') {
      final start = pos;
      while (pos < input.length && (_isLetterOrDigit(input[pos]) || input[pos] == '_')) pos++;
      final name = input.substring(start, pos);
      if (!variables.containsKey(name)) throw FormatException('Unknown variable: $name');
      return variables[name]!;
    }

    // number
    final start = pos;
    bool hasDot = false;
    while (pos < input.length && (_isDigit(input[pos]) || input[pos] == '.')) {
      if (input[pos] == '.') {
        if (hasDot) throw FormatException('Multiple dots in number');
        hasDot = true;
      }
      pos++;
    }
    final numStr = input.substring(start, pos);
    return double.parse(numStr);
  }
}

class _CustomColumnManagementDialogUniversal extends StatefulWidget {
  final DataProvider provider;
  final List<Map<String, dynamic>> templates;
  final List<String> availableFields;
  final Map<String, ColumnDefinition> columnDefinitions;
  final VoidCallback onColumnsChanged;

  const _CustomColumnManagementDialogUniversal({
    Key? key,
    required this.provider,
    required this.templates,
    required this.availableFields,
    required this.columnDefinitions,
    required this.onColumnsChanged,
  }) : super(key: key);

  @override
  __CustomColumnManagementDialogUniversalState createState() => __CustomColumnManagementDialogUniversalState();
}

class __CustomColumnManagementDialogUniversalState extends State<_CustomColumnManagementDialogUniversal> {
  List<CustomColumn> _customColumns = [];
  bool _isLoading = true;
  String? _selectedTemplateDisplayName;
  String? _editingColumnName;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _formulaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadColumns();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _formulaController.dispose();
    super.dispose();
  }

  Future<void> _loadColumns() async {
    final cols = await widget.provider.getCustomColumns();
    if (mounted) {
      setState(() {
        _customColumns = cols;
        _isLoading = false;
      });
    }
  }

  String _simplifyFormula(String formula) {
    final regex = RegExp(r'COALESCE\(\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*,\s*0\s*\)');
    return formula.replaceAllMapped(regex, (match) {
      final field = match.group(1)!;
      return widget.columnDefinitions[field]?.title ?? field;
    });
  }

  void _refreshAfterOperation() async {
    final cols = await widget.provider.getCustomColumns();
    if (mounted) {
      setState(() {
        _customColumns = cols;
      });
    }
    widget.onColumnsChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: FractionallySizedBox(
        widthFactor: 0.8,
        heightFactor: 0.8,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                height: 50,
                child: Center(
                  child: Text(
                    'Управление кастомными столбцами',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Левая панель – существующие колонки (как в reports_screen)
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Существующие столбцы:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _isLoading
                                ? const Center(child: CircularProgressIndicator())
                                : _customColumns.isEmpty
                                ? const Center(child: Text('Нет кастомных столбцов'))
                                : ListView.builder(
                              itemCount: _customColumns.length,
                              itemBuilder: (ctx, index) {
                                final col = _customColumns[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          col.displayName,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _simplifyFormula(col.formula),
                                          style: const TextStyle(fontSize: 10),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.edit, size: 18),
                                              onPressed: () {
                                                _nameController.text = col.displayName;
                                                _formulaController.text = col.formula;
                                                setState(() {
                                                  _editingColumnName = col.name;
                                                  _selectedTemplateDisplayName = null;
                                                });
                                              },
                                              tooltip: 'Редактировать',
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                              onPressed: () async {
                                                final confirm = await showDialog<bool>(
                                                  context: context,
                                                  builder: (ctx) => AlertDialog(
                                                    title: const Text('Удаление столбца'),
                                                    content: Text('Удалить столбец "${col.displayName}"?'),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () => Navigator.pop(ctx, false),
                                                        child: const Text('Отмена'),
                                                      ),
                                                      ElevatedButton(
                                                        onPressed: () => Navigator.pop(ctx, true),
                                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                        child: const Text('Удалить'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (confirm == true) {
                                                  try {
                                                    await widget.provider.deleteCustomColumn(col.name);
                                                    if (mounted) {
                                                      if (_editingColumnName == col.name) {
                                                        _nameController.clear();
                                                        _formulaController.clear();
                                                        _editingColumnName = null;
                                                      }
                                                      _refreshAfterOperation();
                                                    }
                                                  } catch (e) {
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text('Ошибка удаления: $e')),
                                                      );
                                                    }
                                                  }
                                                }
                                              },
                                              tooltip: 'Удалить',
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Правая панель – создание/редактирование (точная копия из reports_screen)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.templates.isNotEmpty) ...[
                            const Text(
                              'Шаблон:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<String>(
                              value: _selectedTemplateDisplayName,
                              hint: const Text('— выберите —'),
                              isExpanded: true,
                              items: widget.templates.map((t) {
                                return DropdownMenuItem<String>(
                                  value: t['display_name'] as String,
                                  child: Text(t['display_name'] as String),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  final template = widget.templates.firstWhere(
                                        (t) => t['display_name'] == value,
                                  );
                                  _nameController.text = template['display_name'] as String;
                                  _formulaController.text = template['formula'] as String;
                                  setState(() {
                                    _selectedTemplateDisplayName = value;
                                    _editingColumnName = null;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                          // Поле названия
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Название столбца',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Поле формулы
                          SizedBox(
                            height: 100,
                            child: TextField(
                              controller: _formulaController,
                              decoration: const InputDecoration(
                                labelText: 'Формула',
                                border: OutlineInputBorder(),
                                hintText: 'например: retail_price + delivery_rub',
                              ),
                              maxLines: 3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Кнопки операторов (как в reports_screen)
                          const Text(
                            'Операторы:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            children: ['+', '-', '*', '/', '(', ')'].map((op) {
                              return ElevatedButton(
                                onPressed: () {
                                  _formulaController.text += op;
                                },
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(40, 36),
                                  padding: EdgeInsets.zero,
                                ),
                                child: Text(op, style: const TextStyle(fontSize: 16)),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          // Список доступных полей (с русскими названиями)
                          const Text(
                            'Доступные поля:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: widget.availableFields.map((field) {
                                  final title = widget.columnDefinitions[field]?.title ?? field;
                                  return ActionChip(
                                    label: Text(title, style: const TextStyle(fontSize: 11)),
                                    onPressed: () {
                                      _formulaController.text += field;
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Кнопки действий
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final name = _nameController.text.trim();
                      final formula = _formulaController.text.trim();
                      if (name.isEmpty || formula.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Название и формула не могут быть пустыми'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }
                      // Проверка на валидность полей
                      final regex = RegExp(r'[a-zA-Z_][a-zA-Z0-9_]*');
                      final matches = regex.allMatches(formula);
                      final usedFields = matches.map((m) => m.group(0)).toSet();
                      final invalidFields = usedFields.where((f) => !widget.availableFields.contains(f)).toList();
                      if (invalidFields.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Неизвестные поля: ${invalidFields.join(', ')}'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }
                      try {
                        if (_editingColumnName != null) {
                          await widget.provider.updateCustomColumn(_editingColumnName!, name, formula);
                        } else {
                          await widget.provider.addCustomColumn(name, formula);
                        }
                        if (mounted) {
                          _nameController.clear();
                          _formulaController.clear();
                          setState(() {
                            _editingColumnName = null;
                            _selectedTemplateDisplayName = null;
                          });
                          _refreshAfterOperation();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_editingColumnName != null
                                  ? 'Столбец "$name" обновлён'
                                  : 'Столбец "$name" создан'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                    child: Text(_editingColumnName != null ? 'Обновить' : 'Создать'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}