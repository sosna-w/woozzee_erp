import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

import '../providers/reports_sync_provider.dart';
import '../models/report_detail_model.dart';
import '../services/aggregation_settings_service.dart';
import '../constants/reports_constants.dart';
import '../models/column_statistics.dart';
import '../delegates/custom_column_menu_delegate.dart';
import '../widgets/reports/date_range_picker_dialog.dart';
import '../widgets/reports/custom_column_management_dialog.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late PlutoGridStateManager _stateManager;
  late List<PlutoColumn> _columns;
  Map<String, ColumnStatistics> _columnStatsMap = {};
  late CustomColumnMenuDelegate _customColumnMenuDelegate;
  late AggregationSettingsService _aggregationSettings;

  DateTime? _lastAppliedOrderTime;
  DateTime? _lastSavedTime;
  bool _ignoreNextColumnMove = false;
  Set<String> _hiddenFields = {};
  bool _isGroupingMode = false;
  String? _groupByField;
  bool _isChartExpanded = false;
  List<Map<String, dynamic>> _customColumns = [];
  String? _currentGroupByField;
  bool _isChartVisible = false;
  String _selectedDateColumn = 'rr_dt';
  List<String> _selectedChartFields = [];
  Map<String, Color> _fieldToColor = {};
  Map<String, List<FlSpot>> _chartSpotsMap = {};
  bool _isChartLoading = false;
  int _columnOrderVersion = 0;

  List<PlutoRow> _visibleRows = [];
  bool _hasMoreRows = false;
  int _totalRecordsInDB = 0;
  int _currentOffset = 0;
  final int _chunkSize = 25;
  final int _preloadSize = 25;
  Map<String, List<dynamic>> _filters = {};
  String? _currentSortField;
  bool _currentSortDesc = true;

  TextEditingController _dateRangeController = TextEditingController();
  TextEditingController _nmIdController = TextEditingController();
  TextEditingController _saNameController = TextEditingController();
  DateTimeRange? _selectedDateRange;
  bool _isLoading = false;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  bool _isDateCacheLoading = false;
  final List<String> _logs = [];
  static const int _maxLogs = 100;

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().split(' ')[1].substring(0, 8);
    _logs.insert(0, '[$timestamp] $message');
    if (_logs.length > _maxLogs) _logs.removeLast();
    print(message);
  }

  @override
  void initState() {
    super.initState();
    _ignoreNextColumnMove = true;
    _aggregationSettings = AggregationSettingsService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCustomColumns();
    });
    _initializeGrid();
    _initAggregationSettings().then((_) {
      if (!mounted) return;
      _addLog('✅ Настройки агрегации загружены, обновляем заголовки');
      for (final entry in _columnStatsMap.entries) {
        final field = entry.key;
        final stats = entry.value;
        stats.aggregationMethod = _aggregationSettings.getMethod(field);
        stats.displayMode = _aggregationSettings.getDisplayMode(field);
      }
      _updateAllColumnTitles();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applySavedColumnOrder();
      });
    });
    _customColumnMenuDelegate = CustomColumnMenuDelegate(
      onFreezeLeft: _freezeColumnLeft,
      onFreezeRight: _freezeColumnRight,
      onUnfreeze: _unfreezeColumn,
      onToggleHide: _toggleHideColumn,
      onShowAllColumns: _showAllColumns,
    );
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final weekAgo = yesterday.subtract(const Duration(days: 7));
    final dateFrom = DateTime(weekAgo.year, weekAgo.month, weekAgo.day);
    final dateTo = DateTime(yesterday.year, yesterday.month, yesterday.day);
    _selectedDateRange = DateTimeRange(start: dateFrom, end: dateTo);
    _updateDateRangeController();
    _preloadDateAvailability();
    _addLog('✅ ReportsScreen initState() завершен');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = Provider.of<ReportsSyncProvider>(context, listen: false);
      try {
        await provider.checkDatabaseUpdate();
      } catch (e) {
        _addLog('⚠️ Ошибка проверки обновления базы: $e');
      }
    });
  }

  Future<void> _loadCustomColumns() async {
    _addLog('📥 _loadCustomColumns: начало загрузки');
    try {
      final provider = Provider.of<ReportsSyncProvider>(context, listen: false);
      final columns = await provider.getCustomColumns();
      _addLog('📥 Загружено кастомных колонок: ${columns.length}');
      setState(() {
        _customColumns = columns;
        _initializeGrid();
        _columnOrderVersion++;
      });
      await _applySavedColumnOrder();
      _loadReports();
      _addLog('✅ _loadCustomColumns завершён');
    } catch (e) {
      _addLog('❌ Ошибка загрузки кастомных колонок: $e');
    }
  }

  Future<void> _applySavedColumnOrder() async {
    _addLog('📂 Попытка загрузить сохранённый порядок колонок...');
    final order = await _aggregationSettings.loadColumnOrder();
    if (order == null || order.isEmpty) {
      _addLog('📂 Сохранённый порядок колонок отсутствует');
      return;
    }
    _addLog('📂 Загружен порядок колонок (${order.length} полей): $order');
    final columnMap = {for (var col in _columns) col.field: col};
    final newColumns = <PlutoColumn>[];
    for (final field in order) {
      if (columnMap.containsKey(field)) {
        newColumns.add(columnMap[field]!);
        columnMap.remove(field);
      } else {
        _addLog('⚠️ Поле "$field" из сохранённого порядка не найдено в текущих колонках');
      }
    }
    newColumns.addAll(columnMap.values);
    _lastAppliedOrderTime = DateTime.now();
    _ignoreNextColumnMove = true;
    setState(() {
      _columns = newColumns;
      _columnOrderVersion++;
    });
    _addLog('✅ Применён сохранённый порядок колонок. Новая версия: $_columnOrderVersion');
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) _ignoreNextColumnMove = false;
    });
  }

  void _saveColumnOrder({String source = 'unknown'}) {
    if (!mounted || _stateManager == null) return;
    List<PlutoColumn>? columns;
    try {
      columns = _stateManager.refColumns.originalList;
    } catch (e) {
      _addLog('⚠️ Не удалось получить колонки из stateManager: $e');
      return;
    }
    if (_isLoading) {
      _addLog('⏱️ Игнорируем сохранение порядка [$source] во время загрузки');
      return;
    }
    if (_lastSavedTime != null &&
        DateTime.now().difference(_lastSavedTime!) < const Duration(milliseconds: 500)) {
      _addLog('⏱️ Игнорируем частое сохранение порядка [$source]');
      return;
    }
    if (_lastAppliedOrderTime != null &&
        DateTime.now().difference(_lastAppliedOrderTime!) < const Duration(seconds: 5)) {
      _addLog('⏱️ Игнорируем сохранение порядка [$source] (прошло мало времени после применения)');
      return;
    }
    _lastSavedTime = DateTime.now();
    final fields = columns.map((col) => col.field).toList();
    _aggregationSettings.saveColumnOrder(fields);
    _addLog('💾 Сохранён порядок колонок [$source]: $fields');
  }

  Future<void> _initAggregationSettings() async {
    await _aggregationSettings.init();
    _addLog('✅ Настройки агрегации загружены');
    _hiddenFields = await _aggregationSettings.loadHiddenColumns();
    _addLog('📂 Загружены скрытые колонки: $_hiddenFields');
  }

  void _initializeGrid() {
    _addLog('🔧 Начало инициализации сетки');
    try {
      final fieldNames = ReportDetail.getFieldNames();
      _addLog('📋 Найдено полей в модели: ${fieldNames.length}');
      _columns = [];
      _columnStatsMap = {};

      for (final field in fieldNames) {
        try {
          final title = columnTranslations[field] ?? field;
          final columnType = _getColumnType(field);
          final width = _getColumnWidth(field);
          final bool supportsFooter = _supportsFooter(field);

          ColumnStatistics columnStats = ColumnStatistics(field, displayName: columnTranslations[field] ?? field);
          final savedMethod = _aggregationSettings.getMethod(field);
          columnStats.aggregationMethod = savedMethod;
          final savedDisplayMode = _aggregationSettings.getDisplayMode(field);
          columnStats.displayMode = savedDisplayMode;
          _columnStatsMap[field] = columnStats;

          final column = PlutoColumn(
            title: '',
            field: field,
            enableContextMenu: false,
            type: columnType,
            width: width,
            minWidth: 100,
            enableFilterMenuItem: false,
            enableSorting: false,
            enableAutoEditing: false,
            enableDropToResize: true,
            enableRowChecked: false,
            enableRowDrag: false,
            enableColumnDrag: false,
            textAlign: PlutoColumnTextAlign.center,
            titleTextAlign: PlutoColumnTextAlign.center,
            titleSpan: _buildTitleSpan(field, columnStats, false, null),
            formatter: (value) {
              try {
                if (value == null) return '';
                if (value is num) {
                  if (value == 0) return '';
                  return NumberFormat('#,###.00', 'ru_RU').format(value);
                }
                if (value is DateTime) return _formatDate(value);
                return value.toString();
              } catch (e) {
                return 'ERROR';
              }
            },
            renderer: (context) => _getColumnRenderer(context),
          );
          _columns.add(column);
        } catch (e) {
          _addLog('⚠️ Ошибка создания колонки для поля $field: $e');
          final errorColumn = PlutoColumn(
            title: field,
            field: field,
            type: PlutoColumnType.text(),
            width: 100,
            enableFilterMenuItem: false,
            enableSorting: false,
            renderer: (context) => const Text('ERR', style: TextStyle(color: Colors.red)),
          );
          _columns.add(errorColumn);
        }
      }

      for (final col in _customColumns) {
        final field = col['column_name'] as String;
        final displayName = col['display_name'] as String;
        final dataType = col['data_type'] as String;
        final columnStats = ColumnStatistics(field, displayName: displayName);
        _columnStatsMap[field] = columnStats;
        final column = PlutoColumn(
          title: '',
          field: field,
          type: dataType == 'DOUBLE' ? PlutoColumnType.number() : PlutoColumnType.text(),
          width: 150,
          minWidth: 100,
          enableContextMenu: false,
          enableFilterMenuItem: false,
          enableSorting: false,
          enableAutoEditing: false,
          textAlign: PlutoColumnTextAlign.center,
          titleTextAlign: PlutoColumnTextAlign.center,
          titleSpan: _buildTitleSpan(field, columnStats, false, null),
          renderer: (context) => _getColumnRenderer(context),
        );
        _columns.add(column);
      }

      _visibleRows = [];
      _hasMoreRows = false;
      _currentOffset = 0;
      _totalRecordsInDB = 0;
      _addLog('✅ Создано колонок: ${_columns.length}');
    } catch (e) {
      _addLog('❌ Критическая ошибка в _initializeGrid(): $e');
      _columns = [
        PlutoColumn(title: 'ID', field: 'id', type: PlutoColumnType.text(), width: 100, renderer: (context) => Text(context.cell.value?.toString() ?? '', style: const TextStyle(fontSize: 10))),
        PlutoColumn(title: 'Артикул', field: 'nm_id', type: PlutoColumnType.text(), width: 100, renderer: (context) => Text(context.cell.value?.toString() ?? '', style: const TextStyle(fontSize: 10))),
        PlutoColumn(title: 'Название', field: 'sa_name', type: PlutoColumnType.text(), width: 200, renderer: (context) => Text(context.cell.value?.toString() ?? '', style: const TextStyle(fontSize: 10))),
      ];
      _visibleRows = [];
      _hasMoreRows = false;
      _columnStatsMap = {};
    }
  }

  void _updateAllColumnTitles() {
    if (_stateManager == null) return;
    for (final column in _stateManager.refColumns) {
      final columnStats = _columnStatsMap[column.field];
      final isHidden = column.hide;
      column.titleSpan = _buildTitleSpan(column.field, columnStats, isHidden, column);
    }
    _stateManager.notifyListeners();
  }

  InlineSpan _buildTitleSpan(String field, ColumnStatistics? columnStats, bool isHidden, PlutoColumn? column) {
    final children = <InlineSpan>[];
    final hasFilter = _filters.containsKey(field) && _filters[field]!.isNotEmpty;

    children.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Container(
          width: 120,
          height: 275,
          padding: const EdgeInsets.only(top: 5),
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: 120,
              height: 275,
              decoration: BoxDecoration(color: Colors.blue.withOpacity(0), borderRadius: BorderRadius.circular(6)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Значение агрегации
                  GestureDetector(
                    onTap: () => _addLog('🔄 Тап по значению статистики поля: $field'),
                    child: MouseRegion(
                      cursor: columnStats != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
                      child: Container(
                        width: 72,
                        height: 32,
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: columnStats != null ? columnStats.modeColor.withOpacity(0.1) : Colors.grey.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: columnStats != null ? columnStats.modeColor.withOpacity(0.3) : Colors.grey.withOpacity(0.2), width: 1),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))],
                        ),
                        child: Center(
                          child: AutoSizeText(
                            columnStats != null ? columnStats.getFormattedValue() : '',
                            maxLines: 1,
                            minFontSize: 6,
                            maxFontSize: 14,
                            textAlign: TextAlign.center,
                            wrapWords: false,
                            overflowReplacement: Text(
                              columnStats != null ? columnStats.getFormattedValue() : '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 6, color: Colors.black, fontWeight: FontWeight.w600),
                            ),
                            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Символ типа агрегации + меню
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      MouseRegion(
                        cursor: columnStats != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
                        child: GestureDetector(
                          onTap: () {
                            if (columnStats != null) {
                              setState(() {
                                columnStats.cycleMode();
                                _updateAllColumnTitles();
                              });
                              _aggregationSettings.setDisplayMode(field, columnStats.displayMode);
                            }
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: columnStats != null ? columnStats.modeColor.withOpacity(0.1) : Colors.grey.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: columnStats != null ? columnStats.modeColor.withOpacity(0.3) : Colors.grey.withOpacity(0.2), width: 1),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))],
                            ),
                            child: Center(
                              child: Text(
                                columnStats != null ? columnStats.getDisplaySymbol() : 'Σ',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: columnStats != null ? Colors.black : Colors.grey[700]),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      PopupMenuButton<dynamic>(
                        itemBuilder: (BuildContext popupContext) {
                          final col = _stateManager.refColumns.firstWhere((c) => c.field == field, orElse: () => _stateManager.refColumns.first);
                          final items = <PopupMenuEntry<dynamic>>[
                            PopupMenuItem<dynamic>(
                              value: PlutoGridColumnMenuItem.freezeToStart,
                              height: 36,
                              child: Row(children: [Icon(Icons.pin_end, size: 20, color: col.frozen == PlutoColumnFrozen.start ? Colors.black : Colors.grey[700]), const SizedBox(width: 8), Text('Закрепить слева', style: TextStyle(color: col.frozen == PlutoColumnFrozen.start ? Colors.black : Colors.grey[700], fontWeight: col.frozen == PlutoColumnFrozen.start ? FontWeight.bold : FontWeight.normal))]),
                            ),
                            PopupMenuItem<dynamic>(
                              value: PlutoGridColumnMenuItem.freezeToEnd,
                              height: 36,
                              child: Row(children: [Icon(Icons.pin_end, size: 20, color: col.frozen == PlutoColumnFrozen.end ? Colors.black : Colors.grey[700]), const SizedBox(width: 8), Text('Закрепить справа', style: TextStyle(color: col.frozen == PlutoColumnFrozen.end ? Colors.black : Colors.grey[700], fontWeight: col.frozen == PlutoColumnFrozen.end ? FontWeight.bold : FontWeight.normal))]),
                            ),
                            PopupMenuItem<dynamic>(
                              value: PlutoGridColumnMenuItem.unfreeze,
                              height: 36,
                              enabled: col.frozen != PlutoColumnFrozen.none,
                              child: Row(children: [Icon(Icons.unfold_more, size: 20, color: Colors.grey[700]), const SizedBox(width: 8), const Text('Снять закрепление')]),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem<dynamic>(
                              value: PlutoGridColumnMenuItem.hideColumn,
                              height: 36,
                              child: Row(children: [Icon(col.hide ? Icons.visibility : Icons.visibility_off, size: 20, color: Colors.grey[700]), const SizedBox(width: 8), Text(col.hide ? 'Показать столбец' : 'Скрыть столбец')]),
                            ),
                            PopupMenuItem<dynamic>(
                              value: 'show_all',
                              height: 36,
                              child: Row(children: [Icon(Icons.view_column, size: 20, color: Colors.grey[700]), const SizedBox(width: 8), const Text('Показать все столбцы')]),
                            ),
                          ];
                          if (field.startsWith('custom_')) {
                            items.add(const PopupMenuDivider());
                            items.add(PopupMenuItem<dynamic>(value: 'delete', height: 36, child: Row(children: [Icon(Icons.delete, size: 20, color: Colors.red[700]), const SizedBox(width: 8), Text('Удалить столбец', style: TextStyle(color: Colors.red[700]))])));
                          }
                          return items;
                        },
                        onSelected: (dynamic value) {
                          _addLog('📋 Menu selected: $value для поля $field');
                          if (value is PlutoGridColumnMenuItem) {
                            if (_stateManager != null) {
                              final column = _stateManager.refColumns.firstWhere((c) => c.field == field, orElse: () => _stateManager.refColumns.first);
                              _customColumnMenuDelegate.onSelected(context: context, stateManager: _stateManager, column: column, mounted: mounted, selected: value);
                            }
                          } else if (value == 'delete') {
                            _deleteCustomColumn(field);
                          } else if (value == 'show_all') {
                            _showAllColumns();
                          }
                        },
                        child: Container(width: 32, height: 32, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.withOpacity(0.3), width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))]), child: const Center(child: Icon(Icons.menu, size: 18, color: Colors.black))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Кнопки агрегация + график
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PopupMenuButton<String>(
                        itemBuilder: (context) => _buildAggregationMenuItems(field),
                        onSelected: (value) => _handleAggregationSelection(field, value),
                        offset: const Offset(0, 40),
                        child: Container(width: 32, height: 32, decoration: BoxDecoration(color: _aggregationSettings.getMethod(field) != 'none' ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: _aggregationSettings.getMethod(field) != 'none' ? Colors.green.withOpacity(0.5) : Colors.grey.withOpacity(0.3), width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))]), child: Center(child: Icon(Icons.group_work, size: 18, color: _aggregationSettings.getMethod(field) != 'none' ? Colors.green : Colors.black))),
                      ),
                      const SizedBox(width: 8),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            _addLog('📈 Переключение поля на графике: $field');
                            setState(() => _isChartVisible = true);
                            _toggleChartField(field);
                          },
                          child: Container(width: 32, height: 32, decoration: BoxDecoration(color: _fieldToColor.containsKey(field) ? _fieldToColor[field]!.withOpacity(0.2) : Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: _fieldToColor.containsKey(field) ? _fieldToColor[field]! : Colors.grey.withOpacity(0.3), width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))]), child: Center(child: Icon(Icons.show_chart, size: 18, color: _fieldToColor.containsKey(field) ? _fieldToColor[field]! : Colors.grey[700]))),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Сортировка + фильтрация
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            _addLog('🔄 Кнопка сортировки нажата для поля: $field');
                            setState(() {
                              if (_currentSortField == field) {
                                _currentSortDesc = !_currentSortDesc;
                              } else {
                                _currentSortField = field;
                                _currentSortDesc = true;
                              }
                            });
                            _loadReports();
                          },
                          child: Container(width: 32, height: 32, decoration: BoxDecoration(color: _currentSortField == field ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: _currentSortField == field ? Colors.green.withOpacity(0.5) : Colors.grey.withOpacity(0.3), width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))]), child: Center(child: Icon(_currentSortField == field ? (_currentSortDesc ? Icons.arrow_downward : Icons.arrow_upward) : Icons.sort, size: 18, color: _currentSortField == field ? Colors.green : Colors.grey[700]))),
                        ),
                      ),
                      const SizedBox(width: 8),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => _openFilterDialog(field),
                          child: Container(width: 32, height: 32, decoration: BoxDecoration(color: hasFilter ? Colors.blue.withOpacity(0.2) : Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: hasFilter ? Colors.blue.withOpacity(0.5) : Colors.grey.withOpacity(0.3), width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))]), child: Center(child: Icon(Icons.filter_alt, size: 18, color: hasFilter ? Colors.blue : Colors.grey[700]))),
                        ),
                      ),
                    ],
                  ),
                  _buildFadingDivider(),
                  _buildDraggableTypeLabel(field, column),
                  _buildFadingDivider(),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AutoSizeText(
                      columnStats?.displayName ?? columnTranslations[field] ?? field,
                      maxLines: 5,
                      minFontSize: 7,
                      maxFontSize: 13,
                      textAlign: TextAlign.center,
                      wrapWords: false,
                      overflowReplacement: Text(
                        columnStats?.displayName ?? columnTranslations[field] ?? field,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 8, color: Colors.black, fontWeight: FontWeight.normal, height: 1.1),
                      ),
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.normal, height: 1.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    children.add(const TextSpan(text: '\n'));
    children.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: SizedBox(width: 0, height: 0)));
    return TextSpan(children: children, style: const TextStyle(height: 1.0));
  }

  Widget _buildFadingDivider() {
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.transparent, Colors.grey.withOpacity(0.3), Colors.transparent], stops: const [0.0, 0.5, 1.0]),
      ),
    );
  }

  Widget _buildDraggableTypeLabel(String field, PlutoColumn? column) {
    final typeLabel = _buildTypeLabel(field);
    if (column == null || _stateManager == null) return typeLabel;
    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovered = false;
        return MouseRegion(
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: isHovered ? Border.all(color: Colors.blue.withOpacity(0.5), width: 1.5) : null,
              color: isHovered ? Colors.blue.withOpacity(0.1) : null,
            ),
            child: Tooltip(
              message: 'Перетащите для изменения порядка колонок',
              preferBelow: false,
              child: Draggable<PlutoColumn>(
                data: column,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: PlutoShadowContainer(
                    alignment: Alignment.center,
                    width: PlutoGridSettings.minColumnWidth,
                    height: _stateManager?.columnHeight ?? 275,
                    backgroundColor: _stateManager?.configuration.style.gridBackgroundColor ?? Colors.white,
                    borderColor: _stateManager?.configuration.style.gridBorderColor ?? Colors.grey,
                    child: Text(
                      column.title.isNotEmpty ? column.title : columnTranslations[field] ?? field,
                      style: _stateManager?.configuration.style.columnTextStyle.copyWith(fontSize: 12) ?? const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
                child: typeLabel,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTypeLabel(String field) {
    final label = columnTypeLabels[field] ?? '';
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Center(
        child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.grey[700], letterSpacing: 0.5), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _getColumnRenderer(PlutoColumnRendererContext context) {
    final value = context.cell.value;
    final field = context.column.field;
    if (value is num) {
      Color textColor = Colors.black;
      if (value > 0) textColor = Colors.green;
      else if (value < 0) textColor = Colors.red;
      if (value == 0) return const Text('', style: TextStyle(fontSize: 10));
      final formatted = NumberFormat('#,###.00', 'ru_RU').format(value);
      return Text(formatted, style: TextStyle(fontSize: 10, color: textColor));
    }
    if (value is num) {
      Color textColor = Colors.black;
      if (value > 0) textColor = Colors.green;
      else if (value < 0) textColor = Colors.red;
      if (field.endsWith('_amount') || field.endsWith('_price') || field.endsWith('_rub') || field.endsWith('_fee') || field.endsWith('_commission') ||
          field == 'retail_price' || field == 'retail_amount' || field == 'cost_price' || field == 'additional_expenses' || field == 'commission_amount' ||
          field == 'commission_normal' || field == 'penalty_commission_rub' || field == 'delivery_rub' || field == 'ppvz_reward' || field == 'acquiring_fee' ||
          field == 'acceptance' || field == 'cashback_amount' || field == 'cashback_commission_change' || field == 'storage_fee' || field == 'penalty' ||
          field == 'deduction' || field == 'installment_cofinancing_amount' || field == 'additional_payment' || field == 'payment_schedule' || field == 'total') {
        return Text(value.toStringAsFixed(2), style: TextStyle(fontSize: 10, color: textColor));
      } else if (field.endsWith('_percent') || field.endsWith('_prc') || field.contains('percent') || field.contains('prc')) {
        return Text(value.toStringAsFixed(2), style: TextStyle(fontSize: 10, color: textColor));
      } else {
        return Text(value.toString(), style: TextStyle(fontSize: 10, color: textColor));
      }
    }
    final formatter = context.column.formatter;
    if (formatter != null) {
      final formattedValue = formatter(value);
      return Text(formattedValue, style: const TextStyle(fontSize: 10));
    } else {
      return Text(value?.toString() ?? '', style: const TextStyle(fontSize: 10));
    }
  }

  PlutoColumnType _getColumnType(String field) {
    if (field.endsWith('_dt') || field == 'report_date' || field == 'created_at' || field == 'updated_at') {
      return PlutoColumnType.date(format: 'yyyy-MM-dd');
    } else if (_supportsFooter(field)) {
      return PlutoColumnType.number(format: _getFooterFormat(field));
    } else {
      return PlutoColumnType.text();
    }
  }

  bool _supportsFooter(String field) {
    final dataType = ReportDetail.getFieldDataType(field);
    if (field == 'nm_id' || field == 'id' || field == 'delivery_time_hours' || field.endsWith('_id') || field == 'srid' || field == 'rrd_id' || field == 'order_uid') return false;
    return dataType == 'currency' || dataType == 'percent' || dataType == 'integer' || field == 'quantity' || field == 'delivery_amount' || field == 'return_amount';
  }

  String _getFooterFormat(String field) {
    final dataType = ReportDetail.getFieldDataType(field);
    switch (dataType) {
      case 'currency': return '#,##0.00 ₽';
      case 'percent': return '#,##0.00%';
      case 'integer': return '#,##0';
      default: return '#,##0.00';
    }
  }

  double _getColumnWidth(String field) {
    if (field.endsWith('_dt') || field == 'report_date' || field == 'created_at' || field == 'updated_at') return 120;
    if (field == 'total') return 100;
    if (field.endsWith('_amount') || field.endsWith('_price') || field.endsWith('_rub') || field.endsWith('_fee') || field.endsWith('_commission')) return 150;
    if (field == 'sa_name' || field == 'subject_name' || field == 'brand_name' || field == 'supplier_oper_name' || field == 'bonus_type_name') return 200;
    if (field == 'srid' || field == 'rrd_id' || field == 'order_uid') return 180;
    if (field == 'quantity' || field == 'nm_id' || field == 'id') return 100;
    return 150;
  }

  void _freezeColumnLeft(PlutoColumn column) {
    if (_stateManager != null) {
      _stateManager.toggleFrozenColumn(column, PlutoColumnFrozen.start);
      _aggregationSettings.setFrozen(column.field, 'start');
    }
  }

  void _freezeColumnRight(PlutoColumn column) {
    if (_stateManager != null) {
      _stateManager.toggleFrozenColumn(column, PlutoColumnFrozen.end);
      _aggregationSettings.setFrozen(column.field, 'end');
    }
  }

  void _unfreezeColumn(PlutoColumn column) {
    if (_stateManager != null) {
      _stateManager.toggleFrozenColumn(column, PlutoColumnFrozen.none);
      _aggregationSettings.setFrozen(column.field, 'none');
    }
  }

  void _toggleHideColumn(PlutoColumn column) {
    _addLog('📌 toggleHideColumn: field=${column.field}, hide=${column.hide}');
    if (column.hide) {
      _stateManager.hideColumns([column], false);
      _hiddenFields.remove(column.field);
    } else {
      _stateManager.hideColumns([column], true);
      _hiddenFields.add(column.field);
    }
    _aggregationSettings.saveHiddenColumns(_hiddenFields);
  }

  void _showAllColumns() {
    final hiddenColumns = _stateManager.refColumns.originalList.where((col) => col.hide).toList();
    if (hiddenColumns.isNotEmpty) {
      _stateManager.hideColumns(hiddenColumns, false);
      _hiddenFields.clear();
      _aggregationSettings.saveHiddenColumns(_hiddenFields);
    }
  }

  Future<void> _deleteCustomColumn(String field) async {
    _addLog('🗑️ _deleteCustomColumn вызван для поля: $field');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление столбца'),
        content: Text('Вы уверены, что хотите удалить столбец "${columnTranslations[field] ?? field}"?'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Удалить'))],
      ),
    );
    if (confirm != true) return;
    try {
      final provider = Provider.of<ReportsSyncProvider>(context, listen: false);
      await provider.deleteCustomColumn(field);
      if (_currentSortField == field) setState(() { _currentSortField = null; _currentSortDesc = true; });
      await _loadCustomColumns();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Столбец удалён'), backgroundColor: Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка удаления: $e'), backgroundColor: Colors.red));
    }
  }

  List<PopupMenuEntry<String>> _buildAggregationMenuItems(String field) {
    final currentMethod = _aggregationSettings.getMethod(field);
    final menuItems = <PopupMenuEntry<String>>[
      PopupMenuItem<String>(value: 'group_by', height: 36, child: Row(children: [Icon(Icons.group_work, size: 20, color: Colors.grey[700]), const SizedBox(width: 8), const Text('Агрегировать по столбцу', style: TextStyle(fontSize: 12))])),
      const PopupMenuDivider(),
      const PopupMenuItem<String>(value: 'rules_header', height: 30, enabled: false, child: Text('Правила агрегации', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey))),
    ];
    aggregationMethods.forEach((key, value) {
      menuItems.add(PopupMenuItem<String>(
        value: key,
        height: 36,
        child: Row(children: [Icon(currentMethod == key ? Icons.check : null, size: 16, color: Colors.blue), const SizedBox(width: 8), Text(value, style: TextStyle(fontSize: 12, fontWeight: currentMethod == key ? FontWeight.bold : FontWeight.normal))]),
      ));
    });
    return menuItems;
  }

  void _handleAggregationSelection(String field, String value) {
    if (value == 'group_by') {
      _toggleGroupBy(field);
    } else if (value != 'rules_header') {
      _aggregationSettings.setMethod(field, value).then((_) {
        if (_isGroupingMode) _loadReports();
        final stats = _columnStatsMap[field];
        if (stats != null) stats.aggregationMethod = value;
        _updateAllColumnTitles();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Метод агрегации для "${columnTranslations[field] ?? field}" сохранен'), duration: const Duration(seconds: 2)));
      });
    }
  }

  void _toggleGroupBy(String field) {
    setState(() {
      if (_isGroupingMode && _groupByField == field) {
        _isGroupingMode = false;
        _groupByField = null;
      } else {
        _isGroupingMode = true;
        _groupByField = field;
      }
      _currentOffset = 0;
    });
    _loadReports();
  }

  void _openFilterDialog(String field) async {
    final provider = Provider.of<ReportsSyncProvider>(context, listen: false);
    final otherFilters = Map<String, List<dynamic>>.from(_filters)..remove(field);
    final currentValues = _filters[field] ?? [];
    final result = await showDialog<List<dynamic>>(
      context: context,
      builder: (context) => ColumnFilterDialog(
        field: field,
        fieldTitle: columnTranslations[field] ?? field,
        currentValues: currentValues,
        provider: provider,
        dateRange: _selectedDateRange,
        nmId: _nmIdController.text.isNotEmpty ? int.tryParse(_nmIdController.text) : null,
        saName: _saNameController.text.isNotEmpty ? _saNameController.text : null,
        otherFilters: otherFilters,
      ),
    );
    if (result != null) {
      setState(() {
        if (result.isEmpty) _filters.remove(field);
        else _filters[field] = result;
        _currentOffset = 0;
        _updateAllColumnTitles();
      });
      _loadReports();
    }
  }

  void _updateColumnStatistics() {
    if (_visibleRows.isEmpty) return;
    for (final entry in _columnStatsMap.entries) entry.value.update(_visibleRows);
    _updateAllColumnTitles();
  }

  Future<void> _updateStatisticsFromDatabase() async {
    try {
      final provider = Provider.of<ReportsSyncProvider>(context, listen: false);
      final aggregatedData = await provider.getAggregatedData(
        dateFrom: _selectedDateRange?.start,
        dateTo: _selectedDateRange?.end,
        nmId: _nmIdController.text.isNotEmpty ? int.tryParse(_nmIdController.text) : null,
        saName: _saNameController.text.isNotEmpty ? _saNameController.text : null,
        filters: _filters,
      );
      for (final entry in _columnStatsMap.entries) {
        final field = entry.key;
        final stats = entry.value;
        if (field == 'total') {
          double totalSum = 0.0;
          for (final totalField in totalFields) {
            final sumKey = 'total_$totalField';
            if (aggregatedData.containsKey(sumKey) && aggregatedData[sumKey] != null) {
              final value = aggregatedData[sumKey];
              if (value is num) totalSum += value.toDouble();
            }
          }
          await stats.updateFromDatabase(aggregatedData: aggregatedData, customSum: totalSum);
        } else {
          await stats.updateFromDatabase(aggregatedData: aggregatedData);
        }
      }
      _updateAllColumnTitles();
    } catch (e) {
      for (final stats in _columnStatsMap.values) {
        if (stats.supportsStatistics()) stats.update(_visibleRows);
      }
      _updateAllColumnTitles();
    }
  }

  Future<void> _loadReports({bool loadMore = false}) async {
    _addLog('🔍 ЗАГРУЗКА ДАННЫХ (режим: ${_isGroupingMode ? 'группировка по $_groupByField' : 'обычный'})');
    if (!loadMore) setState(() { _isLoading = true; _currentOffset = 0; });
    try {
      final provider = Provider.of<ReportsSyncProvider>(context, listen: false);
      final allMethods = _aggregationSettings.getAllMethods();
      if (_isGroupingMode && _groupByField != null) {
        _totalRecordsInDB = await provider.getAggregatedGroupCount(
          groupByField: _groupByField!,
          dateFrom: _selectedDateRange?.start,
          dateTo: _selectedDateRange?.end,
          nmId: _nmIdController.text.isNotEmpty ? int.tryParse(_nmIdController.text) : null,
          saName: _saNameController.text.isNotEmpty ? _saNameController.text : null,
          filters: _filters,
        );
      } else {
        _totalRecordsInDB = await provider.getTotalCountWithFilters(
          dateFrom: _selectedDateRange?.start,
          dateTo: _selectedDateRange?.end,
          nmId: _nmIdController.text.isNotEmpty ? int.tryParse(_nmIdController.text) : null,
          saName: _saNameController.text.isNotEmpty ? _saNameController.text : null,
          filters: _filters,
        );
      }
      _addLog('📈 Общее количество: $_totalRecordsInDB');
      List<Map<String, dynamic>> reports;
      if (_isGroupingMode && _groupByField != null) {
        reports = await provider.getAggregatedByColumn(
          groupByField: _groupByField!,
          dateFrom: _selectedDateRange?.start,
          dateTo: _selectedDateRange?.end,
          nmId: _nmIdController.text.isNotEmpty ? int.tryParse(_nmIdController.text) : null,
          saName: _saNameController.text.isNotEmpty ? _saNameController.text : null,
          filters: _filters,
          aggregationMethods: allMethods,
          sortField: _currentSortField,
          sortDesc: _currentSortDesc,
          limit: loadMore ? _chunkSize : _preloadSize,
          offset: loadMore ? _currentOffset : 0,
        );
      } else {
        reports = await provider.getReportsPaginated(
          dateFrom: _selectedDateRange?.start,
          dateTo: _selectedDateRange?.end,
          nmId: _nmIdController.text.isNotEmpty ? int.tryParse(_nmIdController.text) : null,
          saName: _saNameController.text.isNotEmpty ? _saNameController.text : null,
          filters: _filters,
          sortField: _currentSortField,
          sortDesc: _currentSortDesc,
          limit: loadMore ? _chunkSize : _preloadSize,
          offset: loadMore ? _currentOffset : 0,
        );
      }
      final List<PlutoRow> newRows = [];
      for (final record in reports) {
        final cells = <String, PlutoCell>{};
        final allColumnFields = _columns.map((col) => col.field).toList();
        for (final fieldName in allColumnFields) {
          dynamic value = record[fieldName];
          if (value == null && !_isGroupingMode && ReportDetail.getFieldNames().contains(fieldName)) {
            final dataType = ReportDetail.getFieldDataType(fieldName);
            if (dataType == 'currency' || dataType == 'percent' || dataType == 'integer') value = 0;
          }
          cells[fieldName] = PlutoCell(value: value);
        }
        newRows.add(PlutoRow(cells: cells));
      }
      setState(() {
        if (loadMore) {
          _visibleRows.addAll(newRows);
          _currentOffset += _chunkSize;
        } else {
          _visibleRows = newRows;
          _currentOffset = newRows.length;
        }
        _hasMoreRows = _visibleRows.length < _totalRecordsInDB;
      });
      if (_stateManager != null) {
        _stateManager.refRows.clear();
        _stateManager.refRows.addAll(_visibleRows);
        _stateManager.notifyListeners();
      }
      await _updateStatisticsFromDatabase();
      if (_isChartVisible && _selectedChartFields.isNotEmpty) _loadChartData();
    } catch (e, stack) {
      _addLog('❌ Ошибка загрузки: $e');
      if (!loadMore) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки данных: $e'), backgroundColor: Colors.red));
    } finally {
      if (!loadMore) setState(() => _isLoading = false);
    }
  }

  void _loadMoreData() {
    _loadReports(loadMore: true);
  }

  Future<void> _loadChartData() async {
    if (_selectedChartFields.isEmpty) {
      setState(() => _chartSpotsMap.clear());
      return;
    }
    setState(() => _isChartLoading = true);
    try {
      final provider = Provider.of<ReportsSyncProvider>(context, listen: false);
      final Map<String, List<FlSpot>> newSpotsMap = {};
      for (final field in _selectedChartFields) {
        final data = await provider.getTimeSeriesData(
          dateColumn: _selectedDateColumn,
          valueColumn: field,
          dateFrom: _selectedDateRange?.start,
          dateTo: _selectedDateRange?.end,
          nmId: _nmIdController.text.isNotEmpty ? int.tryParse(_nmIdController.text) : null,
          saName: _saNameController.text.isNotEmpty ? _saNameController.text : null,
          filters: _filters,
        );
        final spots = <FlSpot>[];
        for (final record in data) {
          final date = record['date'] as DateTime?;
          final total = record['total'] as num?;
          if (date != null && total != null) {
            final normalizedDate = DateTime(date.year, date.month, date.day);
            spots.add(FlSpot(normalizedDate.millisecondsSinceEpoch.toDouble(), total.toDouble()));
          }
        }
        newSpotsMap[field] = spots;
      }
      setState(() => _chartSpotsMap = newSpotsMap);
    } catch (e) {
      setState(() => _chartSpotsMap.clear());
    } finally {
      setState(() => _isChartLoading = false);
    }
  }

  void _toggleChartField(String field) {
    setState(() {
      if (_selectedChartFields.contains(field)) {
        _selectedChartFields.remove(field);
        _fieldToColor.remove(field);
        _chartSpotsMap.remove(field);
      } else {
        if (_selectedChartFields.length < 9) {
          _selectedChartFields.add(field);
          final colorIndex = _selectedChartFields.length - 1;
          _fieldToColor[field] = chartColors[colorIndex % chartColors.length];
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Достигнут лимит линий (максимум 9)'), duration: Duration(seconds: 2)));
          return;
        }
      }
    });
    _updateAllColumnTitles();
    if (_isChartVisible) _loadChartData();
  }

  void _clearAllFilters() {
    setState(() {
      _filters.clear();
      if (_isGroupingMode) {
        _isGroupingMode = false;
        _groupByField = null;
      }
      _currentOffset = 0;
      _updateAllColumnTitles();
    });
    _loadReports();
  }

  void _preloadDateAvailability() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = Provider.of<ReportsSyncProvider>(context, listen: false);
      setState(() => _isDateCacheLoading = true);
      try {
        await provider.checkDateAvailability(forceRefresh: true);
      } catch (e) {}
      finally { if (mounted) setState(() => _isDateCacheLoading = false); }
    });
  }

  String _formatDate(DateTime date) => DateFormat('dd.MM.yyyy').format(date);
  void _updateDateRangeController() {
    if (_selectedDateRange != null) {
      _dateRangeController.text = '${_formatDate(_selectedDateRange!.start)} – ${_formatDate(_selectedDateRange!.end)}';
    } else {
      _dateRangeController.text = '';
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final provider = Provider.of<ReportsSyncProvider>(context, listen: false);
    if (!provider.isSyncing) provider.resetProgress();
    if (!provider.isDateAvailabilityLoaded && provider.isDateAvailabilityLoading) {
      _showDateCacheLoadingDialog(context);
      return;
    }
    final result = await showDialog<DateTimeRange>(
      context: context,
      builder: (context) => DateRangePickerDialog(
        initialDateRange: _selectedDateRange,
        localDateAvailability: provider.cachedLocalDateAvailability,
        serverDateAvailability: provider.cachedServerDateAvailability,
        checkingServerDates: provider.isDateAvailabilityLoading,
        provider: provider,
        onRefresh: () async { await provider.checkDateAvailability(forceRefresh: true); },
      ),
    );
    if (result != null) {
      setState(() => _selectedDateRange = result);
      _updateDateRangeController();
      if (!provider.isSyncing) provider.resetProgress();
      _loadReports();
    }
  }

  void _showDateCacheLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Загрузка данных'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text('Загружаем информацию о доступных датах...'),
          const SizedBox(height: 8),
          Consumer<ReportsSyncProvider>(
            builder: (context, provider, _) => Text('Прогресс: ${provider.isDateAvailabilityLoaded ? '100%' : provider.isDateAvailabilityLoading ? 'Загрузка...' : 'Подготовка...'}', style: const TextStyle(fontSize: 12)),
          ),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена'))],
      ),
    );
  }

  Future<void> _resetAllAggregationSettings() async {
    await _aggregationSettings.clear();
    for (final stats in _columnStatsMap.values) {
      stats.aggregationMethod = 'none';
      stats.displayMode = 'sum';
    }
    _hiddenFields.clear();
    if (_stateManager != null) {
      final currentlyHidden = _stateManager.refColumns.where((col) => col.hide).toList();
      if (currentlyHidden.isNotEmpty) _stateManager.hideColumns(currentlyHidden, false);
    }
    if (_isGroupingMode) {
      setState(() { _isGroupingMode = false; _groupByField = null; });
      _loadReports();
    } else {
      _updateAllColumnTitles();
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Все настройки агрегации сброшены'), duration: Duration(seconds: 2)));
  }

  Future<void> _showAddCustomColumnDialog() async {
    final nameController = TextEditingController();
    final formulaController = TextEditingController();
    final availableFields = ReportDetail.getFieldNames();
    List<Map<String, dynamic>> templates = [];
    try {
      final jsonString = await rootBundle.loadString('assets/default_custom_columns.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      templates = jsonList.cast<Map<String, dynamic>>();
    } catch (e) { _addLog('⚠️ Ошибка загрузки шаблонов: $e'); }
    final provider = Provider.of<ReportsSyncProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => CustomColumnManagementDialog(
        provider: provider,
        templates: templates,
        availableFields: availableFields,
        columnTranslations: columnTranslations,
        onColumnsChanged: _loadCustomColumns,
      ),
    );
  }

  Widget _buildTopPanel() {
    return Consumer<ReportsSyncProvider>(
      builder: (context, provider, _) {
        final hasActiveFilters = _filters.isNotEmpty && _filters.values.any((values) => values.isNotEmpty);
        return Container(
          height: 60,
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.1), width: 1))),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text(_selectedDateRange != null ? '${_formatDate(_selectedDateRange!.start)} – ${_formatDate(_selectedDateRange!.end)}' : 'Выберите даты', style: const TextStyle(fontSize: 14))),
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8))),
                      child: InkWell(
                        onTap: () => _selectDateRange(context),
                        borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
                        child: Center(child: provider.isDateAvailabilityLoading || _isDateCacheLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.calendar_today, size: 20)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              IconButton(icon: const Icon(Icons.view_column), onPressed: _showAllColumns, tooltip: 'Показать все скрытые столбцы'),
              Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Icon(Icons.sort, size: 20, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 150,
                      child: DropdownButton<String>(
                        value: _currentSortField,
                        hint: Text('Сортировка', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        isExpanded: true,
                        underline: const SizedBox(),
                        icon: const Icon(Icons.arrow_drop_down, size: 20),
                        items: [
                          const DropdownMenuItem<String>(value: null, child: Text('Дата отчета (по умолчанию)', style: TextStyle(fontSize: 12))),
                          ...ReportDetail.getFieldNames().map((field) => DropdownMenuItem<String>(value: field, child: Text(columnTranslations[field] ?? field, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis))),
                          ..._customColumns.map((col) => DropdownMenuItem<String>(value: col['column_name'] as String, child: Text(col['display_name'] as String, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (String? newField) {
                          if (newField != _currentSortField) {
                            setState(() { _currentSortField = newField; _currentSortDesc = true; });
                            _loadReports();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(_currentSortDesc ? Icons.arrow_downward : Icons.arrow_upward, size: 20, color: _currentSortField != null ? Colors.blue : Colors.grey[400]),
                      onPressed: _currentSortField != null ? () { setState(() => _currentSortDesc = !_currentSortDesc); _loadReports(); } : null,
                      tooltip: _currentSortDesc ? 'По убыванию' : 'По возрастанию',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (provider.isCheckingUpdate) Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.blue[100]!)), child: Row(children: [const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 8), const Text('Проверка обновлений...', style: TextStyle(fontSize: 12, color: Colors.blue))])),
              if (provider.isDownloadingDb) Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green[100]!)), child: Row(children: [const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 8), Text('Загрузка базы... ${(provider.progress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, color: Colors.green))])),
              if (!provider.isCheckingUpdate && !provider.isDownloadingDb && provider.lastUpdateDateTime != null) Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[300]!)), child: Row(children: [Icon(Icons.update, size: 14, color: Colors.grey[600]), const SizedBox(width: 6), Text('Обновлено: ${_formatUpdateDateTime(provider.lastUpdateDateTime!)}', style: TextStyle(fontSize: 11, color: Colors.grey[600]))])),
              if (provider.isSyncing && !provider.isDownloadingDb) Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.blue[100]!)), child: Row(children: [const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 8), Text(provider.totalRecords == 0 ? 'Загрузка...' : '${provider.syncedRecords}/${provider.totalRecords} (${(provider.progress * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 12, color: Colors.blue))])),
              if (hasActiveFilters) Container(margin: const EdgeInsets.only(left: 8), child: ElevatedButton.icon(icon: const Icon(Icons.filter_alt_off, size: 16), label: const Text('Сбросить фильтры', style: TextStyle(fontSize: 12)), onPressed: _clearAllFilters, style: ElevatedButton.styleFrom(backgroundColor: Colors.red[50], foregroundColor: Colors.red[700], padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.red[100]!))))),
              if (_isGroupingMode && _groupByField != null) Container(margin: const EdgeInsets.only(left: 8), child: Chip(label: Text('Группировка: ${columnTranslations[_groupByField] ?? _groupByField}', style: const TextStyle(fontSize: 12)), backgroundColor: Colors.blue[50], deleteIcon: const Icon(Icons.close, size: 16), onDeleted: () => _toggleGroupBy(_groupByField!))),
              IconButton(icon: const Icon(Icons.add, size: 20), onPressed: _showAddCustomColumnDialog, tooltip: 'Добавить кастомный столбец'),
              IconButton(icon: const Icon(Icons.restore, size: 20), onPressed: _resetAllAggregationSettings, tooltip: 'Сбросить все настройки агрегации'),
            ],
          ),
        );
      },
    );
  }

  String _formatUpdateDateTime(DateTime dateTime) => DateFormat('dd.MM.yyyy HH:mm').format(dateTime);

  Widget _buildChartPanel() {
    return Container(
      height: _isChartExpanded ? 550 : 350,
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, size: 20, color: Colors.blue),
              const SizedBox(width: 8),
              const Text('Аналитика по дням', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              Container(
                width: 180,
                decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: DropdownButton<String>(
                  value: _selectedDateColumn,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: dateColumns.map((col) => DropdownMenuItem(value: col, child: Text(columnTranslations[col] ?? col, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (value) { if (value != null) { setState(() => _selectedDateColumn = value); _loadChartData(); } },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _selectedChartFields.map((field) {
                      final color = _fieldToColor[field] ?? Colors.grey;
                      return Padding(padding: const EdgeInsets.only(right: 8), child: Chip(label: Text(columnTranslations[field] ?? field, style: const TextStyle(fontSize: 11)), backgroundColor: color.withOpacity(0.2), labelStyle: TextStyle(color: color), deleteIcon: Icon(Icons.close, size: 16, color: color), onDeleted: () => _toggleChartField(field)));
                    }).toList(),
                  ),
                ),
              ),
              IconButton(icon: Icon(_isChartExpanded ? Icons.fullscreen_exit : Icons.fullscreen, size: 20), onPressed: () => setState(() => _isChartExpanded = !_isChartExpanded), tooltip: _isChartExpanded ? 'Сжать график' : 'Развернуть график'),
              IconButton(icon: const Icon(Icons.close), onPressed: () { setState(() { _isChartVisible = false; _selectedChartFields.clear(); _fieldToColor.clear(); _chartSpotsMap.clear(); }); }, tooltip: 'Закрыть график'),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isChartLoading ? const Center(child: CircularProgressIndicator()) : _chartSpotsMap.isEmpty ? const Center(child: Text('Нажмите на иконку 📈 в заголовке колонки, чтобы построить график', style: TextStyle(color: Colors.grey))) : LayoutBuilder(
              builder: (context, constraints) {
                double maxAbsValue = 0;
                for (final spots in _chartSpotsMap.values) {
                  for (final spot in spots) {
                    final abs = spot.y.abs();
                    if (abs > maxAbsValue) maxAbsValue = abs;
                  }
                }
                if (maxAbsValue == 0) maxAbsValue = 1;
                final Map<int, double> firstXForDay = {};
                for (final spots in _chartSpotsMap.values) {
                  for (final spot in spots) {
                    final dayKey = (spot.x / (1000 * 3600 * 24)).floor();
                    firstXForDay.putIfAbsent(dayKey, () => spot.x);
                  }
                }
                final allDayKeys = firstXForDay.keys.toList()..sort();
                final int totalDays = allDayKeys.length;
                int step = totalDays < 32 ? 1 : (totalDays < 63 ? 2 : (totalDays < 93 ? 5 : 10));
                final Set<int> visibleDays = {};
                for (int i = 0; i < totalDays; i += step) visibleDays.add(allDayKeys[i]);
                final verticalLines = allDayKeys.map((dayKey) => VerticalLine(x: firstXForDay[dayKey]!, color: Colors.grey.withOpacity(0.5), strokeWidth: 1, dashArray: [5, 5])).toList();
                return LineChart(
                  LineChartData(
                    extraLinesData: ExtraLinesData(verticalLines: verticalLines),
                    gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.15), strokeWidth: 0.5)),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, interval: 24 * 60 * 60 * 1000, getTitlesWidget: (value, meta) {
                        final dayKey = (value / (24 * 60 * 60 * 1000)).floor();
                        if (visibleDays.contains(dayKey)) {
                          final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                          return Text(DateFormat('dd.MM').format(date), style: const TextStyle(fontSize: 10));
                        }
                        return const SizedBox.shrink();
                      })),
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 50, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 10)))),
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: true),
                    minY: -maxAbsValue,
                    maxY: maxAbsValue,
                    lineBarsData: _selectedChartFields.map((field) {
                      final spots = _chartSpotsMap[field] ?? [];
                      final color = _fieldToColor[field] ?? Colors.blue;
                      return LineChartBarData(spots: spots, isCurved: false, barWidth: 1, color: color, belowBarData: BarAreaData(show: false), dotData: FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 2, color: color, strokeColor: Colors.transparent, strokeWidth: 0)));
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildTopPanel(),
          if (_isChartVisible) _buildChartPanel(),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: PlutoGrid(
                    key: ValueKey(_columnOrderVersion),
                    columns: _columns,
                    rows: _visibleRows,
                    columnMenuDelegate: _customColumnMenuDelegate,
                    onLoaded: (PlutoGridOnLoadedEvent event) {
                      _stateManager = event.stateManager;
                      _stateManager.setShowColumnFilter(true);
                      _stateManager.setShowColumnFooter(false);
                      _stateManager.setShowLoading(true);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _loadReports();
                        _applyFrozenSettings();
                        if (_hiddenFields.isNotEmpty) {
                          final columnsToHide = _stateManager.refColumns.where((col) => _hiddenFields.contains(col.field)).toList();
                          if (columnsToHide.isNotEmpty) _stateManager.hideColumns(columnsToHide, true);
                        }
                        _stateManager.setShowLoading(false);
                      });
                    },
                    onColumnsMoved: (event) { if (!_ignoreNextColumnMove) _saveColumnOrder(source: 'onColumnsMoved'); },
                    onChanged: (PlutoGridOnChangedEvent event) {
                      if (event.column != null && event.row != null && totalFields.contains(event.column!.field)) {
                        try {
                          final json = <String, dynamic>{};
                          for (final field in ReportDetail.getFieldNames()) {
                            final cell = event.row!.cells[field];
                            if (cell != null) json[field] = cell.value;
                          }
                          for (final field in totalFields) {
                            final cell = event.row!.cells[field];
                            if (cell != null) json[field] = cell.value;
                          }
                          final totalValue = _calculateTotalDirectly(json);
                          event.row!.cells['total']?.value = totalValue;
                          _stateManager.notifyListeners();
                          _updateColumnStatistics();
                        } catch (e) {}
                      }
                    },
                    configuration: PlutoGridConfiguration(
                      columnSize: const PlutoGridColumnSizeConfig(autoSizeMode: PlutoAutoSizeMode.scale),
                      style: PlutoGridStyleConfig(
                        enableGridBorderShadow: true,
                        gridBorderColor: Colors.grey[300]!,
                        activatedColor: Colors.blue[100]!,
                        activatedBorderColor: Colors.blue,
                        cellColorInEditState: Colors.yellow[50]!,
                        cellTextStyle: const TextStyle(fontSize: 10),
                        columnTextStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        iconColor: Colors.blueGrey,
                        rowHeight: 30,
                        columnHeight: 275,
                      ),
                      scrollbar: const PlutoGridScrollbarConfig(isAlwaysShown: true, scrollbarThickness: 8, scrollbarThicknessWhileDragging: 12),
                    ),
                  ),
                ),
                if (_hasMoreRows && _visibleRows.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.grey[50],
                    child: Center(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.expand_more, size: 20),
                        label: Text('Показать еще ($_chunkSize) • Загружено ${_visibleRows.length}/$_totalRecordsInDB', style: const TextStyle(fontSize: 14)),
                        onPressed: _loadMoreData,
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), backgroundColor: Colors.blue[600], foregroundColor: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applyFrozenSettings() async {
    if (_stateManager == null) return;
    final frozenMap = await _aggregationSettings.getAllFrozen();
    for (final entry in frozenMap.entries) {
      final field = entry.key;
      final frozenValue = entry.value;
      PlutoColumn? column;
      try {
        column = _stateManager.refColumns.originalList.firstWhere((col) => col.field == field);
      } on StateError catch (_) { column = null; }
      if (column != null) {
        PlutoColumnFrozen frozen;
        if (frozenValue == 'start') frozen = PlutoColumnFrozen.start;
        else if (frozenValue == 'end') frozen = PlutoColumnFrozen.end;
        else continue;
        _stateManager.toggleFrozenColumn(column, frozen);
      }
    }
  }

  double _calculateTotalDirectly(Map<String, dynamic> record) {
    double total = 0.0;
    for (final field in totalFields) {
      final value = record[field];
      if (value is num) total += value.toDouble();
    }
    return total;
  }

  @override
  void dispose() {
    _stateManager.dispose();
    _dateRangeController.dispose();
    _nmIdController.dispose();
    _saNameController.dispose();
    super.dispose();
  }
}