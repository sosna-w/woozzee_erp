// database_screen.dart - ОБНОВЛЕННАЯ ВЕРСИЯ С ЛОГИРОВАНИЕМ
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/product_manager.dart';

class DatabaseScreen extends StatefulWidget {
  const DatabaseScreen({super.key});

  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _products = [];
  List<dynamic> _stocks = [];
  bool _isLoadingProducts = false;
  bool _isLoadingStocks = false;
  
  // Параметры пагинации для товаров
  int _productsCurrentPage = 0;
  int _productsPerPage = 100;
  int _productsTotalCount = 0;
  
  // Параметры пагинации для остатков
  int _stocksCurrentPage = 0;
  int _stocksPerPage = 100;
  int _stocksTotalCount = 0;
  
  // Кэш загруженных страниц
  final Map<int, List<dynamic>> _productsPageCache = {};
  final Map<int, List<dynamic>> _stocksPageCache = {};
  
  // Контроллеры для прокрутки
  final ScrollController _horizontalScrollController = ScrollController();
  final Map<int, ScrollController> _verticalScrollControllers = {};

  // Фиксированные ширины столбцов для товаров (все поля из модели Product)
  final Map<String, double> _productColumnWidths = {
    'nmID': 100.0,
    'imtID': 100.0,
    'nmUUID': 150.0,
    'subjectID': 100.0,
    'subjectName': 150.0,
    'vendorCode': 120.0,
    'brand': 120.0,
    'title': 200.0,
    'description': 250.0,
    'needKiz': 80.0,
    'photos': 150.0,
    'video': 150.0,
    'wholesale_enabled': 100.0,
    'wholesale_quantum': 100.0,
    'dimensions_length': 100.0,
    'dimensions_width': 100.0,
    'dimensions_height': 100.0,
    'dimensions_weightBrutto': 120.0,
    'dimensions_isValid': 100.0,
    'characteristics': 200.0,
    'sizes': 150.0,
    'tags': 150.0,
    'created_at': 150.0,
    'updated_at': 150.0,
  };

  // Фиксированные ширины столбцов для остатков (все поля из модели Stock)
  final Map<String, double> _stockColumnWidths = {
    'lastChangeDate': 150.0,
    'warehouseName': 150.0,
    'supplierArticle': 150.0,
    'nmId': 100.0,
    'barcode': 120.0,
    'quantity': 80.0,
    'inWayToClient': 100.0,
    'inWayFromClient': 100.0,
    'quantityFull': 100.0,
    'category': 100.0,
    'subject': 120.0,
    'brand': 120.0,
    'techSize': 100.0,
    'Price': 100.0,
    'Discount': 80.0,
    'isSupply': 80.0,
    'isRealization': 100.0,
    'SCCode': 100.0,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    print('🔄 Инициализация DatabaseScreen...');
    _loadProductsTotalCount();
    _loadStocksTotalCount();
    _loadProductsPage(0);
    _loadStocksPage(0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _horizontalScrollController.dispose();
    for (var controller in _verticalScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProductsTotalCount() async {
    try {
      print('📊 Загрузка общего количества товаров...');
      final response = await http.get(Uri.parse('https://hide_domain.com/products'));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _productsTotalCount = data.length;
        });
        print('✅ Общее количество товаров: $_productsTotalCount');
      }
    } catch (e) {
      if (!mounted) return;
      print('❌ Ошибка загрузки общего количества товаров: $e');
    }
  }

