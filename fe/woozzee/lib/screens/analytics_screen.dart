import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/custom_widget_data.dart';
import '../models/image_data.dart';
import '../widgets/product_slide.dart';
import '../widgets/chart/minimalist_chart_painter.dart';
import '../utils/color_utils.dart';
import '../utils/photo_cache_manager.dart';
import '../utils/token_manager.dart';
import '../utils/product_manager.dart';
import '../utils/widget_table_data_manager.dart';
import '../utils/chart_data_manager.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> with TickerProviderStateMixin {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  List<int> _filteredIndices = [];
  int _currentProductIndex = 0;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isControlPanelVisible = false;
  bool _isProductsPanelCollapsed = false;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  String _animationSpeed = 'обычно';
  final List<String> _animationSpeeds = ['очень медленно', 'медленно', 'обычно', 'пауза', 'быстро'];
  String _backgroundMode = 'обычный';
  final List<String> _backgroundModes = [
    'обычный', 'легкое размытие', 'размытие', 'сильное размытие',
    'легкое затемнение', 'затемнение', 'сильное затемнение', 'размытие + затемнение'
  ];

  final Map<String, Future<Map<String, dynamic>>> _chartDataCache = {};
  final Map<String, DateTime> _chartDataCacheTime = {};
  final Duration _chartDataCacheDuration = Duration(minutes: 5);
  final Map<int, Future<Map<String, dynamic>>> _productDataFutures = {};

  String? _draggingDividerWidgetId;
  double _dragStartX = 0.0;
  double _dragStartColumnWidth = 0.0;
  bool _isDraggingDivider = false;

  final WidgetTableDataManager _tableDataManager = WidgetTableDataManager();
  final TableDataProvider _tableDataProvider = TableDataProvider();
  final ChartDataManager _chartDataManager = ChartDataManager();

  static const double leftWidgetPadding = 120.0;

  List<CustomWidgetData> _customWidgets = [];
  bool _isWidgetEditMode = false;
  CustomWidgetData? _selectedWidget;
  Offset? _dragStartPosition;
  Offset? _widgetStartPosition;
  Size? _widgetStartSize;

  final ScrollController _widgetsScrollController = ScrollController();
  double _totalWidgetsHeight = 0;

  static const double widgetPadding = 16.0;
  static const double widgetSpacing = 12.0;

  double _pageScrollOffset = 0.0;
  bool _isUpdatingWidgets = false;

  final Map<String, TextEditingController> _titleControllers = {};
  final Map<String, FocusNode> _titleFocusNodes = {};

  MouseCursor _currentCursor = MouseCursor.defer;
  String _currentResizeDirection = '';

  final FocusNode _focusNode = FocusNode();
  late PageController _pageController;

  final Map<int, List<ImageData>> _imageCache = {};
  final Map<int, bool> _isPreloading = {};
  final Set<int> _cachedPages = {};
  final int _pageCacheSize = 3;

  final PhotoCacheManager _photoCache = PhotoCacheManager();
  final TokenManager _tokenManager = TokenManager();

  bool _isAnimationSpeedExpanded = false;
  bool _isBackgroundModeExpanded = false;
  bool _isContextMenuOpen = false;
  Offset? _contextMenuPosition;
  final GlobalKey _contextMenuKey = GlobalKey();
  OverlayEntry? _currentControlPanelEntry;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 1.0, keepPage: true);
    _pageController.addListener(_handlePageScroll);
    _focusNode.requestFocus();
    _loadSettings();
    _loadCustomWidgets();
    _initPhotoCache();
    _initAllProductsData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateTotalWidgetsHeight();
      _updateAllWidgetsPositions();
    });
  }

  Future<void> _initPhotoCache() async {
    try {
      await _photoCache.initialize();
      _loadProducts();
    } catch (e) {
      _loadProducts();
    }
  }

  Future<void> _initAllProductsData() async {
    try {
      await _tableDataProvider.initializeAllData();
    } catch (e) {}
  }

  Future<void> _loadProducts() async {
    try {
      setState(() { _isLoading = true; _hasError = false; });
      final productManager = ProductManager();
      if (!productManager.isInitialized) await productManager.initialize();
      final productsWithPhotos = productManager.productsWithPhotos;
      final List<Map<String, dynamic>> processedProducts = [];
      for (var product in productsWithPhotos) {
        final productImages = product.getPhotoUrls();
        if (productImages.isNotEmpty) {
          processedProducts.add({
            'nmID': product.nmID.toString(),
            'vendorCode': product.vendorCode,
            'title': product.title,
            'subjectName': product.subjectName,
            'images': productImages,
          });
        }
      }
      setState(() {
        _products = processedProducts;
        _filteredProducts = List.from(processedProducts);
        _filteredIndices = List.generate(processedProducts.length, (i) => i);
        _isLoading = false;
      });
      if (processedProducts.isNotEmpty) {
        await _preloadProductImages(0);
        _updatePageCache(0);
      }
      productManager.addListener(() { if (mounted) setState(() {}); });
    } catch (e) {
      setState(() { _isLoading = false; _hasError = true; });
    }
  }

  Future<List<ImageData>> _loadProductImages(int productIndex) async {
    if (productIndex >= _products.length) return [];
    final product = _products[productIndex];
    final images = List<String>.from(product['images'] ?? []);
    final nmId = int.tryParse(product['nmID']?.toString() ?? '0');
    if (nmId == null || nmId == 0 || images.isEmpty) return [];
    final screenHeight = MediaQuery.of(context).size.height;
    final imageWidth = screenHeight * (900 / 1200);
    final List<ImageData> loadedImages = [];
    for (int i = 0; i < images.length; i++) {
      loadedImages.add(ImageData(
        key: ValueKey('${productIndex}_${nmId}_$i'),
        width: imageWidth,
        height: screenHeight,
        imageUrl: images[i],
        productIndex: productIndex,
        imageIndex: i,
        nmId: nmId,
      ));
    }
    return loadedImages;
  }

  Future<void> _preloadProductImages(int productIndex, {bool forceReload = false}) async {
    if (productIndex >= _products.length) return;
    if (_imageCache.containsKey(productIndex) && !forceReload) return;
    if (_isPreloading[productIndex] == true) return;
    setState(() { _isPreloading[productIndex] = true; });
    try {
      final images = await _loadProductImages(productIndex);
      if (mounted) setState(() { _imageCache[productIndex] = images; _isPreloading[productIndex] = false; });
    } catch (e) { if (mounted) setState(() { _isPreloading[productIndex] = false; }); }
  }

  void _updatePageCache(int currentFilteredIndex) {
    _cachedPages.clear();
    for (int offset = -_pageCacheSize; offset <= _pageCacheSize; offset++) {
      final targetIndex = (currentFilteredIndex + offset + _filteredIndices.length) % _filteredIndices.length;
      if (targetIndex < _filteredIndices.length) {
        final productIndex = _filteredIndices[targetIndex];
        _cachedPages.add(productIndex);
        if (!_imageCache.containsKey(productIndex)) _preloadProductImages(productIndex);
      }
    }
  }

  void _filterProducts(String query) {
    setState(() {
      _searchQuery = query;
      _filteredIndices.clear();
      if (query.isEmpty) {
        _filteredProducts = List.from(_products);
        _filteredIndices = List.generate(_products.length, (i) => i);
      } else {
        _filteredProducts = _products.where((p) =>
            (p['title']?.toString().toLowerCase() ?? '').contains(query.toLowerCase()) ||
            (p['nmID']?.toString().toLowerCase() ?? '').contains(query.toLowerCase()) ||
            (p['vendorCode']?.toString().toLowerCase() ?? '').contains(query.toLowerCase()) ||
            (p['subjectName']?.toString().toLowerCase() ?? '').contains(query.toLowerCase())
        ).toList();
        for (int i = 0; i < _products.length; i++) {
          final p = _products[i];
          if ((p['title']?.toString().toLowerCase() ?? '').contains(query.toLowerCase()) ||
              (p['nmID']?.toString().toLowerCase() ?? '').contains(query.toLowerCase()) ||
              (p['vendorCode']?.toString().toLowerCase() ?? '').contains(query.toLowerCase()) ||
              (p['subjectName']?.toString().toLowerCase() ?? '').contains(query.toLowerCase())) {
            _filteredIndices.add(i);
          }
        }
      }
      if (_filteredIndices.isNotEmpty && !_filteredIndices.contains(_currentProductIndex)) {
        _currentProductIndex = _filteredIndices[0];
        _pageController.jumpToPage(0);
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _filterProducts('');
  }

  void _onPageChanged(int filteredIndex) {
    if (filteredIndex < _filteredIndices.length) {
      setState(() { _currentProductIndex = _filteredIndices[filteredIndex]; });
      _clearProductDataCacheForCurrentProduct();
      _updatePageCache(filteredIndex);
    }
  }

  void _clearProductDataCacheForCurrentProduct() {
    if (_currentProductIndex < _products.length) {
      final nmId = int.tryParse(_products[_currentProductIndex]['nmID']?.toString() ?? '0');
      if (nmId != null && nmId != 0) {
        _tableDataProvider.clearCache(nmId: nmId);
        setState(() {});
      }
    }
  }

  Future<void> _clearCacheForCurrentProduct() async {
    if (_products.isEmpty || _currentProductIndex >= _products.length) return;
    final product = _products[_currentProductIndex];
    final nmId = int.tryParse(product['nmID']?.toString() ?? '0');
    if (nmId == null || nmId == 0) return;
    setState(() { _isLoading = true; });
    try {
      await _photoCache.clearCacheForProduct(nmId);
      _imageCache.remove(_currentProductIndex);
      _cachedPages.remove(_currentProductIndex);
      _productDataFutures.remove(nmId);
      await _preloadProductImages(_currentProductIndex, forceReload: true);
      _showSuccessSnackbar('Кэш очищен для товара $nmId');
    } catch (e) { _showErrorSnackbar('Ошибка: $e'); }
    finally { if (mounted) setState(() { _isLoading = false; }); }
  }

  void _goToNextProduct() {
    if (_filteredIndices.isEmpty) return;
    int currentFilteredIndex = _filteredIndices.indexOf(_currentProductIndex);
    if (currentFilteredIndex == -1) currentFilteredIndex = 0;
    final nextFilteredIndex = (currentFilteredIndex + 1) % _filteredIndices.length;
    _pageController.animateToPage(nextFilteredIndex, duration: Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _goToPreviousProduct() {
    if (_filteredIndices.isEmpty) return;
    int currentFilteredIndex = _filteredIndices.indexOf(_currentProductIndex);
    if (currentFilteredIndex == -1) currentFilteredIndex = _filteredIndices.length - 1;
    final prevFilteredIndex = (currentFilteredIndex - 1 + _filteredIndices.length) % _filteredIndices.length;
    _pageController.animateToPage(prevFilteredIndex, duration: Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _goToProduct(int index) {
    final filteredIndex = _filteredIndices.indexOf(index);
    if (filteredIndex != -1) _pageController.animateToPage(filteredIndex, duration: Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  // ---------- Custom Widgets ----------
  Future<void> _loadCustomWidgets() async {
    final prefs = await SharedPreferences.getInstance();
    final widgetsJson = prefs.getString('customWidgets');
    if (widgetsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(widgetsJson);
        setState(() { _customWidgets = decoded.map((item) => CustomWidgetData.fromJson(item)).toList(); _updateTotalWidgetsHeight(); });
      } catch (e) {}
    }
  }

  Future<void> _saveCustomWidgets() async {
    final prefs = await SharedPreferences.getInstance();
    final widgetsJson = jsonEncode(_customWidgets.map((w) => w.toJson()).toList());
    await prefs.setString('customWidgets', widgetsJson);
  }

  void _updateTotalWidgetsHeight() {
    if (_customWidgets.isEmpty) { _totalWidgetsHeight = 0; return; }
    double maxBottom = 0;
    for (var w in _customWidgets) {
      if (!w.isFixedLayer) {
        final bottom = w.top + w.height;
        if (bottom > maxBottom) maxBottom = bottom;
      }
    }
    _totalWidgetsHeight = maxBottom + widgetPadding * 2;
    final screenHeight = MediaQuery.of(context).size.height;
    if (_totalWidgetsHeight < screenHeight) _totalWidgetsHeight = screenHeight;
  }

  void _updateAllWidgetsPositions() {
    if (_isUpdatingWidgets) return;
    _isUpdatingWidgets = true;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final containerHeight = _totalWidgetsHeight < screenHeight ? screenHeight : _totalWidgetsHeight;
    for (var w in _customWidgets) w.updateAbsoluteValues(screenWidth, screenHeight, containerHeight);
    _isUpdatingWidgets = false;
  }

  void _updateWidgetsPositions(double availableWidth, double screenHeight, double containerHeight) {
    if (_isUpdatingWidgets) return;
    _isUpdatingWidgets = true;
    final fullWidth = MediaQuery.of(context).size.width;
    for (var w in _customWidgets) w.updateAbsoluteValues(fullWidth, screenHeight, containerHeight);
    _isUpdatingWidgets = false;
  }

  void _addCustomWidget() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final double panelWidth = _isProductsPanelCollapsed ? 60 : screenWidth / 6;
    final double availableWidth = screenWidth - panelWidth;
    final double widthPercent = 0.3;
    final int baseRowCount = 3;
    final double headerHeight = 40.0, verticalPadding = 16.0;
    final double requiredHeight = headerHeight + verticalPadding + (baseRowCount * 48.0);
    final double heightPercent = requiredHeight / screenHeight;
    double topPercent = widgetPadding / screenHeight;
    double leftPercent = widgetPadding / availableWidth;
    if (_selectedWidget != null) {
      final selectedBottom = _selectedWidget!.top + _selectedWidget!.height;
      topPercent = (selectedBottom + widgetSpacing) / screenHeight;
      leftPercent = _selectedWidget!.leftPercent;
    } else if (_customWidgets.isNotEmpty) {
      final regular = _customWidgets.where((w) => !w.isFixedLayer).toList();
      if (regular.isNotEmpty) {
        final last = regular.last;
        topPercent = (last.top + last.height + widgetSpacing) / screenHeight;
        leftPercent = last.leftPercent;
      }
    }
    final newWidget = CustomWidgetData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      leftPercent: leftPercent,
      topPercent: topPercent,
      widthPercent: widthPercent,
      heightPercent: heightPercent,
      isEditing: true,
      widgetType: 'table',
      widgetTitle: 'Новая таблица',
    );
    final nameOptions = _tableDataManager.getAvailableAttributes();
    for (int i = 0; i < baseRowCount && i < nameOptions.length; i++) newWidget.tableAttributes[i] = nameOptions[i];
    setState(() {
      _customWidgets.add(newWidget);
      _selectedWidget = newWidget;
      _isWidgetEditMode = true;
      _updateTotalWidgetsHeight();
      _updateAllWidgetsPositions();
    });
    _saveCustomWidgets();
  }

  void _removeCustomWidget(String widgetId) {
    _titleControllers.remove(widgetId)?.dispose();
    _titleFocusNodes.remove(widgetId)?.dispose();
    _hideWidgetControlPanel();
    setState(() {
      _customWidgets.removeWhere((w) => w.id == widgetId);
      if (_selectedWidget?.id == widgetId) _selectedWidget = null;
      _updateTotalWidgetsHeight();
      _updateAllWidgetsPositions();
    });
    _saveCustomWidgets();
  }

  void _toggleWidgetEditMode() {
    setState(() {
      _isWidgetEditMode = !_isWidgetEditMode;
      if (!_isWidgetEditMode) {
        _hideWidgetControlPanel();
        for (var w in _customWidgets) { w.isEditing = false; w.isTitleEditing = false; }
        _selectedWidget = null;
      }
    });
  }

  void _selectWidget(CustomWidgetData widget) {
    if (!_isWidgetEditMode) return;
    setState(() {
      for (var w in _customWidgets) { w.isEditing = false; w.isTitleEditing = false; }
      widget.isEditing = true;
      _selectedWidget = widget;
    });
    _showWidgetControlPanel(widget);
  }

  void _showWidgetControlPanel(CustomWidgetData widget) {
    final context = widget.widgetKey.currentContext;
    if (context == null) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final widgetPosition = renderBox.localToGlobal(Offset.zero);
    final widgetSize = renderBox.size;
    final screenSize = MediaQuery.of(context).size;
    final panelWidth = _calculatePanelWidth(widget.widgetType);
    const panelHeight = 56.0;
    double panelLeft = widgetPosition.dx;
    double panelTop = widgetPosition.dy + widgetSize.height + 8;
    if (panelTop + panelHeight > screenSize.height - 16) panelTop = widgetPosition.dy - panelHeight - 8;
    if (panelTop < 16) panelTop = widgetPosition.dy + widgetSize.height + 8;
    if (panelLeft + panelWidth > screenSize.width - 16) panelLeft = screenSize.width - panelWidth - 16;
    if (panelLeft < 16) panelLeft = 16;
    _hideWidgetControlPanel();
    _currentControlPanelEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: panelLeft,
        top: panelTop,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: panelWidth,
            height: panelHeight,
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[700]!),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)],
            ),
            child: _buildControlPanelContent(widget),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_currentControlPanelEntry!);
  }

  void _hideWidgetControlPanel() {
    _currentControlPanelEntry?.remove();
    _currentControlPanelEntry = null;
  }

  double _calculatePanelWidth(String widgetType) {
    const double baseButtonWidth = 48.0;
    const double horizontalPadding = 24.0;
    int buttonCount = 5;
    if (widgetType == 'table') buttonCount += 2;
    if (widgetType == 'chart') buttonCount += 4; // настройки, 2 чекбокса, обновить
    return (buttonCount * baseButtonWidth) + horizontalPadding;
  }

  Widget _buildControlPanelContent(CustomWidgetData widget) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildControlPanelButton(icon: widget.isTitleVisible ? Icons.title : Icons.visibility_off,
            color: widget.isTitleVisible ? Colors.teal : Colors.grey,
            tooltip: widget.isTitleVisible ? 'Скрыть заголовок' : 'Показать заголовок',
            onTap: () => _toggleWidgetTitleVisibility(widget.id)),
        _buildControlPanelButton(icon: widget.isTitleEditing ? Icons.check : Icons.edit_note,
            color: widget.isTitleEditing ? Colors.green : Colors.blue,
            tooltip: widget.isTitleEditing ? 'Сохранить заголовок' : 'Редактировать заголовок',
            onTap: () => _toggleTitleEditing(widget.id)),
        _buildControlPanelButton(icon: _getWidgetTypeIcon(widget.widgetType),
            color: _getWidgetTypeColor(widget.widgetType),
            tooltip: 'Изменить тип виджета', onTap: () => _showWidgetTypeMenu(widget.id)),
        _buildControlPanelButton(icon: widget.isFixedLayer ? Icons.lock : Icons.lock_open,
            color: widget.isFixedLayer ? Colors.purple : Colors.amber,
            tooltip: widget.isFixedLayer ? 'Открепить слой' : 'Закрепить на слое',
            onTap: () => _toggleWidgetFixedLayer(widget.id)),
        _buildControlPanelButton(icon: Icons.delete_outline, color: Colors.red,
            tooltip: 'Удалить виджет', onTap: () => _removeCustomWidget(widget.id)),
        if (widget.widgetType == 'table') ...[
          _buildControlPanelButton(icon: widget.isFirstColumnVisible ? Icons.view_column : Icons.view_column_outlined,
              color: widget.isFirstColumnVisible ? Colors.blue : Colors.grey,
              tooltip: widget.isFirstColumnVisible ? 'Скрыть первый столбец' : 'Показать первый столбец',
              onTap: () => _toggleFirstColumnVisibility(widget.id)),
          _buildControlPanelButton(icon: Icons.add, color: Colors.green,
              tooltip: 'Добавить строку', onTap: () => _addTableRow(widget.id)),
          _buildControlPanelButton(icon: Icons.remove, color: widget.tableAttributes.length > 1 ? Colors.red : Colors.grey,
              tooltip: widget.tableAttributes.length > 1 ? 'Удалить последнюю строку' : 'Невозможно удалить единственную строку',
              onTap: () => widget.tableAttributes.length > 1 ? _removeLastTableRow(widget.id) : null),
        ],
        if (widget.widgetType == 'chart') ...[
          _buildControlPanelButton(icon: Icons.tune, color: Colors.purple,
              tooltip: 'Настройки графика', onTap: () => _showChartSettings(widget.id)),
          _buildControlPanelButton(icon: widget.showFBO ? Icons.check_box : Icons.check_box_outline_blank,
              color: widget.showFBO ? Colors.green : Colors.grey,
              tooltip: widget.showFBO ? 'Скрыть FBO' : 'Показать FBO',
              onTap: () => _toggleChartLine(widget.id, 'fbo')),
          _buildControlPanelButton(icon: widget.showFBS ? Icons.check_box : Icons.check_box_outline_blank,
              color: widget.showFBS ? Colors.blue : Colors.grey,
              tooltip: widget.showFBS ? 'Скрыть FBS' : 'Показать FBS',
              onTap: () => _toggleChartLine(widget.id, 'fbs')),
          _buildControlPanelButton(icon: Icons.refresh, color: Colors.amber,
              tooltip: 'Обновить данные графика', onTap: () => _refreshChartData(widget.id)),
        ],
      ],
    );
  }

  Widget _buildControlPanelButton({required IconData icon, required Color color, required String tooltip, required VoidCallback? onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.5), width: 1.5),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  void _toggleWidgetTitleVisibility(String widgetId) {
    final idx = _customWidgets.indexWhere((w) => w.id == widgetId);
    if (idx == -1) return;
    setState(() {
      _customWidgets[idx].isTitleVisible = !_customWidgets[idx].isTitleVisible;
      if (!_customWidgets[idx].isTitleVisible) {
        _customWidgets[idx].isTitleEditing = false;
        if (_titleControllers.containsKey(widgetId)) _customWidgets[idx].widgetTitle = _titleControllers[widgetId]!.text;
      }
    });
    _saveCustomWidgets();
  }

  void _toggleTitleEditing(String widgetId) {
    final idx = _customWidgets.indexWhere((w) => w.id == widgetId);
    if (idx == -1) return;
    if (!_customWidgets[idx].isTitleVisible) _customWidgets[idx].isTitleVisible = true;
    setState(() {
      _customWidgets[idx].isTitleEditing = !_customWidgets[idx].isTitleEditing;
      if (!_titleControllers.containsKey(widgetId)) _titleControllers[widgetId] = TextEditingController(text: _customWidgets[idx].widgetTitle);
      if (!_titleFocusNodes.containsKey(widgetId)) _titleFocusNodes[widgetId] = FocusNode();
      if (_customWidgets[idx].isTitleEditing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _titleFocusNodes[widgetId]?.requestFocus();
          _titleControllers[widgetId]?.selection = TextSelection(baseOffset: 0, extentOffset: _titleControllers[widgetId]!.text.length);
        });
      } else {
        _customWidgets[idx].widgetTitle = _titleControllers[widgetId]?.text ?? _customWidgets[idx].widgetTitle;
        _saveCustomWidgets();
      }
    });
  }

  void _saveWidgetTitle(String widgetId) {
    final idx = _customWidgets.indexWhere((w) => w.id == widgetId);
    if (idx == -1) return;
    setState(() {
      _customWidgets[idx].isTitleEditing = false;
      if (_titleControllers.containsKey(widgetId)) _customWidgets[idx].widgetTitle = _titleControllers[widgetId]!.text;
    });
    _saveCustomWidgets();
  }

  void _showWidgetTypeMenu(String widgetId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('Выберите тип виджета', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTypeOption('table', 'Таблица', Icons.table_chart, Colors.green, widgetId),
            SizedBox(height: 8),
            _buildTypeOption('text', 'Текст', Icons.text_fields, Colors.blue, widgetId),
            SizedBox(height: 8),
            _buildTypeOption('chart', 'График', Icons.bar_chart, Colors.orange, widgetId),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeOption(String type, String label, IconData icon, Color color, String widgetId) {
    return ListTile(
      dense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: Colors.white)),
      tileColor: Colors.grey[800],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: color.withOpacity(0.3))),
      onTap: () { Navigator.pop(context); _changeWidgetType(widgetId, type); },
    );
  }

  void _changeWidgetType(String widgetId, String newType) {
    final widget = _customWidgets.firstWhere((w) => w.id == widgetId);
    setState(() {
      widget.widgetType = newType;
      if (newType == 'table' && widget.tableAttributes.isEmpty) {
        final nameOptions = _tableDataManager.getAvailableAttributes();
        if (nameOptions.isNotEmpty) widget.tableAttributes[0] = nameOptions[0];
      }
    });
    _saveCustomWidgets();
  }

  void _toggleWidgetFixedLayer(String widgetId) {
    final widget = _customWidgets.firstWhere((w) => w.id == widgetId);
    final currentAbsoluteWidth = widget.width;
    final currentAbsoluteHeight = widget.height;
    setState(() {
      widget.isFixedLayer = !widget.isFixedLayer;
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      final availableWidth = screenWidth - (_isProductsPanelCollapsed ? 60 : screenWidth / 6);
      final heightReference = widget.isFixedLayer ? screenHeight : _totalWidgetsHeight;
      widget.width = currentAbsoluteWidth;
      widget.height = currentAbsoluteHeight;
      widget.leftPercent = widget.left / availableWidth;
      widget.topPercent = widget.top / heightReference;
      widget.widthPercent = widget.width / availableWidth;
      widget.heightPercent = widget.height / heightReference;
      _updateTotalWidgetsHeight();
      _updateAllWidgetsPositions();
    });
    _saveCustomWidgets();
  }

  void _toggleFirstColumnVisibility(String widgetId) {
    final idx = _customWidgets.indexWhere((w) => w.id == widgetId);
    if (idx == -1) return;
    setState(() { _customWidgets[idx].isFirstColumnVisible = !_customWidgets[idx].isFirstColumnVisible; });
    _saveCustomWidgets();
  }

  void _addTableRow(String widgetId) {
    final widget = _customWidgets.firstWhere((w) => w.id == widgetId);
    if (widget.widgetType != 'table') return;
    setState(() {
      final nameOptions = _tableDataManager.getAvailableAttributes();
      final nextIndex = widget.tableAttributes.length;
      if (nameOptions.isNotEmpty) widget.tableAttributes[nextIndex] = nameOptions[0];
      final double newHeight = 40.0 + 16.0 + (widget.tableAttributes.length * widget.baseRowHeight);
      widget.height = newHeight;
      widget.heightPercent = newHeight / (widget.isFixedLayer ? MediaQuery.of(context).size.height : _totalWidgetsHeight);
      _updateTotalWidgetsHeight();
      _updateAllWidgetsPositions();
    });
    _saveCustomWidgets();
  }

  void _removeLastTableRow(String widgetId) {
    final widget = _customWidgets.firstWhere((w) => w.id == widgetId);
    if (widget.widgetType != 'table' || widget.tableAttributes.length <= 1) return;
    setState(() {
      final lastIndex = widget.tableAttributes.length - 1;
      final Map<int, String> newAttributes = {};
      for (int i = 0; i < lastIndex; i++) newAttributes[i] = widget.tableAttributes[i]!;
      widget.tableAttributes = newAttributes;
      final double newHeight = 40.0 + 16.0 + (widget.tableAttributes.length * widget.baseRowHeight);
      widget.height = newHeight;
      widget.heightPercent = newHeight / (widget.isFixedLayer ? MediaQuery.of(context).size.height : _totalWidgetsHeight);
      _updateTotalWidgetsHeight();
      _updateAllWidgetsPositions();
    });
    _saveCustomWidgets();
  }

  void _updateTableWidgetData(String widgetId, int rowIndex, String name) {
    final widget = _customWidgets.firstWhere((w) => w.id == widgetId);
    setState(() { widget.tableAttributes[rowIndex] = name; });
    _saveCustomWidgets();
  }

  void _updateTableColumnWidths(String widgetId, List<double> widths) {
    final widget = _customWidgets.firstWhere((w) => w.id == widgetId);
    setState(() { widget.tableColumnWidths = widths; });
    _saveCustomWidgets();
  }

  void _startWidgetInteraction(CustomWidgetData widget, Offset localPosition) {
    if (!_isWidgetEditMode) return;
    final handleSize = 20.0;
    final resizeDirection = _getResizeDirection(localPosition, widget, handleSize);
    setState(() {
      if (resizeDirection.isNotEmpty) {
        widget.isResizing = true;
        widget.resizeDirection = resizeDirection;
        _dragStartPosition = localPosition;
        _widgetStartPosition = Offset(widget.left, widget.top);
        _widgetStartSize = Size(widget.width, widget.height);
      } else {
        _dragStartPosition = localPosition;
        _widgetStartPosition = Offset(widget.left, widget.top);
        _widgetStartSize = null;
        _selectWidget(widget);
      }
    });
  }

  void _updateWidgetInteraction(CustomWidgetData widget, Offset localPosition) {
    if (!_isWidgetEditMode || _dragStartPosition == null || _widgetStartPosition == null) return;
    if (_isDraggingDivider) return;
    final delta = localPosition - _dragStartPosition!;
    if (widget.isResizing) _updateWidgetResize(widget, delta);
    else _updateWidgetDrag(widget, delta);
  }

  void _updateWidgetDrag(CustomWidgetData widget, Offset delta) {
    _hideWidgetControlPanel();
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final availableWidth = screenWidth - (_isProductsPanelCollapsed ? 60 : screenWidth / 6);
    if (widget.isFixedLayer) {
      double newLeft = _widgetStartPosition!.dx + delta.dx;
      double newTop = _widgetStartPosition!.dy + delta.dy;
      newLeft = newLeft.clamp(leftWidgetPadding, availableWidth - widget.width - widgetPadding);
      newTop = newTop.clamp(widgetPadding, screenHeight - widget.height - widgetPadding);
      setState(() { widget.left = newLeft; widget.top = newTop; widget.leftPercent = widget.left / availableWidth; widget.topPercent = widget.top / screenHeight; });
    } else {
      double newLeft = _widgetStartPosition!.dx + delta.dx;
      double newTop = _widgetStartPosition!.dy + delta.dy;
      newLeft = newLeft.clamp(leftWidgetPadding, availableWidth - widget.width - widgetPadding);
      newTop = newTop.clamp(widgetPadding, _totalWidgetsHeight - widget.height - widgetPadding);
      setState(() { widget.left = newLeft; widget.top = newTop; widget.leftPercent = widget.left / availableWidth; widget.topPercent = widget.top / _totalWidgetsHeight; });
    }
  }

  void _updateWidgetResize(CustomWidgetData widget, Offset delta) {
    _hideWidgetControlPanel();
    if (_widgetStartSize == null) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final availableWidth = screenWidth - (_isProductsPanelCollapsed ? 60 : screenWidth / 6);
    final containerHeight = widget.isFixedLayer ? screenHeight : _totalWidgetsHeight;
    final direction = widget.resizeDirection;
    double newLeft = _widgetStartPosition!.dx;
    double newTop = _widgetStartPosition!.dy;
    double newWidth = _widgetStartSize!.width;
    double newHeight = _widgetStartSize!.height;
    const minWidth = 100.0;
    const minRowHeight = 40.0;
    if (direction.contains('w')) {
      newLeft = _widgetStartPosition!.dx + delta.dx;
      newWidth = _widgetStartSize!.width - delta.dx;
      if (newWidth < minWidth) { newWidth = minWidth; newLeft = _widgetStartPosition!.dx + _widgetStartSize!.width - minWidth; }
    }
    if (direction.contains('e')) { newWidth = _widgetStartSize!.width + delta.dx; if (newWidth < minWidth) newWidth = minWidth; }
    if (direction.contains('n')) { newTop = _widgetStartPosition!.dy + delta.dy; newHeight = _widgetStartSize!.height - delta.dy; }
    if (direction.contains('s')) { newHeight = _widgetStartSize!.height + delta.dy; }
    newWidth = newWidth.clamp(minWidth, availableWidth - widgetPadding * 2);
    newHeight = newHeight.clamp(minRowHeight, containerHeight - widgetPadding * 2);
    newLeft = newLeft.clamp(widgetPadding, availableWidth - newWidth - widgetPadding);
    newTop = newTop.clamp(widgetPadding, containerHeight - newHeight - widgetPadding);
    setState(() {
      widget.left = newLeft; widget.top = newTop; widget.width = newWidth; widget.height = newHeight;
      widget.leftPercent = widget.left / availableWidth;
      widget.topPercent = widget.top / containerHeight;
      widget.widthPercent = widget.width / availableWidth;
      widget.heightPercent = widget.height / containerHeight;
      if (!widget.isFixedLayer) _updateTotalWidgetsHeight();
    });
  }

  void _endWidgetInteraction() {
    _dragStartPosition = null;
    _widgetStartPosition = null;
    _widgetStartSize = null;
    for (var w in _customWidgets) { w.isResizing = false; w.resizeDirection = ''; }
    _endDividerDrag();
    _currentCursor = MouseCursor.defer;
    _currentResizeDirection = '';
    _updateTotalWidgetsHeight();
    _updateAllWidgetsPositions();
    if (_selectedWidget != null && _selectedWidget!.isEditing) WidgetsBinding.instance.addPostFrameCallback((_) => _showWidgetControlPanel(_selectedWidget!));
    _saveCustomWidgets();
  }

  String _getResizeDirection(Offset localPosition, CustomWidgetData widget, double handleSize) {
    if (localPosition.dx <= handleSize && localPosition.dy <= handleSize) return 'nw';
    if (localPosition.dx >= widget.width - handleSize && localPosition.dy <= handleSize) return 'ne';
    if (localPosition.dx <= handleSize && localPosition.dy >= widget.height - handleSize) return 'sw';
    if (localPosition.dx >= widget.width - handleSize && localPosition.dy >= widget.height - handleSize) return 'se';
    if (localPosition.dx <= handleSize) return 'w';
    if (localPosition.dx >= widget.width - handleSize) return 'e';
    if (localPosition.dy <= handleSize) return 'n';
    if (localPosition.dy >= widget.height - handleSize) return 's';
    return '';
  }

  void _endDividerDrag() { setState(() { _draggingDividerWidgetId = null; _isDraggingDivider = false; }); }

  // ---------- Chart methods ----------
  void _showChartSettings(String widgetId) {
    final widget = _customWidgets.firstWhere((w) => w.id == widgetId);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('Настройки графика', style: TextStyle(color: Colors.white)),
        content: SizedBox(width: 300, child: _buildChartSettingsForm(widget)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Отмена', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () { _saveCustomWidgets(); Navigator.pop(context); }, child: Text('Сохранить', style: TextStyle(color: Colors.blue))),
        ],
      ),
    );
  }

  Widget _buildChartSettingsForm(CustomWidgetData widget) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Тип данных:', style: TextStyle(color: Colors.white70, fontSize: 12)),
          DropdownButton<String>(
            value: widget.chartDataType,
            onChanged: (v) { setState(() { widget.chartDataType = v!; }); },
            items: ChartDataManager.availableChartTypes.map((type) => DropdownMenuItem(value: type, child: Text(type, style: TextStyle(color: Colors.white)))).toList(),
            dropdownColor: Colors.grey[800], style: TextStyle(color: Colors.white), isExpanded: true,
          ),
          SizedBox(height: 16),
          Text('Период:', style: TextStyle(color: Colors.white70, fontSize: 12)),
          DropdownButton<String>(
            value: widget.chartPeriod,
            onChanged: (v) {
              setState(() {
                widget.chartPeriod = v!;
                if (v != 'custom') {
                  final days = _getDaysForPeriod(v);
                  if (days != null) {
                    widget.chartDateTo = DateTime.now();
                    widget.chartDateFrom = widget.chartDateTo!.subtract(Duration(days: days));
                  }
                }
              });
            },
            items: ChartDataManager.periodPresets.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value['name']!, style: TextStyle(color: Colors.white)))).toList(),
            dropdownColor: Colors.grey[800], style: TextStyle(color: Colors.white), isExpanded: true,
          ),
          if (widget.chartPeriod == 'custom') ...[
            SizedBox(height: 12),
            _buildDateRow('С:', widget.chartDateFrom, (date) { setState(() { widget.chartDateFrom = date; }); }),
            _buildDateRow('По:', widget.chartDateTo, (date) { setState(() { widget.chartDateTo = date; }); }),
          ],
          SizedBox(height: 16),
          Text('Отображать:', style: TextStyle(color: Colors.white70, fontSize: 12)),
          Row(children: [
            Checkbox(value: widget.showFBO, onChanged: (v) { setState(() { widget.showFBO = v!; }); }, checkColor: Colors.white, activeColor: Colors.green),
            Text('FBO', style: TextStyle(color: Colors.green)),
            SizedBox(width: 20),
            Checkbox(value: widget.showFBS, onChanged: (v) { setState(() { widget.showFBS = v!; }); }, checkColor: Colors.white, activeColor: Colors.blue),
            Text('FBS', style: TextStyle(color: Colors.blue)),
          ]),
        ],
      ),
    );
  }

  Widget _buildDateRow(String label, DateTime? date, Function(DateTime) onChanged) {
    return Row(
      children: [
        Text(label, style: TextStyle(color: Colors.white70, fontSize: 12)),
        SizedBox(width: 8),
        Expanded(
          child: TextButton(
            onPressed: () async {
              final selected = await showDatePicker(context: context, initialDate: date ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(Duration(days: 365)), lastDate: DateTime.now(),
                  builder: (c, child) => Theme(data: ThemeData.dark().copyWith(colorScheme: ColorScheme.dark(primary: Colors.blue)), child: child!));
              if (selected != null) onChanged(selected);
            },
            child: Text(date != null ? '${date.day}.${date.month}.${date.year}' : 'Выберите дату', style: TextStyle(color: Colors.white)),
            style: TextButton.styleFrom(backgroundColor: Colors.grey[800]),
          ),
        ),
      ],
    );
  }

  int? _getDaysForPeriod(String period) {
    const daysMap = {'7_days': 7, '30_days': 30, '90_days': 90};
    return daysMap[period];
  }

  void _toggleChartLine(String widgetId, String lineType) {
    final widget = _customWidgets.firstWhere((w) => w.id == widgetId);
    setState(() {
      if (lineType == 'fbo') widget.showFBO = !widget.showFBO;
      else if (lineType == 'fbs') widget.showFBS = !widget.showFBS;
    });
    _saveCustomWidgets();
  }

  void _refreshChartData(String widgetId) {
    final widget = _customWidgets.firstWhere((w) => w.id == widgetId);
    final currentProduct = _products.isNotEmpty && _currentProductIndex < _products.length ? _products[_currentProductIndex] : null;
    if (currentProduct != null) {
      final nmId = int.tryParse(currentProduct['nmID']?.toString() ?? '0');
      if (nmId != null) {
        _chartDataManager.clearCache(nmId: nmId);
        setState(() {});
      }
    }
  }

  // ---------- Table build helpers ----------
  Map<int, String> _getTableWidgetData(String widgetId) => _customWidgets.firstWhere((w) => w.id == widgetId).tableAttributes;
  List<double> _getTableColumnWidths(String widgetId) => _customWidgets.firstWhere((w) => w.id == widgetId).tableColumnWidths;

  String _getProductValue(Map<String, dynamic> productData, String attributeName) {
    switch (attributeName) {
      case 'Артикул': return productData['nm_id']?.toString() ?? '';
      case 'Мой артикул': return productData['vendor_code']?.toString() ?? '';
      case 'Баркод': return productData['barcode']?.toString() ?? '';
      case 'Наименование': return productData['title']?.toString() ?? '';
      case 'Остаток FBO': return productData['total_quantity']?.toString() ?? '0';
      case 'Остаток FBS': return productData['fbs_quantity']?.toString() ?? '0';
      case 'Тэги': return (productData['tags'] as List? ?? []).map((t) => t['name']?.toString() ?? '').where((n) => n.isNotEmpty).join(', ');
      default: return 'Недоступно';
    }
  }

  Color _getValueColor(String attributeName, String value) {
    if (value.isEmpty || value == '0') return Colors.white.withOpacity(0.5);
    if (attributeName == 'Остаток FBO' || attributeName == 'Остаток FBS') {
      final intValue = int.tryParse(value) ?? 0;
      if (intValue <= 0) return Colors.red.withOpacity(0.8);
      if (intValue <= 10) return Colors.orange.withOpacity(0.8);
      return Colors.green.withOpacity(0.8);
    }
    return Colors.white.withOpacity(0.8);
  }

  // ---------- UI Components ----------
  void _toggleProductsPanel() {
    setState(() { _isProductsPanelCollapsed = !_isProductsPanelCollapsed; });
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateAllWidgetsPositions());
    _saveProductsPanelCollapsed(_isProductsPanelCollapsed);
  }

  void _toggleControlPanelVisibility() { setState(() { _isControlPanelVisible = !_isControlPanelVisible; }); _saveControlPanelVisibility(_isControlPanelVisible); }
  void _toggleAnimationSpeed() { final next = (_animationSpeeds.indexOf(_animationSpeed) + 1) % _animationSpeeds.length; setState(() { _animationSpeed = _animationSpeeds[next]; }); _saveAnimationSpeed(_animationSpeed); }
  void _toggleBackgroundMode() { final next = (_backgroundModes.indexOf(_backgroundMode) + 1) % _backgroundModes.length; setState(() { _backgroundMode = _backgroundModes[next]; }); _saveBackgroundMode(_backgroundMode); }

  double _getAnimationSpeed() {
    switch (_animationSpeed) {
      case 'очень медленно': return 20.0;
      case 'медленно': return 40.0;
      case 'обычно': return 80.0;
      case 'быстро': return 160.0;
      default: return 0.0;
    }
  }
  bool get _isAnimationPaused => _animationSpeed == 'пауза';

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _animationSpeed = prefs.getString('animationSpeed') ?? 'обычно';
      _backgroundMode = prefs.getString('backgroundMode') ?? 'обычный';
      _isControlPanelVisible = prefs.getBool('isControlPanelVisible') ?? false;
      _isProductsPanelCollapsed = prefs.getBool('isProductsPanelCollapsed') ?? false;
    });
  }
  void _saveAnimationSpeed(String v) async => (await SharedPreferences.getInstance()).setString('animationSpeed', v);
  void _saveBackgroundMode(String v) async => (await SharedPreferences.getInstance()).setString('backgroundMode', v);
  void _saveControlPanelVisibility(bool v) async => (await SharedPreferences.getInstance()).setBool('isControlPanelVisible', v);
  void _saveProductsPanelCollapsed(bool v) async => (await SharedPreferences.getInstance()).setBool('isProductsPanelCollapsed', v);

  void _showErrorSnackbar(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  void _showSuccessSnackbar(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.arrowLeft) _goToPreviousProduct();
    if (key == LogicalKeyboardKey.keyD || key == LogicalKeyboardKey.arrowRight) _goToNextProduct();
    if (event.character == 'ф') _goToPreviousProduct();
    if (event.character == 'в') _goToNextProduct();
    if (key == LogicalKeyboardKey.keyC) _clearCacheForCurrentProduct();
    if (key == LogicalKeyboardKey.keyH) _toggleControlPanelVisibility();
    if (key == LogicalKeyboardKey.keyM) _showContextMenuAtCenter();
    if (key == LogicalKeyboardKey.keyP) _toggleProductsPanel();
    if (key == LogicalKeyboardKey.keyF && !_isProductsPanelCollapsed) _searchFocusNode.requestFocus();
    if (key == LogicalKeyboardKey.escape && _searchFocusNode.hasFocus) _searchFocusNode.unfocus();
    if (key == LogicalKeyboardKey.keyW) _toggleWidgetEditMode();
  }

  void _showContextMenuAtCenter() {
    final size = MediaQuery.of(context).size;
    _showContextMenuDialog(Offset(size.width / 2, size.height / 2));
  }

  void _showContextMenuDialog(Offset position) {
    if (_isContextMenuOpen) Navigator.of(context).pop();
    setState(() { _contextMenuPosition = position; _isAnimationSpeedExpanded = false; _isBackgroundModeExpanded = false; _isContextMenuOpen = true; });
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Stack(
        children: [
          Positioned.fill(child: GestureDetector(
            onTap: () { Navigator.pop(context); setState(() { _contextMenuPosition = null; _isContextMenuOpen = false; }); },
            onSecondaryTapDown: (d) { Navigator.pop(context); _showContextMenuDialog(d.globalPosition); },
            child: Container(color: Colors.transparent),
          )),
          if (_contextMenuPosition != null)
            Positioned(
              left: _contextMenuPosition!.dx, top: _contextMenuPosition!.dy,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 300,
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
                  decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[700]!),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)]),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
                            child: Row(children: [Icon(Icons.settings, color: Colors.white, size: 20), SizedBox(width: 8), Text('Контекстное меню', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))])),
                        _buildMenuExpansion('Скорость анимации', _animationSpeed, _animationSpeeds, (v) { Navigator.pop(context); setState(() { _animationSpeed = v; }); _saveAnimationSpeed(v); }, Icons.speed, _getAnimationSpeedColor),
                        Divider(color: Colors.grey),
                        _buildMenuExpansion('Фон', _backgroundMode, _backgroundModes, (v) { Navigator.pop(context); setState(() { _backgroundMode = v; }); _saveBackgroundMode(v); }, Icons.brush, Colors.blue),
                        Divider(color: Colors.grey),
                        _buildMenuItem(icon: _isProductsPanelCollapsed ? Icons.chevron_right : Icons.chevron_left, color: Colors.blue,
                            title: _isProductsPanelCollapsed ? 'Развернуть панель товаров' : 'Свернуть панель товаров', onTap: () { Navigator.pop(context); _toggleProductsPanel(); }),
                        _buildMenuItem(icon: Icons.delete, color: Colors.red, title: 'Очистить кэш текущего товара', onTap: () { Navigator.pop(context); _clearCacheForCurrentProduct(); }),
                        _buildMenuItem(icon: _isControlPanelVisible ? Icons.visibility_off : Icons.visibility, color: Colors.blue,
                            title: _isControlPanelVisible ? 'Скрыть панель управления' : 'Показать панель управления', onTap: () { Navigator.pop(context); _toggleControlPanelVisibility(); }),
                        Divider(color: Colors.grey),
                        Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), color: Colors.grey[800],
                            child: Text('Кастомные виджеты', style: TextStyle(color: Colors.grey[300], fontSize: 12, fontWeight: FontWeight.bold))),
                        _buildMenuItem(icon: Icons.add, color: Colors.teal, title: 'Добавить новый виджет', onTap: () { Navigator.pop(context); _addCustomWidget(); }),
                        _buildMenuItem(icon: _isWidgetEditMode ? Icons.done : Icons.edit, color: _isWidgetEditMode ? Colors.orange : Colors.blue,
                            title: _isWidgetEditMode ? 'Завершить редактирование' : 'Редактировать виджеты', onTap: () { Navigator.pop(context); _toggleWidgetEditMode(); }),
                        Container(padding: EdgeInsets.all(12), color: Colors.grey[800],
                            child: Text('Используйте ПКМ или клавишу M для открытия меню\nP - панель товаров, F - поиск, W - редактирование виджетов\nВ режиме редактирования: перетаскивайте виджеты и изменяйте размер\nНажмите на замок, чтобы зафиксировать виджет на слое выше',
                                style: TextStyle(color: Colors.grey[500], fontSize: 10), textAlign: TextAlign.center)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ).then((_) => setState(() { _contextMenuPosition = null; _isContextMenuOpen = false; }));
  }

  Widget _buildMenuExpansion(String title, String currentValue, List<String> values, Function(String) onSelect, IconData icon, Color iconColor) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.symmetric(horizontal: 12),
        title: Row(children: [Icon(icon, color: iconColor, size: 20), SizedBox(width: 8), Text('$title: $currentValue', style: TextStyle(color: Colors.grey[300], fontSize: 14))]),
        trailing: Icon(values == _animationSpeeds ? (_isAnimationSpeedExpanded ? Icons.expand_less : Icons.expand_more) : (_isBackgroundModeExpanded ? Icons.expand_less : Icons.expand_more), color: Colors.grey[400], size: 20),
        onExpansionChanged: (expanded) => setState(() { if (values == _animationSpeeds) _isAnimationSpeedExpanded = expanded; else _isBackgroundModeExpanded = expanded; }),
        children: values.map((v) => ListTile(
          dense: true, visualDensity: VisualDensity(horizontal: 0, vertical: -4), contentPadding: EdgeInsets.only(left: 40, right: 16),
          leading: Icon(v == currentValue ? Icons.check_circle : Icons.circle_outlined, color: v == currentValue ? Colors.green : Colors.grey[600], size: 16),
          title: Text(v, style: TextStyle(color: v == currentValue ? Colors.white : Colors.grey[300], fontSize: 13)),
          onTap: () => onSelect(v),
        )).toList(),
      ),
    );
  }

  Widget _buildMenuItem({required IconData icon, required Color color, required String title, required VoidCallback onTap}) {
    return ListTile(
      dense: true, visualDensity: VisualDensity(horizontal: 0, vertical: -4), contentPadding: EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(icon, color: color, size: 20),
      title: Text(title, style: TextStyle(color: color, fontSize: 14)),
      onTap: onTap,
    );
  }

  double _calculateAdaptiveFontSize(CustomWidgetData widget, {double minSize = 8.0, double maxSize = 24.0, double heightFactor = 0.06}) {
    final ref = widget.height < widget.width ? widget.height : widget.width;
    return (ref * heightFactor).clamp(minSize, maxSize);
  }

  Color _getWidgetTypeColor(String type) => type == 'table' ? Colors.green : type == 'text' ? Colors.blue : type == 'chart' ? Colors.orange : Colors.grey;
  IconData _getWidgetTypeIcon(String type) => type == 'table' ? Icons.table_chart : type == 'text' ? Icons.text_fields : type == 'chart' ? Icons.bar_chart : Icons.question_mark;

  void _handlePageScroll() { if (_pageController.hasClients) setState(() { _pageScrollOffset = _pageController.page ?? 0; }); }

  @override
  void dispose() {
    _focusNode.dispose(); _searchFocusNode.dispose(); _searchController.dispose();
    _pageController.removeListener(_handlePageScroll); _pageController.dispose(); _widgetsScrollController.dispose();
    for (var c in _titleControllers.values) c.dispose();
    for (var fn in _titleFocusNodes.values) fn.dispose();
    _endDividerDrag();
    super.dispose();
  }

  // ---------- build methods ----------
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onSecondaryTapDown: (details) => _showContextMenuDialog(details.globalPosition),
          child: Stack(
            children: [
              Positioned.fill(child: Container(color: Colors.black, child: _buildMainContent())),
              if (_customWidgets.isNotEmpty) Positioned.fill(child: _buildCustomWidgetsOverlay(screenWidth, screenWidth)),
              Positioned(left: 0, top: 0, bottom: 0, child: _buildProductsPanel()),
            ],
          ),
        ),
        floatingActionButton: _buildFloatingActionButtons(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  Widget _buildCustomWidgetsOverlay(double panelWidth, double availableWidth) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = MediaQuery.of(context).size.height;
        final containerHeight = constraints.maxHeight;
        _updateWidgetsPositions(availableWidth, screenHeight, containerHeight);
        return Stack(
          children: [
            SingleChildScrollView(
              controller: _widgetsScrollController,
              physics: BouncingScrollPhysics(),
              child: SizedBox(height: _totalWidgetsHeight, child: Stack(children: _customWidgets.where((w) => !w.isFixedLayer).map((w) => _buildPositionedWidget(w)).toList())),
            ),
            ..._customWidgets.where((w) => w.isFixedLayer).map((w) => _buildPositionedWidget(w)),
          ],
        );
      },
    );
  }

  Widget _buildPositionedWidget(CustomWidgetData widget) => Positioned(left: widget.left, top: widget.top, child: _buildCustomWidget(widget));

  Widget _buildCustomWidget(CustomWidgetData widget) {
    return MouseRegion(
      cursor: _isWidgetEditMode ? _currentCursor : SystemMouseCursors.basic,
      onHover: (event) {
        if (!_isWidgetEditMode) return;
        final local = event.localPosition;
        final handleSize = widget.width * 0.05;
        final dir = _getResizeDirection(local, widget, handleSize);
        if (dir.isNotEmpty) {
          final newCursor = _getCursorForResizeDirection(dir);
          if (newCursor != _currentCursor) setState(() { _currentCursor = newCursor; _currentResizeDirection = dir; });
        } else if (_currentCursor != SystemMouseCursors.move) setState(() { _currentCursor = SystemMouseCursors.move; _currentResizeDirection = ''; });
      },
      onExit: (event) { if (_currentCursor != SystemMouseCursors.basic) setState(() { _currentCursor = SystemMouseCursors.basic; _currentResizeDirection = ''; }); },
      child: GestureDetector(
        onTap: () => _selectWidget(widget),
        onPanStart: (d) => _startWidgetInteraction(widget, d.localPosition),
        onPanUpdate: (d) => _updateWidgetInteraction(widget, d.localPosition),
        onPanEnd: (_) => _endWidgetInteraction(),
        onPanCancel: _endWidgetInteraction,
        child: Container(
          key: widget.widgetKey,
          width: widget.width, height: widget.height, margin: EdgeInsets.all(2), clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: widget.isEditing ? (widget.isFixedLayer ? Colors.purple.withOpacity(0.15) : Colors.blue.withOpacity(0.15)) : Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(8), child: _buildWidgetContent(widget)),
        ),
      ),
    );
  }

  Widget _buildWidgetContent(CustomWidgetData widget) {
    return Container(padding: EdgeInsets.all(8), child: Column(children: [_buildWidgetTitle(widget), Expanded(child: _buildWidgetBody(widget))]));
  }

  Widget _buildWidgetTitle(CustomWidgetData widget) {
    if (!widget.isTitleVisible && !widget.isTitleEditing) return SizedBox(height: widget.height * 0.02);
    final double fontSize = _calculateAdaptiveFontSize(widget, heightFactor: 0.08);
    final double headerHeight = (widget.height * 0.15).clamp(32.0, 60.0);
    if (widget.isTitleEditing && widget.isEditing) {
      if (!_titleControllers.containsKey(widget.id)) _titleControllers[widget.id] = TextEditingController(text: widget.widgetTitle);
      if (!_titleFocusNodes.containsKey(widget.id)) _titleFocusNodes[widget.id] = FocusNode();
      return Container(height: headerHeight, padding: EdgeInsets.symmetric(horizontal: widget.width * 0.02, vertical: widget.height * 0.01),
          child: TextField(controller: _titleControllers[widget.id], focusNode: _titleFocusNodes[widget.id],
              style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1,
              decoration: InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: widget.width * 0.02, vertical: widget.height * 0.01),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(widget.height * 0.02), borderSide: BorderSide(color: Colors.blue, width: 1)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(widget.height * 0.02), borderSide: BorderSide(color: Colors.blue, width: 1)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(widget.height * 0.02), borderSide: BorderSide(color: Colors.blue, width: 2)),
                  fillColor: Colors.black.withOpacity(0.3), filled: true),
              onSubmitted: (_) => _saveWidgetTitle(widget.id), onTapOutside: (_) => _saveWidgetTitle(widget.id)));
    } else {
      return Container(height: headerHeight, alignment: Alignment.center, padding: EdgeInsets.symmetric(horizontal: widget.width * 0.02),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (widget.widgetType.isNotEmpty && widget.isEditing) Icon(_getWidgetTypeIcon(widget.widgetType), color: _getWidgetTypeColor(widget.widgetType), size: fontSize * 0.8),
            if (widget.widgetType.isNotEmpty && widget.isEditing) SizedBox(width: 8),
            Expanded(child: Text(widget.widgetTitle, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: fontSize, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]));
    }
  }

  Widget _buildWidgetBody(CustomWidgetData widget) {
    if (widget.isEditing && widget.widgetType.isEmpty) return _buildTypeSelection(widget);
    switch (widget.widgetType) {
      case 'table': return _buildTableWidget(widget);
      case 'text': return _buildTextWidget(widget);
      case 'chart': return _buildChartWidget(widget);
      default: return _buildTypeSelection(widget);
    }
  }

  Widget _buildTypeSelection(CustomWidgetData widget) {
    final iconSize = (widget.width < widget.height ? widget.width : widget.height) * 0.2;
    return Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _buildTypeIcon(Icons.table_chart, 'table', widget, iconSize),
      SizedBox(width: 16), _buildTypeIcon(Icons.text_fields, 'text', widget, iconSize),
      SizedBox(width: 16), _buildTypeIcon(Icons.bar_chart, 'chart', widget, iconSize),
    ]));
  }

  Widget _buildTypeIcon(IconData icon, String type, CustomWidgetData widget, double size) => GestureDetector(
    onTap: () => _changeWidgetType(widget.id, type),
    child: Column(children: [
      Container(width: size, height: size, decoration: BoxDecoration(color: Colors.blue.withOpacity(0.3), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.withOpacity(0.5))),
          child: Icon(icon, size: size * 0.6, color: Colors.white)),
      SizedBox(height: 4), Text(type == 'table' ? 'Таблица' : type == 'text' ? 'Текст' : 'График', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 10))
    ]),
  );

  Widget _buildTableWidget(CustomWidgetData widget) {
    final rowCount = widget.tableAttributes.length;
    final availableHeightForRows = widget.height * 0.85 - 16;
    final rowHeight = rowCount > 0 ? (availableHeightForRows / rowCount).clamp(32.0, 80.0) : widget.baseRowHeight;
    final fontSize = _calculateAdaptiveFontSize(widget, heightFactor: rowHeight / widget.height * 0.3, minSize: 10, maxSize: 16);
    final nameOptions = _tableDataManager.getAvailableAttributes();
    final columnWidths = widget.tableColumnWidths;
    final isDraggingThisDivider = _draggingDividerWidgetId == widget.id;

    if (_products.isEmpty || _currentProductIndex >= _products.length) return _buildTableError('Товар не загружен', widget);
    final nmId = int.tryParse(_products[_currentProductIndex]['nmID']?.toString() ?? '0');
    if (nmId == null || nmId == 0) return _buildTableError('Нет данных о товаре', widget);

    if (!_productDataFutures.containsKey(nmId)) _productDataFutures[nmId] = _tableDataManager.getProductData(nmId);
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('table_${widget.id}_$nmId'),
      future: _productDataFutures[nmId]!,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return _buildTableLoading(widget);
        if (snapshot.hasError) return _buildTableError('Ошибка загрузки', widget);
        final productData = snapshot.data ?? {};
        return Container(padding: EdgeInsets.only(bottom: 4), child: Column(children: [
          Expanded(child: ListView.builder(shrinkWrap: true, physics: NeverScrollableScrollPhysics(), itemCount: rowCount,
              itemBuilder: (context, idx) => _buildTableRow(widget, productData, nameOptions, columnWidths, idx, rowHeight, fontSize, isDraggingThisDivider)))
        ]));
      },
    );
  }

  Widget _buildTableRow(CustomWidgetData widget, Map<String, dynamic> productData, List<String> nameOptions,
      List<double> columnWidths, int rowIndex, double rowHeight, double fontSize, bool isDraggingThisDivider) {
    final currentName = widget.tableAttributes[rowIndex] ?? (nameOptions.isNotEmpty ? nameOptions[0] : '');
    if (currentName == 'Тэги') {
      return _buildTagsTableRow(widget, productData, columnWidths, rowIndex, rowHeight, fontSize, isDraggingThisDivider);
    }
    final value = _getProductValue(productData, currentName);
    final horizontalPadding = widget.width * 0.01;
    final dropdownHeight = rowHeight * 0.7;
    final textVerticalPadding = rowHeight * 0.15;

    return Container(height: rowHeight, decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1), width: 0.5))),
        child: Row(children: [
          if (widget.isFirstColumnVisible) ...[
            Expanded(flex: (columnWidths[0] * 100).round(), child: Container(padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: widget.isEditing
                    ? Material(color: Colors.transparent, child: Container(height: dropdownHeight, alignment: Alignment.center,
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(rowHeight * 0.1), border: Border.all(color: Colors.blue.withOpacity(0.5))),
                        child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                          value: currentName, onChanged: (newVal) => _updateTableWidgetData(widget.id, rowIndex, newVal!),
                          items: nameOptions.map((v) => DropdownMenuItem(value: v, child: Container(padding: EdgeInsets.symmetric(horizontal: widget.width * 0.02),
                              child: Text(v, style: TextStyle(color: Colors.white, fontSize: fontSize * 0.9), overflow: TextOverflow.ellipsis, maxLines: 1)))).toList(),
                          dropdownColor: Colors.grey[900], icon: Icon(Icons.arrow_drop_down, color: Colors.white.withOpacity(0.7), size: fontSize * 1.2), isExpanded: true,
                          style: TextStyle(color: Colors.white, fontSize: fontSize * 0.9),
                        )))))
                    : Container(padding: EdgeInsets.symmetric(horizontal: widget.width * 0.02, vertical: textVerticalPadding), alignment: Alignment.centerLeft,
                        child: Text(currentName, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: fontSize), overflow: TextOverflow.ellipsis, maxLines: 2))),
            ),
            if (widget.isEditing && widget.isFirstColumnVisible)
              _buildDividerHandle(widget, columnWidths, isDraggingThisDivider),
          ],
          Expanded(flex: widget.isFirstColumnVisible ? (columnWidths[1] * 100).round() : 100,
              child: Container(padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Container(padding: EdgeInsets.symmetric(horizontal: widget.width * 0.02, vertical: textVerticalPadding),
                      alignment: widget.isFirstColumnVisible ? Alignment.centerLeft : Alignment.center,
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.1), borderRadius: BorderRadius.circular(rowHeight * 0.1)),
                      child: Text(value, style: TextStyle(color: _getValueColor(currentName, value), fontSize: fontSize, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 2)))),
        ]));
  }

  Widget _buildTagsTableRow(CustomWidgetData widget, Map<String, dynamic> productData, List<double> columnWidths,
      int rowIndex, double rowHeight, double fontSize, bool isDraggingThisDivider) {
    final tags = (productData['tags'] as List?) ?? [];
    final horizontalPadding = widget.width * 0.01;
    final textVerticalPadding = rowHeight * 0.15;
    return Container(height: rowHeight, decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1), width: 0.5))),
        child: Row(children: [
          if (widget.isFirstColumnVisible) ...[
            Expanded(flex: (columnWidths[0] * 100).round(), child: Container(padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Container(padding: EdgeInsets.symmetric(horizontal: widget.width * 0.02, vertical: textVerticalPadding), alignment: Alignment.centerLeft,
                    child: Text('Тэги', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: fontSize), overflow: TextOverflow.ellipsis, maxLines: 1)))),
            if (widget.isEditing && widget.isFirstColumnVisible) _buildDividerHandle(widget, columnWidths, isDraggingThisDivider),
          ],
          Expanded(flex: widget.isFirstColumnVisible ? (columnWidths[1] * 100).round() : 100,
              child: Container(padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Container(padding: EdgeInsets.symmetric(horizontal: widget.width * 0.02, vertical: textVerticalPadding),
                      alignment: widget.isFirstColumnVisible ? Alignment.centerLeft : Alignment.center,
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.1), borderRadius: BorderRadius.circular(rowHeight * 0.1)),
                      child: tags.isEmpty ? Text('Нет тэгов', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: fontSize))
                          : SingleChildScrollView(scrollDirection: Axis.horizontal,
                            child: Wrap(spacing: 4, runSpacing: 2, children: tags.map<Widget>((t) => _buildTagChip(t['name']?.toString() ?? '', t['color']?.toString() ?? 'D1CFD7', fontSize)).toList()))))),
        ]));
  }

  Widget _buildTagChip(String name, String colorHex, double fontSize) {
    final color = hexToColor(colorHex);
    final textColor = getContrastTextColor(color);
    return Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), margin: EdgeInsets.only(right: 4),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Text(name, style: TextStyle(color: textColor, fontSize: fontSize * 0.8, fontWeight: FontWeight.w500)));
  }

  Widget _buildDividerHandle(CustomWidgetData widget, List<double> columnWidths, bool isDraggingThisDivider) {
    return MouseRegion(cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          onPanStart: (d) { setState(() { _draggingDividerWidgetId = widget.id; _dragStartX = d.globalPosition.dx; _dragStartColumnWidth = columnWidths[0]; _isDraggingDivider = true; }); },
          onPanUpdate: (d) {
            final delta = d.globalPosition.dx - _dragStartX;
            final newFirst = (_dragStartColumnWidth + delta / (widget.width - 16)).clamp(0.1, 0.9);
            _updateTableColumnWidths(widget.id, [newFirst, 1.0 - newFirst]);
          },
          onPanEnd: (_) => _endDividerDrag(),
          child: Container(width: 4, color: isDraggingThisDivider ? Colors.blue : Colors.transparent,
              child: Container(margin: EdgeInsets.symmetric(vertical: 8), width: 1, color: isDraggingThisDivider ? Colors.blue : Colors.grey.withOpacity(0.5))),
        ));
  }

  Widget _buildTableLoading(CustomWidgetData widget) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center,
      children: [SizedBox(width: widget.height * 0.15, height: widget.height * 0.15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue)),
        SizedBox(height: widget.height * 0.02), Text('Загрузка данных...', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: _calculateAdaptiveFontSize(widget, heightFactor: 0.06, maxSize: 14))) ]));
  Widget _buildTableError(String msg, CustomWidgetData widget) => Center(child: Text(msg, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: _calculateAdaptiveFontSize(widget, heightFactor: 0.06, maxSize: 14)), textAlign: TextAlign.center));
  Widget _buildTextWidget(CustomWidgetData widget) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center,
      children: [Icon(Icons.text_fields, size: widget.height * 0.15, color: Colors.white.withOpacity(0.5)), SizedBox(height: widget.height * 0.02),
        Text('Текстовый блок', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: _calculateAdaptiveFontSize(widget, heightFactor: 0.06), fontWeight: FontWeight.bold)),
        SizedBox(height: widget.height * 0.01), Text('Текст появится позже', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: widget.height * 0.04))]));

  Widget _buildChartWidget(CustomWidgetData widget) {
    if (_products.isEmpty || _currentProductIndex >= _products.length) return _buildChartPlaceholder('Нет данных о товаре', widget);
    final nmId = int.tryParse(_products[_currentProductIndex]['nmID']?.toString() ?? '0');
    if (nmId == null || nmId == 0) return _buildChartPlaceholder('Неверный ID товара', widget);
    final cacheKey = '${widget.chartDataType}_$nmId${widget.chartPeriod}_${widget.chartDateFrom?.toIso8601String()}_${widget.chartDateTo?.toIso8601String()}_${widget.showFBO}_${widget.showFBS}';
    final now = DateTime.now();
    if (_chartDataCache.containsKey(cacheKey) && _chartDataCacheTime.containsKey(cacheKey) && now.difference(_chartDataCacheTime[cacheKey]!) < _chartDataCacheDuration) {
      return FutureBuilder<Map<String, dynamic>>(future: _chartDataCache[cacheKey]!, builder: (c, s) => _buildChartFutureBuilder(s, widget, cacheKey));
    }
    final future = _chartDataManager.getChartData(chartType: widget.chartDataType, nmId: nmId, period: widget.chartPeriod,
        customDateFrom: widget.chartDateFrom, customDateTo: widget.chartDateTo);
    _chartDataCache[cacheKey] = future; _chartDataCacheTime[cacheKey] = now;
    return FutureBuilder<Map<String, dynamic>>(future: future, builder: (c, s) => _buildChartFutureBuilder(s, widget, cacheKey));
  }

  Widget _buildChartFutureBuilder(AsyncSnapshot<Map<String, dynamic>> snapshot, CustomWidgetData widget, String cacheKey) {
    if (snapshot.connectionState == ConnectionState.waiting) return _buildChartLoading(widget);
    if (snapshot.hasError) {
      _chartDataCache.remove(cacheKey); _chartDataCacheTime.remove(cacheKey);
      return _buildChartPlaceholder('Ошибка: ${snapshot.error}', widget);
    }
    final data = snapshot.data!;
    if (!data['hasData']) return _buildChartPlaceholder(data['message'] ?? 'Нет данных', widget);
    return StatefulBuilder(builder: (ctx, setState) {
      Offset? hoverPos; int? hoverIndex; String? hoverLabel;
      return MouseRegion(
        onHover: (e) => setState(() { hoverPos = e.localPosition; }),
        onExit: (_) => setState(() { hoverPos = null; hoverIndex = null; hoverLabel = null; }),
        child: Container(padding: EdgeInsets.all(8), child: Column(children: [
          if (widget.isEditing) _buildChartLegend(data['datasets'] as List, widget),
          Expanded(child: CustomPaint(
            painter: MinimalistChartPainter(
              labels: List<String>.from(data['labels']),
              detailedLabels: List<String>.from(data['detailedLabels']),
              datasets: (data['datasets'] as List).where((ds) => (ds['label'] == 'FBO' && widget.showFBO) || (ds['label'] == 'FBS' && widget.showFBS)).toList(),
              widgetHeight: widget.height, widgetWidth: widget.width, hoverPosition: hoverPos,
              timestamps: List<DateTime>.from(data['timestamps']),
              onHover: (idx, lbl) { setState(() { hoverIndex = idx; hoverLabel = lbl; }); },
            ),
          )),
          if (widget.isEditing) _buildChartFooter(data, widget, hoverIndex, hoverLabel),
        ])),
      );
    });
  }

  Widget _buildChartLegend(List<Map<String, dynamic>> datasets, CustomWidgetData widget) => Container(padding: EdgeInsets.only(bottom: 8),
      child: Wrap(spacing: 16, children: datasets.map((ds) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: hexToColor(ds['color']?.toString() ?? '#FFFFFF'), shape: BoxShape.circle)),
        SizedBox(width: 4), Text(ds['label']?.toString() ?? '', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: widget.height * 0.03))
      ])).toList()));

  Widget _buildChartFooter(Map<String, dynamic> chartData, CustomWidgetData widget, int? hoverIndex, String? hoverLabel) {
    final period = chartData['period'] ?? '30_days';
    final periodName = ChartDataManager.periodPresets[period]?['name'] ?? 'Произвольный';
    String hoverInfo = '';
    if (hoverIndex != null && hoverLabel != null) {
      final timestamps = List<DateTime>.from(chartData['timestamps'] ?? []);
      if (hoverIndex < timestamps.length) {
        const months = ['янв','фев','мар','апр','май','июн','июл','авг','сен','окт','ноя','дек'];
        final t = timestamps[hoverIndex];
        hoverInfo = ' • $hoverLabel в ${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')} ${t.day} ${months[t.month-1]}';
      }
    }
    return Container(padding: EdgeInsets.only(top: 8),
        child: Text('Период: $periodName$hoverInfo', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: widget.height * 0.025), textAlign: TextAlign.center));
  }

  Widget _buildChartLoading(CustomWidgetData widget) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    SizedBox(width: widget.height * 0.1, height: widget.height * 0.1, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue)),
    SizedBox(height: widget.height * 0.02), Text('Загрузка данных графика...', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: widget.height * 0.04))
  ]));
  Widget _buildChartPlaceholder(String msg, CustomWidgetData widget) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.bar_chart, size: widget.height * 0.15, color: Colors.white.withOpacity(0.3)),
    SizedBox(height: widget.height * 0.02), Text(msg, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: widget.height * 0.04))
  ]));

  SystemMouseCursor _getCursorForResizeDirection(String dir) {
    switch (dir) {
      case 'n': case 's': return SystemMouseCursors.resizeUpDown;
      case 'e': case 'w': return SystemMouseCursors.resizeLeftRight;
      case 'nw': case 'se': return SystemMouseCursors.resizeUpLeftDownRight;
      case 'ne': case 'sw': return SystemMouseCursors.resizeUpRightDownLeft;
      default: return SystemMouseCursors.move;
    }
  }

  Widget _buildProductsPanel() {
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = screenWidth / 6;
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      width: _isProductsPanelCollapsed ? 60 : panelWidth,
      decoration: BoxDecoration(color: Colors.grey[900], border: Border(right: BorderSide(color: Colors.grey[800]!, width: 1)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.7), blurRadius: 10, spreadRadius: 2)]),
      child: Column(children: [
        Container(height: 60, padding: EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.grey[800], border: Border(bottom: BorderSide(color: Colors.grey[700]!, width: 1))),
            child: _isProductsPanelCollapsed ? GestureDetector(onTap: _toggleProductsPanel, child: Center(child: RotatedBox(quarterTurns: 1,
                child: AnimatedSwitcher(duration: Duration(milliseconds: 300), child: Text('${_currentProductIndex + 1}', key: ValueKey(_currentProductIndex), style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))))))
                : Row(children: [Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text('Товары', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('${_filteredProducts.length} из ${_products.length}', style: TextStyle(color: Colors.grey[400], fontSize: 11))])),
                    IconButton(icon: Icon(Icons.chevron_left, color: Colors.white, size: 20), onPressed: _toggleProductsPanel, tooltip: 'Свернуть панель (P)')])),
        if (!_isProductsPanelCollapsed)
          Padding(padding: EdgeInsets.all(12), child: Container(decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Expanded(child: TextField(controller: _searchController, focusNode: _searchFocusNode, onChanged: _filterProducts,
                    decoration: InputDecoration(hintText: 'Поиск товаров...', hintStyle: TextStyle(color: Colors.grey, fontSize: 12), border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), prefixIcon: Icon(Icons.search, color: Colors.grey, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: Icon(Icons.close, color: Colors.grey, size: 16), onPressed: _clearSearch) : null),
                    style: TextStyle(color: Colors.white, fontSize: 12), cursorColor: Colors.blue)),
              ]))),
        Expanded(child: _isProductsPanelCollapsed
            ? GestureDetector(onTap: _toggleProductsPanel, child: Center(child: RotatedBox(quarterTurns: 1,
                child: Container(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Товар ${_currentProductIndex + 1} из ${_products.length}', style: TextStyle(color: Colors.grey, fontSize: 11))))))
            : _buildProductsList()),
      ]),
    );
  }

  Widget _buildProductsList() {
    if (_filteredProducts.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.search_off, color: Colors.grey, size: 40), SizedBox(height: 12),
        Text(_searchQuery.isEmpty ? 'Нет товаров' : 'Ничего не найдено', style: TextStyle(color: Colors.grey, fontSize: 12)),
        if (_searchQuery.isNotEmpty) TextButton(onPressed: _clearSearch, child: Text('Очистить поиск', style: TextStyle(fontSize: 11))),
      ]));
    }
    return ListView.builder(
      itemCount: _filteredProducts.length,
      padding: EdgeInsets.only(bottom: 8),
      itemBuilder: (context, index) {
        final originalIndex = _filteredIndices[index];
        final isCurrent = originalIndex == _currentProductIndex;
        return AnimatedContainer(duration: Duration(milliseconds: 200), margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: isCurrent ? Colors.blue.withOpacity(0.2) : Colors.transparent, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isCurrent ? Colors.blue.withOpacity(0.5) : Colors.transparent)),
            child: Material(color: Colors.transparent, child: InkWell(onTap: () => _goToProduct(originalIndex), borderRadius: BorderRadius.circular(8),
                child: Container(padding: EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_filteredProducts[index]['title']?.toString() ?? 'Без названия', style: TextStyle(color: isCurrent ? Colors.blue : Colors.white, fontSize: 11, fontWeight: FontWeight.w500, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                  SizedBox(height: 6),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_filteredProducts[index]['nmID']}', style: TextStyle(color: isCurrent ? Colors.blue.shade300 : Colors.grey[400], fontSize: 9)),
                    SizedBox(height: 2),
                    Text('${_filteredProducts[index]['vendorCode']}', style: TextStyle(color: isCurrent ? Colors.blue.shade300 : Colors.grey[400], fontSize: 9)),
                  ]),
                  SizedBox(height: 6),
                  Text(_filteredProducts[index]['subjectName']?.toString() ?? 'Без категории', style: TextStyle(color: isCurrent ? Colors.blue.shade300 : Colors.grey[500], fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])))));
      },
    );
  }

  Widget _buildMainContent() {
    if (_isLoading) return _buildLoadingScreen();
    if (_hasError) return _buildErrorScreen();
    if (_products.isEmpty) return _buildEmptyScreen();
    return PageView.builder(
      controller: _pageController,
      onPageChanged: _onPageChanged,
      itemCount: _filteredIndices.length,
      scrollDirection: Axis.horizontal,
      pageSnapping: true,
      physics: PageScrollPhysics(),
      itemBuilder: (context, filteredIdx) {
        final actualIdx = _filteredIndices[filteredIdx];
        final images = _imageCache[actualIdx] ?? [];
        final isPreloading = _isPreloading[actualIdx] == true;
        if (images.isNotEmpty && !isPreloading) {
          return ProductSlide(
            key: ValueKey('product_$actualIdx'),
            product: _products[actualIdx],
            productIndex: actualIdx,
            totalProducts: _products.length,
            images: images,
            isPreloadingThis: false,
            animationSpeed: _animationSpeed,
            filmSpeed: _getAnimationSpeed(),
            isAnimationPaused: _isAnimationPaused,
            backgroundMode: _backgroundMode,
            onClearCache: _clearCacheForCurrentProduct,
          );
        }
        return Container(color: Colors.black, child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(strokeWidth: 2), SizedBox(height: 20),
          Text('Загрузка товара...', style: TextStyle(color: Colors.grey.shade600, fontSize: 16))
        ])));
      },
    );
  }

  Widget _buildLoadingScreen() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    CircularProgressIndicator(strokeWidth: 2), SizedBox(height: 20),
    Text('Загружаем каталог товаров...', style: TextStyle(color: Colors.grey.shade600, fontSize: 16))
  ]));
  Widget _buildErrorScreen() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.error_outline, size: 64, color: Colors.red), SizedBox(height: 20),
    Text('Ошибка загрузки товаров', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    SizedBox(height: 10), Text('Проверьте подключение к серверу'), SizedBox(height: 20),
    ElevatedButton(onPressed: _loadProducts, child: Text('Повторить попытку'))
  ]));
  Widget _buildEmptyScreen() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.image_search, size: 64, color: Colors.grey), SizedBox(height: 20),
    Text('Нет товаров с фотографиями', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    SizedBox(height: 10), Text('Загрузите товары с фотографиями в базу данных'), SizedBox(height: 20),
    ElevatedButton(onPressed: _loadProducts, child: Text('Обновить'))
  ]));

  Widget _buildFloatingActionButtons() {
    if (!_isControlPanelVisible || _products.isEmpty) return SizedBox.shrink();
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _fab(Icons.arrow_back, () => _goToPreviousProduct(), 'Предыдущий товар (A/←)'),
      SizedBox(width: 10),
      _fab(_animationSpeed == 'пауза' ? Icons.play_arrow : Icons.speed, _toggleAnimationSpeed, 'Скорость анимации'),
      SizedBox(width: 10),
      _fab(Icons.brush, _toggleBackgroundMode, 'Режим фона'),
      SizedBox(width: 10),
      _fab(Icons.add, _addCustomWidget, 'Добавить виджет', bgColor: Colors.teal),
      SizedBox(width: 10),
      _fab(_isWidgetEditMode ? Icons.done : Icons.edit, _toggleWidgetEditMode, 'Режим редактирования виджетов (W)', bgColor: _isWidgetEditMode ? Colors.orange : Colors.grey),
      SizedBox(width: 10),
      _fab(Icons.menu, () => _showContextMenuAtCenter(), 'Контекстное меню (M/ПКМ)', bgColor: Colors.purple),
      SizedBox(width: 10),
      _fab(Icons.delete, _clearCacheForCurrentProduct, 'Очистить кэш текущего товара (C)', bgColor: Colors.red),
      SizedBox(width: 10),
      _fab(_isControlPanelVisible ? Icons.visibility_off : Icons.visibility, _toggleControlPanelVisibility, 'Скрыть/показать панель (H)'),
      SizedBox(width: 10),
      _fab(_isProductsPanelCollapsed ? Icons.chevron_right : Icons.chevron_left, _toggleProductsPanel, 'Панель товаров (P)', bgColor: Colors.blue),
      SizedBox(width: 10),
      _fab(Icons.arrow_forward, () => _goToNextProduct(), 'Следующий товар (D/→)'),
    ]);
  }

  Widget _fab(IconData icon, VoidCallback onTap, String tooltip, {Color? bgColor}) => FloatingActionButton(
    onPressed: onTap, backgroundColor: (bgColor ?? Colors.black).withOpacity(0.6),
    child: Icon(icon, color: Colors.white), tooltip: tooltip,
  );
}