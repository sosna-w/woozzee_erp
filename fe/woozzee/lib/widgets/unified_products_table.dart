// unified_products_table.dart - ИСПРАВЛЕННАЯ ВЕРСИЯ
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:excel/excel.dart' as excel_package;
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'tag_manager.dart';
import 'package:open_file/open_file.dart';
import 'dart:async';

class UnifiedProductsTable extends StatefulWidget {
  const UnifiedProductsTable({super.key});

  @override
  State<UnifiedProductsTable> createState() => _UnifiedProductsTableState();
}

class _UnifiedProductsTableState extends State<UnifiedProductsTable>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<dynamic> _allProducts = [];
  List<dynamic> _filteredProducts = [];
  List<dynamic> _displayProducts = [];
  bool _isLoading = false;
  bool _hasError = false;

  int _currentPage = 0;
  int _itemsPerPage = 50;
  int _totalCount = 0;

  final Map<int, Map<String, dynamic>> _localState = {};
  final Map<int, Timer> _configTimers = {};
  final Map<int, int> _countdownTimers = {};

  // Добавляем переменную для хранения индивидуальных конфигураций
  Map<int, Map<String, dynamic>> _productAutoConfigs = {};

  final Map<String, double> _columnWidths = {
    'nm_id': 90.0,
    'vendor_code': 300.0,
    'barcode': 120.0,
    'title': 500.0,
    'tags': 150.0,
    'total_quantity': 50.0,
    'fbs_quantity': 50.0,
    'fbo_threshold': 65.0,
    'fbs_minimum': 65.0,
    'auto_replenishment': 65.0,
    'updating': 50.0,
    'change_quantity': 100.0,
  };

  final FocusNode _focusNode = FocusNode();
  String? _sortColumn;
  bool _sortAscending = true;
  final Map<String, List<String>> _filters = {};
  final Map<String, bool> _filterVisibility = {};
  final Map<String, TextEditingController> _filterSearchControllers = {};

  final Map<String, GlobalKey> _filterButtonKeys = {};
  String? _currentOpenFilter;

  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  final GlobalKey _tableKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();

    for (final columnKey in _columnWidths.keys) {
      final columnLabel = _getColumnLabel(columnKey);
      _filterButtonKeys[columnLabel] = GlobalKey();
    }

    _loadAllData();
    TagManager().loadTags();
  }

  @override
  void dispose() {
    _configTimers.forEach((id, timer) => timer.cancel());
    _configTimers.clear();
    _countdownTimers.clear();

    _focusNode.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _filterSearchControllers.values.forEach((controller) => controller.dispose());
    super.dispose();
  }

  // ДОБАВЛЕН НОВЫЙ МЕТОД ДЛЯ ЗАГРУЗКИ ИНДИВИДУАЛЬНЫХ КОНФИГУРАЦИЙ
  Future<void> _loadProductAutoConfigs() async {
    try {
      final response = await http.get(
        Uri.parse('https://hide_domain.com/product-auto-config?per_page=10000'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final configs = data['product_auto_configs'] as List<dynamic>;

        setState(() {
          _productAutoConfigs = {};
          for (final config in configs) {
            final nmId = config['nm_id'] as int;
            _productAutoConfigs[nmId] = {
              'fbo_threshold': config['fbo_threshold']?.toString() ?? '',
              'fbs_minimum': config['fbs_minimum']?.toString() ?? '',
              'ignore_auto_replenishment': config['ignore_auto_replenishment'] ?? false,
            };
          }
        });

        print('✅ Загружено индивидуальных конфигураций: ${_productAutoConfigs.length}');
      } else {
        print('⚠️ Ошибка загрузки индивидуальных конфигураций: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Ошибка при загрузке индивидуальных конфигураций: $e');
    }
  }

  // ОБНОВЛЕННЫЙ МЕТОД ЗАГРУЗКИ ДАННЫХ
  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // Сначала загружаем основные данные
      final response = await http.get(
        Uri.parse('https://hide_domain.com/unified-products?per_page=10000'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final products = data['unified_products'] as List<dynamic>;

        // Затем загружаем индивидуальные конфигурации
        await _loadProductAutoConfigs();

        // Инициализируем локальное состояние с учетом индивидуальных конфигураций
        for (var product in products) {
          final id = product['id'];
          final nmId = product['nm_id'] as int;

          // Проверяем, есть ли индивидуальная конфигурация для этого товара
          final autoConfig = _productAutoConfigs[nmId];

          if (autoConfig != null) {
            // Используем значения из индивидуальной конфигурации
            _localState[id] = {
              'fbo_threshold': autoConfig['fbo_threshold'] ?? '',
              'fbs_minimum': autoConfig['fbs_minimum'] ?? '',
              'auto_replenishment': autoConfig['ignore_auto_replenishment'] ?? false,
              'updating': false,
              'change_quantity': '',
            };
          } else {
            // Используем значения по умолчанию
            _localState[id] = {
              'fbo_threshold': '',
              'fbs_minimum': '',
              'auto_replenishment': false,
              'updating': false,
              'change_quantity': '',
            };
          }
        }

        if (mounted) {
          setState(() {
            _allProducts = products;
            _totalCount = products.length;
            _applyFiltersAndSorting();
            _hasError = false;
          });
        }
      } else {
        _showErrorSnackbar('Ошибка загрузки: ${response.statusCode}');
        if (mounted) {
          setState(() {
            _hasError = true;
          });
        }
      }
    } catch (e) {
      _showErrorSnackbar('Ошибка подключения: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _closeAllFilters() {
    setState(() {
      _filterVisibility.clear();
      _currentOpenFilter = null;
    });
  }

  void _handleTableTap() {
    if (_currentOpenFilter != null) {
      _closeAllFilters();
    }
  }

  Future<void> _exportToExcel() async {
    try {
      if (_filteredProducts.isEmpty) {
        _showErrorSnackbar('Нет данных для экспорта');
        return;
      }

      setState(() {
        _isLoading = true;
      });

      var excelFile = excel_package.Excel.createExcel();
      var sheet = excelFile['Sheet1'];

      List<String> headers = [
        'Артикул WB',
        'Мой артикул',
        'Баркод',
        'Наименование',
        'Тэги',
        'FBO',
        'FBS'
      ];

      for (int i = 0; i < headers.length; i++) {
        sheet.cell(excel_package.CellIndex.indexByString("${String.fromCharCode(65 + i)}1")).value = headers[i];
      }

      for (int i = 0; i < _filteredProducts.length; i++) {
        var product = _filteredProducts[i];

        sheet.cell(excel_package.CellIndex.indexByString("A${i + 2}")).value = product['nm_id']?.toString() ?? '';
        sheet.cell(excel_package.CellIndex.indexByString("B${i + 2}")).value = product['vendor_code']?.toString() ?? '';
        sheet.cell(excel_package.CellIndex.indexByString("C${i + 2}")).value = product['barcode']?.toString() ?? '';
        sheet.cell(excel_package.CellIndex.indexByString("D${i + 2}")).value = product['title']?.toString() ?? '';

        List<String> tags = _parseProductTags(product['tags']);
        sheet.cell(excel_package.CellIndex.indexByString("E${i + 2}")).value = tags.join(', ');

        int fboValue = int.tryParse(product['total_quantity']?.toString() ?? '0') ?? 0;
        sheet.cell(excel_package.CellIndex.indexByString("F${i + 2}")).value = fboValue;

        int fbsValue = int.tryParse(product['fbs_quantity']?.toString() ?? '0') ?? 0;
        sheet.cell(excel_package.CellIndex.indexByString("G${i + 2}")).value = fbsValue;
      }

      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить Excel файл',
        fileName: 'остатки_товаров_${DateTime.now().toString().replaceAll(RegExp(r'[^0-9]'), '_')}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputFile != null) {
        var fileBytes = excelFile.save();
        if (fileBytes != null) {
          File file = File(outputFile);
          await file.writeAsBytes(fileBytes);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Файл сохранен: ${file.path}'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Открыть',
                  textColor: Colors.blue,
                  backgroundColor: Colors.white,
                  onPressed: () async {
                    final result = await OpenFile.open(file.path);
                    if (result.type != ResultType.done) {
                      _showErrorSnackbar('Не удалось открыть файл: ${result.message}');
                    }
                  },
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при экспорте: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<String> _parseProductTags(dynamic tagsData) {
    final List<String> tagNames = [];

    if (tagsData == null) return tagNames;

    try {
      List<dynamic> tagsList;

      if (tagsData is String) {
        if (tagsData.trim().isEmpty) return tagNames;
        tagsList = json.decode(tagsData) as List<dynamic>;
      } else if (tagsData is List<dynamic>) {
        tagsList = tagsData;
      } else {
        return tagNames;
      }

      for (final tag in tagsList) {
        if (tag is Map<String, dynamic>) {
          final name = tag['name']?.toString();
          if (name != null && name.isNotEmpty) {
            tagNames.add(name);
          }
        }
      }
    } catch (e) {
      final tagsString = tagsData.toString();
      if (tagsString.isNotEmpty) {
        tagNames.addAll(tagsString.split(',').map((tag) => tag.trim()).where((tag) => tag.isNotEmpty));
      }
    }

    return tagNames;
  }

  Widget _buildNoTagsFilterPopup(String columnName, GlobalKey buttonKey) {
    final RenderBox? buttonRenderBox = buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final buttonSize = buttonRenderBox?.size ?? Size.zero;
    final buttonPosition = buttonRenderBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    return Positioned(
      left: buttonPosition.dx,
      top: buttonPosition.dy + buttonSize.height,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 300,
          height: 200,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: BoxBorder.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.local_offer_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Теги не загружены',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Загрузите теги в настройках',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _toggleFilterVisibility(columnName),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyFiltersAndSorting() {
    List<dynamic> filtered = _allProducts;

    if (_filters.isNotEmpty) {
      filtered = _allProducts.where((product) {
        for (final entry in _filters.entries) {
          final fieldName = _getFieldName(entry.key);

          if (entry.key == 'Тэги') {
            final productTags = _parseProductTags(product[fieldName]);

            if (entry.value.contains('')) {
              if (productTags.isEmpty) {
                continue;
              }
            }

            final hasMatchingTag = entry.value.any((selectedTag) =>
            selectedTag.isNotEmpty &&
                productTags.any((productTag) => productTag.contains(selectedTag))
            );

            if (!hasMatchingTag && !(entry.value.contains('') && productTags.isEmpty)) {
              return false;
            }
          } else if (entry.key == 'Игнор') {
            // Обработка фильтрации для столбца "Игнор"
            final id = product['id'];
            final localState = _localState[id];
            final bool autoReplenishmentValue = localState?['auto_replenishment'] ?? false;

            // Преобразуем булево значение в строку для сравнения
            final String stringValue = autoReplenishmentValue.toString();

            if (!entry.value.contains(stringValue)) {
              return false;
            }
          } else {
            final value = product[fieldName]?.toString() ?? '';
            if (!entry.value.contains(value)) {
              return false;
            }
          }
        }
        return true;
      }).toList();
    }

    if (_sortColumn != null) {
      final fieldName = _getFieldName(_sortColumn!);

      if (_sortColumn == 'Игнор') {
        // Специальная сортировка для столбца "Игнор"
        filtered.sort((a, b) {
          final aId = a['id'];
          final bId = b['id'];
          final aState = _localState[aId];
          final bState = _localState[bId];

          final bool aValue = aState?['auto_replenishment'] ?? false;
          final bool bValue = bState?['auto_replenishment'] ?? false;

          // true (включено) будет считаться "больше" чем false (выключено)
          if (_sortAscending) {
            return aValue == bValue ? 0 : aValue ? 1 : -1;
          } else {
            return aValue == bValue ? 0 : aValue ? -1 : 1;
          }
        });
      } else if (_isNumericField(fieldName)) {
        filtered.sort((a, b) {
          final aValue = a[fieldName];
          final bValue = b[fieldName];
          final aNum = _parseNumber(aValue);
          final bNum = _parseNumber(bValue);
          return _sortAscending ? aNum.compareTo(bNum) : bNum.compareTo(aNum);
        });
      } else {
        filtered.sort((a, b) {
          final aValue = a[fieldName]?.toString() ?? '';
          final bValue = b[fieldName]?.toString() ?? '';
          final comparison = aValue.compareTo(bValue);
          return _sortAscending ? comparison : -comparison;
        });
      }
    }

    setState(() {
      _filteredProducts = filtered;
      _totalCount = filtered.length;
      _updateDisplayProducts();
    });
  }

  bool _isNumericField(String fieldName) {
    final numericFields = [
      'total_quantity', 'fbs_quantity', 'fbo_threshold',
      'fbs_minimum', 'nm_id', 'Price', 'Discount', 'quantity'
    ];
    return numericFields.contains(fieldName);
  }

  double _parseNumber(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  List<String> _getSortedValuesForColumn(String fieldName, Set<String> uniqueValues) {
    if (_isNumericField(fieldName)) {
      final numericValues = uniqueValues.map((value) {
        return double.tryParse(value) ?? 0.0;
      }).toList();

      numericValues.sort();

      return numericValues.map((numValue) {
        if (numValue % 1 == 0) {
          return numValue.toInt().toString();
        } else {
          return numValue.toString();
        }
      }).toList();
    } else {
      final valuesList = uniqueValues.toList();
      valuesList.sort();
      return valuesList;
    }
  }

  void _updateDisplayProducts() {
    final startIndex = _currentPage * _itemsPerPage;
    final endIndex = startIndex + _itemsPerPage;

    setState(() {
      _displayProducts = _filteredProducts.sublist(
        startIndex,
        endIndex > _filteredProducts.length ? _filteredProducts.length : endIndex,
      );
    });
  }

  void _handleScroll(PointerSignalEvent event) {
    if (event is PointerScrollEvent &&
        (RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
            RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.shiftRight))) {
      final double scrollDelta = event.scrollDelta.dy * 2;
      final double newOffset = _horizontalScrollController.offset + scrollDelta;

      final double maxScrollExtent = _horizontalScrollController.position.maxScrollExtent;
      final double clampedOffset = newOffset.clamp(0.0, maxScrollExtent);

      _horizontalScrollController.jumpTo(clampedOffset);
    }
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        // Обработка в родительском виджете
      }
    }
  }

  void _sortColumnBy(String columnName) {
    setState(() {
      if (_sortColumn == columnName) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = columnName;
        _sortAscending = true;
      }
    });

    _applyFiltersAndSorting();
  }

  String _getFieldName(String columnName) {
    final fieldMap = {
      'Артикул WB': 'nm_id',
      'Мой артикул': 'vendor_code',
      'Баркод': 'barcode',
      'Наименование': 'title',
      'Тэги': 'tags',
      'FBO': 'total_quantity',
      'FBS': 'fbs_quantity',
      'Порог': 'fbo_threshold',
      'Уровень FBS': 'fbs_minimum',
      'Игнор': 'auto_replenishment',
      'Изменить': 'change_quantity',
    };
    return fieldMap[columnName] ?? columnName.toLowerCase();
  }

  Widget _buildFilterButton(String columnName) {
    return IconButton(
      key: _filterButtonKeys[columnName],
      icon: Icon(
        Icons.filter_list,
        color: _filters.containsKey(columnName) ? Colors.blue : Colors.grey,
        size: 16,
      ),
      onPressed: () => _toggleFilterVisibility(columnName),
      tooltip: 'Фильтр по столбцу',
    );
  }

  void _toggleFilterVisibility(String columnName) {
    setState(() {
      if (_currentOpenFilter != null && _currentOpenFilter != columnName) {
        _filterVisibility[_currentOpenFilter!] = false;
      }

      _filterVisibility[columnName] = !(_filterVisibility[columnName] ?? false);

      if (_filterVisibility[columnName] == true) {
        _currentOpenFilter = columnName;
        if (!_filterSearchControllers.containsKey(columnName)) {
          _filterSearchControllers[columnName] = TextEditingController();
        }
      } else {
        _currentOpenFilter = null;
      }
    });
  }

  void _updateFilter(String columnName, String value, bool checked) {
    setState(() {
      if (checked) {
        if (!_filters.containsKey(columnName)) {
          _filters[columnName] = [];
        }
        _filters[columnName]!.add(value);
      } else {
        _filters[columnName]?.remove(value);
        if (_filters[columnName]?.isEmpty ?? false) {
          _filters.remove(columnName);
        }
      }
    });

    _applyFiltersAndSorting();
  }

  void _selectAllFilter(String columnName, bool selectAll) {
    setState(() {
      if (selectAll) {
        final fieldName = _getFieldName(columnName);
        final uniqueValues = <String>{};

        if (columnName == 'Тэги') {
          final availableTags = TagManager().getTagNames();
          uniqueValues.addAll(availableTags);
        } else {
          for (final product in _allProducts) {
            final value = product[fieldName]?.toString() ?? '';
            if (value.isNotEmpty) {
              uniqueValues.add(value);
            }
          }
        }

        _filters[columnName] = uniqueValues.toList();
      } else {
        _filters.remove(columnName);
      }
    });

    _applyFiltersAndSorting();
  }

  void _updateEmptyFilter(String columnName, bool includeEmpty) {
    setState(() {
      if (includeEmpty) {
        if (!_filters.containsKey(columnName)) {
          _filters[columnName] = [];
        }
        if (!_filters[columnName]!.contains('')) {
          _filters[columnName]!.add('');
        }
      } else {
        _filters[columnName]?.remove('');
        if (_filters[columnName]?.isEmpty ?? false) {
          _filters.remove(columnName);
        }
      }
    });

    _applyFiltersAndSorting();
  }

  void _clearFilters() {
    setState(() {
      _filters.clear();
      _filterVisibility.clear();
      _currentOpenFilter = null;
      _filterSearchControllers.values.forEach((controller) => controller.clear());
    });

    _applyFiltersAndSorting();
  }

  Widget _buildFilterPopup(String columnName) {
    if (!(_filterVisibility[columnName] ?? false)) {
      return const SizedBox.shrink();
    }

    final fieldName = _getFieldName(columnName);
    final buttonKey = _filterButtonKeys[columnName]!;

    final uniqueValues = <String>{};

    if (columnName == 'Тэги') {
      final availableTags = TagManager().getTagNames();
      if (availableTags.isNotEmpty) {
        uniqueValues.addAll(availableTags);
      } else {
        return _buildNoTagsFilterPopup(columnName, buttonKey);
      }
    } else if (columnName == 'Игнор') {
      // Специальная обработка для столбца "Игнор"
      uniqueValues.addAll(['true', 'false']);
    } else {
      for (final product in _allProducts) {
        final value = product[fieldName]?.toString() ?? '';
        if (value.isNotEmpty) {
          uniqueValues.add(value);
        }
      }
    }

    var valuesList = _getSortedValuesForColumn(fieldName, uniqueValues);

    final searchController = _filterSearchControllers[columnName];
    if (searchController != null && searchController.text.isNotEmpty) {
      final searchText = searchController.text.toLowerCase();
      valuesList = valuesList.where((value) => value.toLowerCase().contains(searchText)).toList();
    }

    final allSelected = _filters[columnName] != null &&
        _filters[columnName]!.where((value) => value.isNotEmpty).length == uniqueValues.length;

    final emptySelected = _filters[columnName]?.contains('') ?? false;

    final RenderBox? buttonRenderBox = buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final buttonSize = buttonRenderBox?.size ?? Size.zero;
    final buttonPosition = buttonRenderBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    double leftPosition;

    if (columnName == 'Артикул WB' || columnName == 'Мой артикул' || columnName == 'Баркод') {
      leftPosition = buttonPosition.dx + buttonSize.width - 50;
    } else {
      leftPosition = buttonPosition.dx - 350;
    }

    return Positioned(
      left: leftPosition,
      top: buttonPosition.dy + buttonSize.height - 100,
      child: GestureDetector(
        onTap: () {},
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 300,
            height: 400,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: BoxBorder.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Фильтр: $columnName',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() {
                          _filterVisibility[columnName] = false;
                          _currentOpenFilter = null;
                        });
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                // Скрываем поле поиска для столбца "Игнор", так как там всего 2 значения
                if (columnName != 'Игнор') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Поиск...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {});
                    },
                  ),
                ],

                const SizedBox(height: 8),
                if (columnName == 'Тэги')
                  Text(
                    '',
                    style: const TextStyle(fontSize: 10, color: Colors.blue),
                  ),
                Text(
                  'Найдено значений: ${valuesList.length}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),

                CheckboxListTile(
                  title: const Text(
                    'Выбрать всё',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  value: allSelected,
                  onChanged: (checked) => _selectAllFilter(columnName, checked ?? false),
                  controlAffinity: ListTileControlAffinity.leading, // исправлено здесь
                  dense: true,
                ),
                // Скрываем чекбокс "Пустые" для столбца "Игнор"
                if (columnName != 'Игнор')
                  CheckboxListTile(
                    title: const Text(
                      'Пустые',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    value: emptySelected,
                    onChanged: (checked) => _updateEmptyFilter(columnName, checked ?? false),
                    controlAffinity: ListTileControlAffinity.leading, // исправлено здесь
                    dense: true,
                  ),
                const Divider(height: 1),

                Expanded(
                  child: valuesList.isEmpty
                      ? const Center(
                    child: Text(
                      'Нет данных для фильтрации',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  )
                      : ListView.builder(
                    itemCount: valuesList.length,
                    itemBuilder: (context, index) {
                      final value = valuesList[index];

                      // Для столбца "Игнор" преобразуем отображаемое значение
                      String displayValue = value;
                      if (columnName == 'Игнор') {
                        displayValue = value == 'true' ? 'Включен' : 'Выключен';
                      }

                      final isChecked = _filters[columnName]?.contains(value) ?? false;
                      return CheckboxListTile(
                        title: Text(
                          displayValue.length > 50 ? '${displayValue.substring(0, 50)}...' : displayValue,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        value: isChecked,
                        onChanged: (checked) => _updateFilter(columnName, value, checked ?? false),
                        controlAffinity: ListTileControlAffinity.leading, // исправлено здесь
                        dense: true,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _filters.remove(columnName);
                            searchController?.clear();
                          });
                          _applyFiltersAndSorting();
                        },
                        child: const Text('Сбросить', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child:
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _filterVisibility[columnName] = false;
                            _currentOpenFilter = null;
                          });
                        },
                        child: const Text('Применить', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _copyToClipboard(String text, String fieldName) {
    if (text.isEmpty) return;

    Clipboard.setData(ClipboardData(text: text));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$fieldName скопирован в буфер обмена'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _shouldHighlightField(int id, String fieldName) {
    final localState = _localState[id];
    if (localState == null) return false;

    final threshold = localState['fbo_threshold']?.toString().trim() ?? '';
    final minimum = localState['fbs_minimum']?.toString().trim() ?? '';

    if (fieldName == 'fbo_threshold') {
      return threshold.isEmpty && minimum.isNotEmpty;
    } else if (fieldName == 'fbs_minimum') {
      return minimum.isEmpty && threshold.isNotEmpty;
    }
    return false;
  }

  Future<void> _sendConfigToServer(int id) async {
    final localState = _localState[id];
    if (localState == null) return;

    setState(() {
      localState['updating'] = true;
    });

    try {
      final product = _allProducts.firstWhere((p) => p['id'] == id);
      final nmId = product['nm_id'];

      // Сначала проверяем, существует ли уже конфигурация для этого товара
      final checkResponse = await http.get(
        Uri.parse('https://hide_domain.com/product-auto-config/$nmId'),
        headers: {'Content-Type': 'application/json'},
      );

      Map<String, dynamic> requestBody = {
        'fbo_threshold': localState['fbo_threshold']?.toString().trim().isNotEmpty == true
            ? int.tryParse(localState['fbo_threshold'].toString().trim())
            : null,
        'fbs_minimum': localState['fbs_minimum']?.toString().trim().isNotEmpty == true
            ? int.tryParse(localState['fbs_minimum'].toString().trim())
            : null,
        'ignore_auto_replenishment': localState['auto_replenishment'],
      };

      http.Response response;

      if (checkResponse.statusCode == 200) {
        // Конфигурация существует - обновляем через PUT
        response = await http.put(
          Uri.parse('https://hide_domain.com/product-auto-config/$nmId'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(requestBody),
        );
      } else if (checkResponse.statusCode == 404) {
        // Конфигурация не существует - создаем через POST
        response = await http.post(
          Uri.parse('https://hide_domain.com/product-auto-config'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'nm_id': nmId,
            ...requestBody,
          }),
        );
      } else {
        throw Exception('Ошибка проверки конфигурации: ${checkResponse.statusCode}');
      }

      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.statusCode}');
      }

      // ОБНОВЛЯЕМ ЛОКАЛЬНУЮ КОПИЮ КОНФИГУРАЦИЙ ПОСЛЕ УСПЕШНОГО СОХРАНЕНИЯ
      await _loadProductAutoConfigs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Конфигурация для товара $nmId сохранена'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          localState['updating'] = false;
          _countdownTimers.remove(id);
        });
      }
    }
  }

  void _handleConfigChange(int id, String field, dynamic value) {
    _configTimers[id]?.cancel();
    _countdownTimers.remove(id);

    _updateLocalState(id, field, value);

    final localState = _localState[id];
    if (localState == null) return;

    // ЗАПУСКАЕМ ТАЙМЕР ПРИ ЛЮБОМ ИЗМЕНЕНИИ КОНФИГУРАЦИИ
    setState(() {
      _countdownTimers[id] = 12; // 12 шагов по 250 мс = 3000 мс
    });

    final countdownTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        final current = _countdownTimers[id] ?? 0;
        if (current > 1) {
          _countdownTimers[id] = current - 1;
        } else {
          _countdownTimers.remove(id);
          timer.cancel();
        }
      });
    });

    _configTimers[id] = Timer(const Duration(milliseconds: 3000), () {
      countdownTimer.cancel();
      if (mounted) {
        _countdownTimers.remove(id);
        _sendConfigToServer(id);
      }
    });
  }

  void _handleAutoReplenishmentChange(int id, bool value) {
    _configTimers[id]?.cancel();
    _countdownTimers.remove(id);

    _updateLocalState(id, 'auto_replenishment', value);
    _sendConfigToServer(id);
  }

  Future<void> _handleStockUpdate(int id) async {
    final localState = _localState[id];
    if (localState == null) return;

    final changeQuantity = localState['change_quantity']?.toString().trim() ?? '';
    if (changeQuantity.isEmpty) {
      _showErrorSnackbar('Введите количество для изменения');
      return;
    }

    final quantity = int.tryParse(changeQuantity);
    if (quantity == null) {
      _showErrorSnackbar('Введите корректное число');
      return;
    }

    // Находим продукт по id
    final product = _allProducts.firstWhere((p) => p['id'] == id);
    final barcode = product['barcode']?.toString() ?? '';

    if (barcode.isEmpty) {
      _showErrorSnackbar('У товара отсутствует баркод');
      return;
    }

    setState(() {
      localState['updating'] = true;
    });

    try {
      final response = await http.post(
        Uri.parse('https://hide_domain.com/update-single-stock'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'barcode': barcode,
          'quantity': quantity,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Остаток FBS обновлен до $quantity'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }

        // Очищаем поле после успешной отправки
        _updateLocalState(id, 'change_quantity', '');
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка обновления остатка: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          localState['updating'] = false;
        });
      }
    }
  }

  Widget _buildDataTable() {
    if (_hasError && _allProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Ошибка загрузки данных',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Проверьте подключение к серверу'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadAllData,
              child: const Text('Повторить попытку'),
            ),
          ],
        ),
      );
    }

    if (_isLoading && _allProducts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_displayProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Данные не найдены',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            if (_filters.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Попробуйте изменить параметры фильтрации',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ],
        ),
      );
    }

    return _buildScrollableTable();
  }

  Widget _buildScrollableTable() {
    return Stack(
      children: [
        GestureDetector(
          onTap: _handleTableTap,
          child: Column(
            children: [
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: BoxBorder.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Активные фильтры:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 16),
                    if (_filters.isNotEmpty) ...[
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ..._filters.entries.map((entry) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 16),
                                  child: Chip(
                                    label: Text('${entry.key}: ${entry.value.length}'),
                                    deleteIcon: const Icon(Icons.close, size: 16),
                                    onDeleted: () {
                                      setState(() {
                                        _filters.remove(entry.key);
                                      });
                                      _applyFiltersAndSorting();
                                    },
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      const Text(
                        'нет активных фильтров',
                        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      icon: Image.asset(
                        'assets/icons/excel.png',
                        width: 75,
                        height: 75,
                        color: Colors.green,
                      ),
                      onPressed: _isLoading ? null : _exportToExcel,
                      tooltip: 'Скачать Excel',
                    ),
                    const SizedBox(width: 8),
                    if (_filters.isNotEmpty) ...[
                      TextButton(
                        onPressed: _clearFilters,
                        child: const Text('Очистить все'),
                      ),
                    ],
                  ],
                ),
              ),

              Expanded(
                child: Scrollbar(
                  controller: _verticalScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _verticalScrollController,
                    child: Scrollbar(
                      controller: _horizontalScrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _horizontalScrollController,
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          key: _tableKey,
                          headingRowHeight: 100,
                          horizontalMargin: 0,
                          columnSpacing: 0,
                          dataRowMinHeight: 40,
                          dataRowMaxHeight: 40,
                          columns: [
                            _buildDataColumn('nm_id', 'Артикул WB'),
                            _buildDataColumn('vendor_code', 'Мой артикул'),
                            _buildDataColumn('barcode', 'Баркод'),
                            _buildDataColumn('title', 'Наименование'),
                            _buildDataColumn('tags', 'Тэги'),
                            _buildDataColumn('total_quantity', 'FBO'),
                            _buildDataColumn('fbs_quantity', 'FBS'),
                            _buildDataColumn('fbo_threshold', 'Порог'),
                            _buildDataColumn('fbs_minimum', 'Уровень FBS'),
                            _buildDataColumn('auto_replenishment', 'Игнор'),
                            _buildDataColumn('updating', ''),
                            _buildDataColumn('change_quantity', 'Изменить'),
                          ],
                          rows: _displayProducts.map((product) {
                            return _buildDataRow(product);
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        ..._columnWidths.keys.map((columnKey) =>
            _buildFilterPopup(_getColumnLabel(columnKey))
        ),
      ],
    );
  }

  String _getColumnLabel(String key) {
    final labelMap = {
      'nm_id': 'Артикул WB',
      'vendor_code': 'Мой артикул',
      'barcode': 'Баркод',
      'title': 'Наименование',
      'tags': 'Тэги',
      'total_quantity': 'FBO',
      'fbs_quantity': 'FBS',
      'fbo_threshold': 'Порог',
      'fbs_minimum': 'Уровень FBS',
      'auto_replenishment': 'Игнор',
      'change_quantity': 'Изменить',
    };
    return labelMap[key] ?? key;
  }

  DataColumn _buildDataColumn(String key, String label) {
    return DataColumn(
      label: Container(
        width: _columnWidths[key]!,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            _buildFilterButton(label),
          ],
        ),
      ),
      onSort: (columnIndex, ascending) => _sortColumnBy(label),
    );
  }

  DataRow _buildDataRow(dynamic product) {
    final id = product['id'];
    final localState = _localState[id] ?? {
      'fbo_threshold': '',
      'fbs_minimum': '',
      'auto_replenishment': false,
      'updating': false,
      'change_quantity': '',
    };

    return DataRow(
      cells: [
        _buildDataCell(product['nm_id']?.toString() ?? '', _columnWidths['nm_id']!),
        _buildCopyableDataCell(
            product['vendor_code']?.toString() ?? '',
            _columnWidths['vendor_code']!,
            'Мой артикул'
        ),
        _buildCopyableDataCell(
            product['barcode']?.toString() ?? '',
            _columnWidths['barcode']!,
            'Баркод'
        ),
        _buildCopyableDataCell(
            product['title']?.toString() ?? '',
            _columnWidths['title']!,
            'Наименование'
        ),
        _buildCopyableTagsCell(product['tags'], _columnWidths['tags']!),
        _buildDataCell(product['total_quantity']?.toString() ?? '0', _columnWidths['total_quantity']!),
        _buildDataCell(product['fbs_quantity']?.toString() ?? '0', _columnWidths['fbs_quantity']!),
        _buildTextFieldCell(
            localState['fbo_threshold']!,
                (value) => _handleConfigChange(id, 'fbo_threshold', value),
            _columnWidths['fbo_threshold']!,
            hintText: '',
            id: id,
            fieldName: 'fbo_threshold'
        ),
        _buildTextFieldCell(
            localState['fbs_minimum']!,
                (value) => _handleConfigChange(id, 'fbs_minimum', value),
            _columnWidths['fbs_minimum']!,
            hintText: '',
            id: id,
            fieldName: 'fbs_minimum'
        ),
        _buildSwitchCell(
            localState['auto_replenishment']!,
                (value) => _handleAutoReplenishmentChange(id, value),
            _columnWidths['auto_replenishment']!,
            id
        ),
        _buildUpdatingCell(localState['updating']!, _columnWidths['updating']!, id),
        _buildTextFieldCell(
            localState['change_quantity']!,
                (value) => _updateLocalState(id, 'change_quantity', value),
            _columnWidths['change_quantity']!,
            hintText: '',
            id: id,
            fieldName: 'change_quantity'
        ),
      ],
    );
  }

  void _updateLocalState(int id, String key, dynamic value) {
    if (!mounted) return;

    setState(() {
      if (!_localState.containsKey(id)) {
        _localState[id] = {
          'fbo_threshold': '',
          'fbs_minimum': '',
          'auto_replenishment': false,
          'updating': false,
          'change_quantity': '',
        };
      }
      _localState[id]![key] = value;
    });
  }

  DataCell _buildDataCell(String value, double width) {
    return DataCell(
      Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          value,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  DataCell _buildCopyableDataCell(String value, double width, String fieldName) {
    return DataCell(
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _copyToClipboard(value, fieldName),
          child: Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  DataCell _buildTextFieldCell(String value, Function(String) onChanged, double width,
      {String hintText = '', required int id, required String fieldName}) {
    final shouldHighlight = _shouldHighlightField(id, fieldName);
    final isChangeQuantityField = fieldName == 'change_quantity';

    return DataCell(
      Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextFormField(
          initialValue: value,
          decoration: InputDecoration(
            hintText: hintText,
            border: OutlineInputBorder(
              borderSide: BorderSide(
                color: shouldHighlight ? Colors.yellow : Colors.grey,
                width: shouldHighlight ? 2.0 : 1.0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: shouldHighlight ? Colors.orange : Theme.of(context).primaryColor,
                width: shouldHighlight ? 2.0 : 1.0,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            isDense: true,
          ),
          onChanged: onChanged,
          onFieldSubmitted: isChangeQuantityField ? (value) {
            if (value.trim().isNotEmpty) {
              _handleStockUpdate(id);
            }
          } : null,
        ),
      ),
    );
  }

  DataCell _buildSwitchCell(bool value, Function(bool) onChanged, double width, int id) {
    return DataCell(
      Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Switch(
          value: value,
          onChanged: (newValue) => onChanged(newValue),
        ),
      ),
    );
  }

  DataCell _buildUpdatingCell(bool updating, double width, int id) {
    final countdownValue = _countdownTimers[id];

    return DataCell(
      Container(
        width: width,
        // Убираем фиксированные отступы и задаем высоту равной высоте строки
        padding: const EdgeInsets.all(0),
        // Выравниваем по центру по вертикали
        alignment: Alignment.center,
        child: updating
            ? const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : countdownValue != null
            ? Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                value: (12 - countdownValue) / 12,
                strokeWidth: 2,
              ),
            ),
            Text(
              ((countdownValue + 2) ~/ 4).toString(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        )
            : const SizedBox(),
      ),
    );
  }

  DataCell _buildCopyableTagsCell(dynamic tagsData, double width) {
    List<dynamic> tagsList = [];

    try {
      if (tagsData is String && tagsData.isNotEmpty) {
        tagsList = json.decode(tagsData) as List<dynamic>;
      } else if (tagsData is List<dynamic>) {
        tagsList = tagsData;
      }
    } catch (e) {
      print('Error parsing tags: $e');
    }

    if (tagsList.isEmpty) {
      return _buildDataCell('', width);
    }

    String tagsString = tagsList.map((tag) {
      if (tag is Map<String, dynamic>) {
        return tag['name']?.toString() ?? '';
      }
      return '';
    }).where((name) => name.isNotEmpty).join(', ');

    return DataCell(
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _copyToClipboard(tagsString, 'Тэги'),
          child: Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
            ),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: tagsList.take(3).map<Widget>((tag) {
                if (tag is! Map<String, dynamic>) {
                  return Container();
                }

                String name = tag['name']?.toString() ?? '';
                String color = tag['color']?.toString() ?? 'D1CFD7';

                if (name.isEmpty) {
                  return Container();
                }

                Color backgroundColor;
                try {
                  String hexColor = color;
                  if (hexColor.startsWith('#')) {
                    hexColor = hexColor.substring(1);
                  }
                  if (hexColor.length == 6) {
                    backgroundColor = Color(0xFF000000 + int.parse(hexColor, radix: 16));
                  } else {
                    backgroundColor = Colors.grey;
                  }
                } catch (e) {
                  backgroundColor = Colors.grey;
                }

                bool isDark = backgroundColor.computeLuminance() < 0.5;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#$name',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaginationControls() {
    final totalPages = (_totalCount / _itemsPerPage).ceil();
    final startItem = _currentPage * _itemsPerPage + 1;
    final endItem = (_currentPage + 1) * _itemsPerPage;
    final actualEndItem = endItem > _totalCount ? _totalCount : endItem;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Показано $startItem-$actualEndItem из $_totalCount',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              if (_hasError)
                Text(
                  'Ошибка загрузки данных',
                  style: TextStyle(
                    color: Colors.red[600],
                    fontSize: 12,
                  ),
                ),
              if (_filters.isNotEmpty)
                Text(
                  'Применены фильтры: ${_filters.length} (отфильтровано ${_filteredProducts.length} из ${_allProducts.length})',
                  style: TextStyle(
                    color: Colors.blue[600],
                    fontSize: 12,
                  ),
                ),
            ],
          ),

          Row(
            children: [
              if (_filters.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.filter_alt_off),
                  onPressed: _clearFilters,
                  tooltip: 'Очистить фильтры',
                ),

              IconButton(
                icon: const Icon(Icons.first_page),
                onPressed: _currentPage > 0 && !_isLoading
                    ? () {
                  setState(() {
                    _currentPage = 0;
                  });
                  _updateDisplayProducts();
                }
                    : null,
                tooltip: 'Первая страница',
              ),

              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 0 && !_isLoading
                    ? () {
                  setState(() {
                    _currentPage--;
                  });
                  _updateDisplayProducts();
                }
                    : null,
                tooltip: 'Предыдущая страница',
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_currentPage + 1} / ${totalPages == 0 ? 1 : totalPages}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),

              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < totalPages - 1 && !_isLoading
                    ? () {
                  setState(() {
                    _currentPage++;
                  });
                  _updateDisplayProducts();
                }
                    : null,
                tooltip: 'Следующая страница',
              ),

              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: _currentPage < totalPages - 1 && !_isLoading
                    ? () {
                  setState(() {
                    _currentPage = totalPages - 1;
                  });
                  _updateDisplayProducts();
                }
                    : null,
                tooltip: 'Последняя страница',
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Остатки товаров',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Всего товаров: $_totalCount',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  IconButton(
                    onPressed: _isLoading ? null : _loadAllData,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Обновить данные',
                  ),
                ],
              ),
            ),

            Expanded(
              child: _buildDataTable(),
            ),

            _buildPaginationControls(),
          ],
        ),
      ),
    );
  }
}