  Future<void> _loadStocksTotalCount() async {
    try {
      print('📊 Загрузка общего количества остатков...');
      final response = await http.get(Uri.parse('https://hide_domain.com/stocks'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _stocksTotalCount = data.length;
        });
        print('✅ Общее количество остатков: $_stocksTotalCount');
      }
    } catch (e) {
      print('❌ Ошибка загрузки общего количества остатков: $e');
    }
  }

  Future<void> _loadProductsPage(int page) async {
    print('🔄 Загрузка страницы товаров $page...');
    
    // Логирование состояния кэша
    _logCacheState();
    
    if (_productsPageCache.containsKey(page)) {
      print('📦 Страница товаров $page найдена в кэше, загружаем из кэша');
      if (!mounted) return;
      setState(() {
        _productsCurrentPage = page;
        _products = _productsPageCache[page]!;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoadingProducts = true;
    });

    try {
      print('🌐 Запрос всех товаров с сервера...');
      final response = await http.get(Uri.parse('https://hide_domain.com/products'));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final allProducts = json.decode(response.body);
        print('✅ Получено ${allProducts.length} товаров с сервера');
        
        // Логируем структуру первого товара для диагностики
        if (allProducts.isNotEmpty) {
          print('🔍 Структура первого товара (первые 3 уровня):');
          _logObjectStructure(allProducts.first, '  ', 0, 3);
        }
        
        final startIndex = page * _productsPerPage;
        final endIndex = startIndex + _productsPerPage;
        final pageProducts = allProducts.sublist(
            startIndex,
            endIndex < allProducts.length ? endIndex : allProducts.length
        );

        print('✂️ Создана страница $page: позиции $startIndex-$endIndex, ${pageProducts.length} товаров');

        if (!mounted) return;
        setState(() {
          _productsPageCache[page] = pageProducts;
          _productsCurrentPage = page;
          _products = pageProducts;
          _productsTotalCount = allProducts.length;
        });
        
        print('✅ Страница товаров $page загружена и кэширована');
        _logCacheState();
        
        // Диагностика фото
        _diagnosePhotos(pageProducts);
        
      } else {
        if (!mounted) return;
        print('❌ Ошибка HTTP при загрузке товаров: ${response.statusCode}');
        _showErrorSnackbar('Ошибка загрузки товаров: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      print('❌ Исключение при загрузке товаров: $e');
      _showErrorSnackbar('Ошибка подключения: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingProducts = false;
      });
    }
  }

  Future<void> _loadStocksPage(int page) async {
    print('🔄 Загрузка страницы остатков $page...');
    
    if (_stocksPageCache.containsKey(page)) {
      print('📦 Страница остатков $page найдена в кэше, загружаем из кэша');
      setState(() {
        _stocksCurrentPage = page;
        _stocks = _stocksPageCache[page]!;
      });
      return;
    }

    setState(() {
      _isLoadingStocks = true;
    });

    try {
      print('🌐 Запрос всех остатков с сервера...');
      final response = await http.get(Uri.parse('https://hide_domain.com/stocks'));
      
      if (response.statusCode == 200) {
        final allStocks = json.decode(response.body);
        print('✅ Получено ${allStocks.length} остатков с сервера');
        
        final startIndex = page * _stocksPerPage;
        final endIndex = startIndex + _stocksPerPage;
        final pageStocks = allStocks.sublist(
          startIndex,
          endIndex < allStocks.length ? endIndex : allStocks.length
        );
        
        print('✂️ Создана страница $page: позиции $startIndex-$endIndex, ${pageStocks.length} остатков');
        
        setState(() {
          _stocksPageCache[page] = pageStocks;
          _stocksCurrentPage = page;
          _stocks = pageStocks;
          _stocksTotalCount = allStocks.length;
        });
        
        print('✅ Страница остатков $page загружена и кэширована');
        
      } else {
        print('❌ Ошибка HTTP при загрузке остатков: ${response.statusCode}');
        _showErrorSnackbar('Ошибка загрузки остатков: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Исключение при загрузке остатков: $e');
      _showErrorSnackbar('Ошибка подключения: $e');
    } finally {
      setState(() {
        _isLoadingStocks = false;
      });
    }
  }

  // Метод для логирования состояния кэша
  void _logCacheState() {
    print('📊 Состояние кэша товаров:');
    print('   Всего страниц в кэше: ${_productsPageCache.length}');
    for (var entry in _productsPageCache.entries) {
      print('   Страница ${entry.key}: ${entry.value.length} товаров');
    }
    
    print('📊 Состояние кэша остатков:');
    print('   Всего страниц в кэше: ${_stocksPageCache.length}');
    for (var entry in _stocksPageCache.entries) {
      print('   Страница ${entry.key}: ${entry.value.length} остатков');
    }
  }

  // Метод для логирования структуры объекта
  void _logObjectStructure(dynamic obj, String indent, int currentDepth, int maxDepth) {
    if (currentDepth >= maxDepth) {
      print('$indent... (глубина $maxDepth достигнута)');
      return;
    }
    
    if (obj is Map) {
      for (var key in obj.keys) {
        final value = obj[key];
        final typeName = value?.runtimeType.toString() ?? 'null';
        
        if (value is Map && currentDepth < maxDepth - 1) {
          print('$indent$key: Map ($typeName)');
          _logObjectStructure(value, '$indent  ', currentDepth + 1, maxDepth);
        } else if (value is List) {
          print('$indent$key: List[${value.length}] ($typeName)');
          if (value.isNotEmpty && currentDepth < maxDepth - 1) {
            _logObjectStructure(value.first, '$indent  ', currentDepth + 1, maxDepth);
          }
        } else {
          final stringValue = value?.toString() ?? 'null';
          final displayValue = stringValue.length > 100 
              ? '${stringValue.substring(0, 100)}...' 
              : stringValue;
          print('$indent$key: $displayValue ($typeName)');
        }
      }
    } else if (obj is List) {
      print('${indent}List[${obj.length}]');
      if (obj.isNotEmpty && currentDepth < maxDepth - 1) {
        _logObjectStructure(obj.first, '$indent  ', currentDepth + 1, maxDepth);
      }
    }
  }

  // Диагностика фото в товарах
  void _diagnosePhotos(List<dynamic> products) {
    print('🔍 Диагностика фотографий в товарах:');
    
    int totalProducts = products.length;
    int productsWithPhotos = 0;
    int productsWithPhotosArray = 0;
    int productsWithPhotosString = 0;
    
    for (var product in products) {
      if (product.containsKey('photos')) {
        final photos = product['photos'];
        productsWithPhotos++;
        
        if (photos is List) {
          productsWithPhotosArray++;
          if (photos.isNotEmpty) {
            final firstPhoto = photos.first;
            print('   Товар ${product['nmID']}: photos is List[${photos.length}]');
            
            if (firstPhoto is Map) {
              print('      Первый элемент: Map с ключами: ${firstPhoto.keys.join(', ')}');
              // Проверяем, есть ли URL в разных форматах
              final urlKeys = ['big', 'c246x328', 'c516x688', 'square', 'tm'];
              for (var key in urlKeys) {
                if (firstPhoto.containsKey(key)) {
                  final url = firstPhoto[key];
                  print('      $key: ${url is String ? (url.length > 50 ? '${url.substring(0, 50)}...' : url) : 'тип: ${url.runtimeType}'}');
                }
              }
            } else if (firstPhoto is String) {
              print('      Первый элемент: String "${firstPhoto.length > 50 ? '${firstPhoto.substring(0, 50)}...' : firstPhoto}"');
            } else {
              print('      Первый элемент: тип ${firstPhoto.runtimeType}');
            }
          } else {
            print('   Товар ${product['nmID']}: photos is List, но пустой');
          }
        } else if (photos is String) {
          productsWithPhotosString++;
          print('   Товар ${product['nmID']}: photos is String (длина: ${photos.length})');
          if (photos.length > 100) {
            print('      Начало строки: ${photos.substring(0, 100)}...');
          } else {
            print('      Строка: $photos');
          }
        } else {
          print('   Товар ${product['nmID']}: photos тип ${photos.runtimeType}');
        }
      }
    }
    
    print('📊 Статистика фото:');
    print('   Всего товаров на странице: $totalProducts');
    print('   Товаров с полем photos: $productsWithPhotos');
    print('   Товаров с photos как List: $productsWithPhotosArray');
    print('   Товаров с photos как String: $productsWithPhotosString');
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Widget _buildProductsTable() {
    return _buildDataTable(
      data: _products,
      columnWidths: _productColumnWidths,
      isLoading: _isLoadingProducts,
      tabIndex: 0,
      buildColumns: () => [
        _buildDataColumn('nmID', _productColumnWidths['nmID']!, 'Артикул WB'),
        _buildDataColumn('imtID', _productColumnWidths['imtID']!, 'imtID'),
        _buildDataColumn('nmUUID', _productColumnWidths['nmUUID']!, 'nmUUID'),
        _buildDataColumn('subjectID', _productColumnWidths['subjectID']!, 'ID категории'),
        _buildDataColumn('subjectName', _productColumnWidths['subjectName']!, 'Название категории'),
        _buildDataColumn('vendorCode', _productColumnWidths['vendorCode']!, 'Артикул продавца'),
        _buildDataColumn('brand', _productColumnWidths['brand']!, 'Бренд'),
        _buildDataColumn('title', _productColumnWidths['title']!, 'Название'),
        _buildDataColumn('description', _productColumnWidths['description']!, 'Описание'),
        _buildDataColumn('needKiz', _productColumnWidths['needKiz']!, 'Нужен КиЗ'),
        _buildDataColumn('photos', _productColumnWidths['photos']!, 'Фото'),
        _buildDataColumn('video', _productColumnWidths['video']!, 'Видео'),
        _buildDataColumn('wholesale_enabled', _productColumnWidths['wholesale_enabled']!, 'Опт включен'),
        _buildDataColumn('wholesale_quantum', _productColumnWidths['wholesale_quantum']!, 'Квант опта'),
        _buildDataColumn('dimensions_length', _productColumnWidths['dimensions_length']!, 'Длина'),
        _buildDataColumn('dimensions_width', _productColumnWidths['dimensions_width']!, 'Ширина'),
        _buildDataColumn('dimensions_height', _productColumnWidths['dimensions_height']!, 'Высота'),
        _buildDataColumn('dimensions_weightBrutto', _productColumnWidths['dimensions_weightBrutto']!, 'Вес брутто'),
        _buildDataColumn('dimensions_isValid', _productColumnWidths['dimensions_isValid']!, 'Размеры валидны'),
        _buildDataColumn('characteristics', _productColumnWidths['characteristics']!, 'Характеристики'),
        _buildDataColumn('sizes', _productColumnWidths['sizes']!, 'Размеры'),
        _buildDataColumn('tags', _productColumnWidths['tags']!, 'Теги'),
        _buildDataColumn('created_at', _productColumnWidths['created_at']!, 'Создан'),
        _buildDataColumn('updated_at', _productColumnWidths['updated_at']!, 'Обновлен'),
      ],
      buildCells: (item) => [
        _buildDataCell(item['nmID']?.toString() ?? '', _productColumnWidths['nmID']!),
        _buildDataCell(item['imtID']?.toString() ?? '', _productColumnWidths['imtID']!),
        _buildDataCell(item['nmUUID']?.toString() ?? '', _productColumnWidths['nmUUID']!),
        _buildDataCell(item['subjectID']?.toString() ?? '', _productColumnWidths['subjectID']!),
        _buildDataCell(item['subjectName']?.toString() ?? '', _productColumnWidths['subjectName']!),
        _buildDataCell(item['vendorCode']?.toString() ?? '', _productColumnWidths['vendorCode']!),
        _buildDataCell(item['brand']?.toString() ?? '', _productColumnWidths['brand']!),
        _buildDataCell(item['title']?.toString() ?? '', _productColumnWidths['title']!),
        _buildDataCell(item['description']?.toString() ?? '', _productColumnWidths['description']!),
        _buildDataCell(_formatBool(item['needKiz']), _productColumnWidths['needKiz']!),
        _buildPhotosCell(item['photos'], _productColumnWidths['photos']!),
        _buildDataCell(item['video']?.toString() ?? '', _productColumnWidths['video']!),
        _buildDataCell(_formatBool(item['wholesale_enabled']), _productColumnWidths['wholesale_enabled']!),
        _buildDataCell(item['wholesale_quantum']?.toString() ?? '', _productColumnWidths['wholesale_quantum']!),
        _buildDataCell(item['dimensions_length']?.toString() ?? '', _productColumnWidths['dimensions_length']!),
        _buildDataCell(item['dimensions_width']?.toString() ?? '', _productColumnWidths['dimensions_width']!),
        _buildDataCell(item['dimensions_height']?.toString() ?? '', _productColumnWidths['dimensions_height']!),
        _buildDataCell(item['dimensions_weightBrutto']?.toString() ?? '', _productColumnWidths['dimensions_weightBrutto']!),
        _buildDataCell(_formatBool(item['dimensions_isValid']), _productColumnWidths['dimensions_isValid']!),
        _buildDataCell(_formatList(item['characteristics']), _productColumnWidths['characteristics']!),
        _buildDataCell(_formatList(item['sizes']), _productColumnWidths['sizes']!),
        _buildTagsCell(item['tags'], _productColumnWidths['tags']!),
        _buildDataCell(_formatDateTime(item['created_at']), _productColumnWidths['created_at']!),
        _buildDataCell(_formatDateTime(item['updated_at']), _productColumnWidths['updated_at']!),
      ],
    );
  }

  Widget _buildStocksTable() {
    return _buildDataTable(
      data: _stocks,
      columnWidths: _stockColumnWidths,
      isLoading: _isLoadingStocks,
      tabIndex: 1,
      buildColumns: () => [
        _buildDataColumn('lastChangeDate', _stockColumnWidths['lastChangeDate']!, 'Дата изменения'),
        _buildDataColumn('warehouseName', _stockColumnWidths['warehouseName']!, 'Склад'),
        _buildDataColumn('supplierArticle', _stockColumnWidths['supplierArticle']!, 'Артикул поставщика'),
        _buildDataColumn('nmId', _stockColumnWidths['nmId']!, 'Артикул WB'),
        _buildDataColumn('barcode', _stockColumnWidths['barcode']!, 'Штрихкод'),
        _buildDataColumn('quantity', _stockColumnWidths['quantity']!, 'Количество'),
        _buildDataColumn('inWayToClient', _stockColumnWidths['inWayToClient']!, 'В пути к клиенту'),
        _buildDataColumn('inWayFromClient', _stockColumnWidths['inWayFromClient']!, 'В пути от клиента'),
        _buildDataColumn('quantityFull', _stockColumnWidths['quantityFull']!, 'Полное количество'),
        _buildDataColumn('category', _stockColumnWidths['category']!, 'Категория'),
        _buildDataColumn('subject', _stockColumnWidths['subject']!, 'Предмет'),
        _buildDataColumn('brand', _stockColumnWidths['brand']!, 'Бренд'),
        _buildDataColumn('techSize', _stockColumnWidths['techSize']!, 'Тех. размер'),
        _buildDataColumn('Price', _stockColumnWidths['Price']!, 'Цена'),
        _buildDataColumn('Discount', _stockColumnWidths['Discount']!, 'Скидка'),
        _buildDataColumn('isSupply', _stockColumnWidths['isSupply']!, 'Поставка'),
        _buildDataColumn('isRealization', _stockColumnWidths['isRealization']!, 'Реализация'),
        _buildDataColumn('SCCode', _stockColumnWidths['SCCode']!, 'Код поставки'),
      ],
      buildCells: (item) => [
        _buildDataCell(_formatDateTime(item['lastChangeDate']), _stockColumnWidths['lastChangeDate']!),
        _buildDataCell(item['warehouseName']?.toString() ?? '', _stockColumnWidths['warehouseName']!),
        _buildDataCell(item['supplierArticle']?.toString() ?? '', _stockColumnWidths['supplierArticle']!),
        _buildDataCell(item['nmId']?.toString() ?? '', _stockColumnWidths['nmId']!),
        _buildDataCell(item['barcode']?.toString() ?? '', _stockColumnWidths['barcode']!),
        _buildDataCell(item['quantity']?.toString() ?? '', _stockColumnWidths['quantity']!),
        _buildDataCell(item['inWayToClient']?.toString() ?? '', _stockColumnWidths['inWayToClient']!),
        _buildDataCell(item['inWayFromClient']?.toString() ?? '', _stockColumnWidths['inWayFromClient']!),
        _buildDataCell(item['quantityFull']?.toString() ?? '', _stockColumnWidths['quantityFull']!),
        _buildDataCell(item['category']?.toString() ?? '', _stockColumnWidths['category']!),
        _buildDataCell(item['subject']?.toString() ?? '', _stockColumnWidths['subject']!),
        _buildDataCell(item['brand']?.toString() ?? '', _stockColumnWidths['brand']!),
        _buildDataCell(item['techSize']?.toString() ?? '', _stockColumnWidths['techSize']!),
        _buildDataCell(item['Price']?.toString() ?? '', _stockColumnWidths['Price']!),
        _buildDataCell(item['Discount']?.toString() ?? '', _stockColumnWidths['Discount']!),
        _buildDataCell(_formatBool(item['isSupply']), _stockColumnWidths['isSupply']!),
        _buildDataCell(_formatBool(item['isRealization']), _stockColumnWidths['isRealization']!),
        _buildDataCell(item['SCCode']?.toString() ?? '', _stockColumnWidths['SCCode']!),
      ],
    );
  }

  Widget _buildDataTable({
    required List<dynamic> data,
    required Map<String, double> columnWidths,
    required bool isLoading,
    required int tabIndex,
    required List<DataColumn> Function() buildColumns,
    required List<DataCell> Function(dynamic item) buildCells,
  }) {
    if (!_verticalScrollControllers.containsKey(tabIndex)) {
      _verticalScrollControllers[tabIndex] = ScrollController();
    }

    return Expanded(
      child: Container(
        child: isLoading && data.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : data.isEmpty
                ? const Center(
                    child: Text(
                      'Данные не найдены',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : Scrollbar(
                    controller: _verticalScrollControllers[tabIndex],
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _verticalScrollControllers[tabIndex],
                      scrollDirection: Axis.vertical,
                      child: Scrollbar(
                        controller: _horizontalScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _horizontalScrollController,
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowHeight: 56,
                            horizontalMargin: 0,
                            columnSpacing: 0,
                            dataRowMinHeight: 40,
                            dataRowMaxHeight: 40,
                            columns: buildColumns(),
                            rows: data.map((item) {
                              return DataRow(
                                cells: buildCells(item),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }

  DataColumn _buildDataColumn(String label, double width, String tooltip) {
    return DataColumn(
      label: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Tooltip(
          message: tooltip,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
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

  // Новый метод для отображения фото
  DataCell _buildPhotosCell(dynamic photosData, double width) {
    if (photosData == null) {
      return _buildDataCell('нет фото', width);
    }
    
    if (photosData is String) {
      // Если это JSON строка
      if (photosData.isEmpty || photosData == '[]') {
        return _buildDataCell('нет фото', width);
      }
      
      try {
        final parsed = json.decode(photosData);
        if (parsed is List) {
          return _buildDataCell('${parsed.length} фото', width);
        }
        return _buildDataCell('1 фото', width);
      } catch (e) {
        return _buildDataCell('ошибка парсинга', width);
      }
    }
    
    if (photosData is List) {
      if (photosData.isEmpty) {
        return _buildDataCell('нет фото', width);
      }
      
      // Попробуем извлечь URL из первого фото
      String? firstPhotoUrl;
      final firstPhoto = photosData.first;
      
      if (firstPhoto is Map) {
        // Пробуем разные ключи, где может быть URL
        final possibleKeys = ['big', 'c246x328', 'c516x688', 'square', 'tm', 'url'];
        for (var key in possibleKeys) {
          if (firstPhoto.containsKey(key) && firstPhoto[key] is String) {
            firstPhotoUrl = firstPhoto[key] as String;
            break;
          }
        }
      } else if (firstPhoto is String) {
        firstPhotoUrl = firstPhoto;
      }
      
      if (firstPhotoUrl != null) {
        return DataCell(
          Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${photosData.length} фото',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  firstPhotoUrl.length > 30 
                    ? '${firstPhotoUrl.substring(0, 30)}...'
                    : firstPhotoUrl,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      }
      
      return _buildDataCell('${photosData.length} фото', width);
    }
    
    return _buildDataCell('неизвестный формат', width);
  }

  String _formatDateTime(String? dateTimeString) {
    if (dateTimeString == null) return '';
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTimeString;
    }
  }

  String _formatBool(dynamic value) {
    if (value == null) return '';
    if (value is bool) {
      return value ? 'Да' : 'Нет';
    }
    if (value is String) {
      return value.toLowerCase() == 'true' ? 'Да' : 'Нет';
    }
    return value.toString();
  }

  DataCell _buildTagsCell(dynamic tagsData, double width) {
    List<dynamic> tagsList = [];

    // Обрабатываем разные форматы данных
    if (tagsData is String) {
      // Если это JSON-строка
      if (tagsData.isEmpty) {
        return _buildDataCell('', width);
      }
      try {
        tagsList = json.decode(tagsData) as List<dynamic>;
      } catch (e) {
        return _buildDataCell('Ошибка парсинга', width);
      }
    } else if (tagsData is List<dynamic>) {
      // Если это уже готовый список
      tagsList = tagsData;
    } else {
      return _buildDataCell('', width);
    }

    if (tagsList.isEmpty) {
      return _buildDataCell('', width);
    }

    return DataCell(
      Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: tagsList.map<Widget>((tag) {
            // Проверяем, что tag - это Map
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
              // Убедимся, что цвет в правильном формате (6 символов без #)
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

            // Вычисляем яркость цвета для определения цвета текста
            bool isDark = backgroundColor.computeLuminance() < 0.5;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '#$name',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _formatList(dynamic value) {
    if (value == null) return '';
    if (value is List) {
      return value.length.toString();
    }
    if (value is String) {
      try {
        // Пропускаем теги, так как они обрабатываются отдельно
        if (value.contains('"name"') && value.contains('"color"')) {
          return ''; // возвращаем пустую строку для тегов
        }
        final list = json.decode(value) as List;
        return list.length.toString();
      } catch (e) {
        return value;
      }
    }
    return value.toString();
  }

  Widget _buildProductsPaginationControls() {
    final totalPages = (_productsTotalCount / _productsPerPage).ceil();
    final startItem = _productsCurrentPage * _productsPerPage + 1;
    final endItem = (_productsCurrentPage + 1) * _productsPerPage;
    final actualEndItem = endItem > _productsTotalCount ? _productsTotalCount : endItem;

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
          // Информация о странице
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Показано $startItem-$actualEndItem из $_productsTotalCount',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Загружено страниц в кэш: ${_productsPageCache.length}',
                style: TextStyle(
                  color: Colors.blue[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),

          // Элементы управления пагинацией
          Row(
            children: [
              // Кнопки навигации
              IconButton(
                icon: const Icon(Icons.first_page),
                onPressed: _productsCurrentPage > 0
                    ? () => _loadProductsPage(0)
                    : null,
                tooltip: 'Первая страница',
              ),

              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _productsCurrentPage > 0
                    ? () => _loadProductsPage(_productsCurrentPage - 1)
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
                  '${_productsCurrentPage + 1} / $totalPages',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),

              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _productsCurrentPage < totalPages - 1
                    ? () => _loadProductsPage(_productsCurrentPage + 1)
                    : null,
                tooltip: 'Следующая страница',
              ),

              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: _productsCurrentPage < totalPages - 1
                    ? () => _loadProductsPage(totalPages - 1)
                    : null,
                tooltip: 'Последняя страница',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStocksPaginationControls() {
    final totalPages = (_stocksTotalCount / _stocksPerPage).ceil();
    final startItem = _stocksCurrentPage * _stocksPerPage + 1;
    final endItem = (_stocksCurrentPage + 1) * _stocksPerPage;
    final actualEndItem = endItem > _stocksTotalCount ? _stocksTotalCount : endItem;

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
          // Информация о странице
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Показано $startItem-$actualEndItem из $_stocksTotalCount',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Загружено страниц в кэш: ${_stocksPageCache.length}',
                style: TextStyle(
                  color: Colors.blue[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),

          // Элементы управления пагинацией
          Row(
            children: [
              // Кнопки навигации
              IconButton(
                icon: const Icon(Icons.first_page),
                onPressed: _stocksCurrentPage > 0
                    ? () => _loadStocksPage(0)
                    : null,
                tooltip: 'Первая страница',
              ),

              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _stocksCurrentPage > 0
                    ? () => _loadStocksPage(_stocksCurrentPage - 1)
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
                  '${_stocksCurrentPage + 1} / $totalPages',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),

              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _stocksCurrentPage < totalPages - 1
                    ? () => _loadStocksPage(_stocksCurrentPage + 1)
                    : null,
                tooltip: 'Следующая страница',
              ),

              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: _stocksCurrentPage < totalPages - 1
                    ? () => _loadStocksPage(totalPages - 1)
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
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text('Базы данных'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.inventory_2_outlined),
              text: 'Товары',
            ),
            Tab(
              icon: Icon(Icons.warehouse_outlined),
              text: 'Остатки FBO',
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              print('🔄 Обновление данных...');
              if (_tabController.index == 0) {
                _productsPageCache.clear();
                _loadProductsPage(0);
                _loadProductsTotalCount();
              } else {
                _stocksPageCache.clear();
                _loadStocksPage(0);
                _loadStocksTotalCount();
              }
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить данные',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Вкладка "Товары"
          Column(
            children: [
              // Информация о количестве товаров
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
                          'Всего товаров: $_productsTotalCount',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Загружено страниц: ${_productsPageCache.length}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (_isLoadingProducts)
                      const Padding(
                        padding: EdgeInsets.only(right: 8.0),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
              ),
              _buildProductsTable(),
              _buildProductsPaginationControls(),
            ],
          ),
          
          // Вкладка "Остатки FBO"
          Column(
            children: [
              // Информация о количестве остатков
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
                          'Всего записей остатков: $_stocksTotalCount',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Загружено страниц: ${_stocksPageCache.length}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (_isLoadingStocks)
                      const Padding(
                        padding: EdgeInsets.only(right: 8.0),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
              ),
              _buildStocksTable(),
              _buildStocksPaginationControls(),
            ],
          ),
        ],
      ),
    );
  }
}