// lib/utils/product_manager.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import 'token_manager.dart';

class ProductManager with ChangeNotifier {
  // Singleton instance
  static final ProductManager _instance = ProductManager._internal();
  factory ProductManager() => _instance;
  ProductManager._internal();

  // Данные
  List<Product> _products = [];
  List<Product> _productsWithPhotos = [];
  Map<int, Product> _productsById = {};
  Map<int, Product> _productsByChrtID = {}; // Новая карта: chrtID -> Product

  // Состояние
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;
  DateTime? _lastUpdateTime;
  Timer? _backgroundUpdateTimer;

  // Настройки
  static const String _cacheFileName = 'products_cache.json';
  static const String _lastUpdateKey = 'products_last_update';
  static const int _backgroundUpdateIntervalMinutes = 15; // Обновление каждые 15 минут
  static const int _cacheMaxAgeMinutes = 60; // Максимальный возраст кэша 1 час

  // Геттеры
  List<Product> get allProducts => List.unmodifiable(_products);
  List<Product> get productsWithPhotos => List.unmodifiable(_productsWithPhotos);
  Map<int, Product> get productsById => Map.unmodifiable(_productsById);
  Map<int, Product> get productsByChrtID => Map.unmodifiable(_productsByChrtID);
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdateTime => _lastUpdateTime;
  int get totalProducts => _products.length;
  int get productsWithPhotosCount => _productsWithPhotos.length;

  /// Инициализация менеджера
  Future<void> initialize() async {
    if (_isInitialized) return;

    print('🔄 Инициализация ProductManager...');

    try {
      // 1. Загружаем из кэша
      await _loadFromCache();

      // 2. Проверяем актуальность кэша
      final bool cacheIsValid = await _isCacheValid();

      if (!cacheIsValid) {
        // Если кэш не валиден, загружаем с сервера
        print('⚠️ Кэш устарел или не найден, загружаем с сервера...');
        await _fetchFromServer();
      } else {
        print('✅ Используем кэшированные данные (обновлено: $_lastUpdateTime)');
      }

      // 3. Запускаем фоновое обновление
      _startBackgroundUpdates();

      _isInitialized = true;
      notifyListeners();

      print(
          '✅ ProductManager инициализирован. Товаров: ${_products.length}, с фото: ${_productsWithPhotos.length}, chrtID-связей: ${_productsByChrtID.length}');
    } catch (e) {
      print('❌ Ошибка инициализации ProductManager: $e');
      _hasError = true;
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Проверка валидности кэша
  Future<bool> _isCacheValid() async {
    if (_products.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final lastUpdateStr = prefs.getString(_lastUpdateKey);

    if (lastUpdateStr == null) return false;

    try {
      final lastUpdate = DateTime.parse(lastUpdateStr);
      final now = DateTime.now();
      final diff = now.difference(lastUpdate).inMinutes;

      return diff < _cacheMaxAgeMinutes;
    } catch (e) {
      return false;
    }
  }

  /// Загрузка данных из кэша
  Future<void> _loadFromCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_cacheFileName');

      if (!await file.exists()) {
        print('📂 Файл кэша не найден');
        return;
      }

      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);

      _products = jsonList.map((json) => Product.fromJson(json)).toList();
      _updateDerivedCollections();

      // Загружаем время последнего обновления
      final prefs = await SharedPreferences.getInstance();
      final lastUpdateStr = prefs.getString(_lastUpdateKey);
      if (lastUpdateStr != null) {
        _lastUpdateTime = DateTime.parse(lastUpdateStr);
      }

      print('📂 Загружено ${_products.length} товаров из кэша');
    } catch (e) {
      print('⚠️ Ошибка загрузки из кэша: $e');
      // В случае ошибки очищаем кэш
      _products.clear();
      _productsWithPhotos.clear();
      _productsById.clear();
      _productsByChrtID.clear();
    }
  }

  /// Сохранение данных в кэш
  Future<void> _saveToCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_cacheFileName');

      final jsonList = _products.map((product) => product.toJson()).toList();
      final jsonString = jsonEncode(jsonList);

      await file.writeAsString(jsonString);

      // Сохраняем время обновления
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastUpdateKey, DateTime.now().toIso8601String());

      print('💾 Сохранено ${_products.length} товаров в кэш');
    } catch (e) {
      print('⚠️ Ошибка сохранения в кэш: $e');
    }
  }

  /// Загрузка данных с сервера
  Future<void> _fetchFromServer({bool force = false}) async {
    if (_isLoading && !force) return;
    _isLoading = true;
    _hasError = false;
    _errorMessage = null;
    notifyListeners();

    try {
      print('🌐 Загрузка товаров с сервера (постранично)...');
      final token = TokenManager().token;
      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': token,
      };

      int page = 1;
      const int perPage = 1000;
      List<Product> allProducts = [];
      bool hasMore = true;

      while (hasMore) {
        final url = 'https://hide_domain.com/products?page=$page&per_page=$perPage';
        final response = await http.get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List<dynamic> productsJson = data['products'] ?? [];
          final pagination = data['pagination'] as Map<String, dynamic>?;
          final totalPages = pagination?['pages'] as int? ?? 1;

          final newProducts = productsJson
              .map((json) => Product.fromJson(json))
              .where((p) => p.nmID != 0)
              .toList();
          allProducts.addAll(newProducts);
          print('📄 Страница $page: загружено ${newProducts.length} товаров');

          if (page >= totalPages) hasMore = false;
          page++;
        } else if (response.statusCode == 401) {
          throw Exception('Ошибка авторизации (401). Проверьте токен API');
        } else {
          throw Exception('Ошибка сервера: ${response.statusCode}');
        }
      }

      _products = allProducts;
      _updateDerivedCollections();
      _lastUpdateTime = DateTime.now();
      await _saveToCache();
      print('✅ Загружено всего ${_products.length} товаров');
    } catch (e) {
      print('❌ Ошибка загрузки с сервера: $e');
      _hasError = true;
      _errorMessage = e.toString();
      if (_products.isEmpty) rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Обновление производных коллекций
  void _updateDerivedCollections() {
    // Продукты с фото
    _productsWithPhotos = _products.where((product) => product.hasPhotos()).toList();

    // Словарь по nmID
    _productsById = {for (var product in _products) product.nmID: product};

    // Словарь по chrtID (каждый размер товара указывает на тот же продукт)
    _productsByChrtID.clear();
    for (var product in _products) {
      for (var size in product.sizes) {
        _productsByChrtID[size.chrtID] = product;
      }
    }

    print(
        '📊 Обновлены коллекции: всего ${_products.length}, с фото ${_productsWithPhotos.length}, chrtID-связей ${_productsByChrtID.length}');
  }

  /// Принудительное обновление данных
  Future<void> refresh({bool showLoading = true}) async {
    print('🔃 Принудительное обновление товаров...');
    await _fetchFromServer(force: true);
  }

  /// Запуск фоновых обновлений
  void _startBackgroundUpdates() {
    // Останавливаем предыдущий таймер, если есть
    _backgroundUpdateTimer?.cancel();

    // Запускаем новый таймер
    _backgroundUpdateTimer = Timer.periodic(
      Duration(minutes: _backgroundUpdateIntervalMinutes),
      (_) async {
        print('🔄 Фоновое обновление товаров...');
        await _fetchFromServer();
      },
    );

    print('⏰ Фоновые обновления запущены (каждые $_backgroundUpdateIntervalMinutes минут)');
  }

  /// Остановка фоновых обновлений
  void stopBackgroundUpdates() {
    _backgroundUpdateTimer?.cancel();
    _backgroundUpdateTimer = null;
    print('⏹️ Фоновые обновления остановлены');
  }

  /// Поиск товаров
  List<Product> searchProducts(String query,
      {bool onlyWithPhotos = false, bool searchByChrtID = true}) {
    if (query.isEmpty) {
      return onlyWithPhotos ? _productsWithPhotos : _products;
    }

    final searchLower = query.toLowerCase();
    final source = onlyWithPhotos ? _productsWithPhotos : _products;

    return source.where((product) {
      // Поиск по стандартным полям
      if (product.title.toLowerCase().contains(searchLower) ||
          product.vendorCode.toLowerCase().contains(searchLower) ||
          product.nmID.toString().contains(searchLower) ||
          product.subjectName.toLowerCase().contains(searchLower)) {
        return true;
      }

      // Поиск по chrtID (если включён)
      if (searchByChrtID) {
        // Если запрос — число, ищем точное совпадение
        final int? chrtIdInt = int.tryParse(query);
        if (chrtIdInt != null && product.allChrtIDs.contains(chrtIdInt)) {
          return true;
        }
        // Поиск по вхождению строки chrtID (например, "694177")
        if (product.allChrtIDs.any((id) => id.toString().contains(searchLower))) {
          return true;
        }
      }

      return false;
    }).toList();
  }

  /// Получение товара по nmID
  Product? getProductById(int nmId) {
    return _productsById[nmId];
  }

  /// Получение товара по chrtID (размерный ID)
  Product? getProductByChrtID(int chrtID) {
    return _productsByChrtID[chrtID];
  }

  /// Получение всех уникальных chrtID из всех товаров
  List<int> getAllChrtIDs() {
    return _productsByChrtID.keys.toList();
  }

  /// Получение товаров с фото для пагинации
  List<Product> getProductsWithPhotosPage(int page, int itemsPerPage) {
    final start = page * itemsPerPage;
    final end = start + itemsPerPage;

    if (start >= _productsWithPhotos.length) {
      return [];
    }

    return _productsWithPhotos.sublist(
      start,
      end > _productsWithPhotos.length ? _productsWithPhotos.length : end,
    );
  }

  /// Получение всех товаров для пагинации
  List<Product> getAllProductsPage(int page, int itemsPerPage) {
    final start = page * itemsPerPage;
    final end = start + itemsPerPage;

    if (start >= _products.length) {
      return [];
    }

    return _products.sublist(
      start,
      end > _products.length ? _products.length : end,
    );
  }

  /// Получение URL фото товара
  List<String> getProductPhotos(int nmId) {
    final product = getProductById(nmId);
    return product?.getPhotoUrls() ?? [];
  }

  /// Очистка кэша
  Future<void> clearCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_cacheFileName');

      if (await file.exists()) {
        await file.delete();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastUpdateKey);

      _products.clear();
      _productsWithPhotos.clear();
      _productsById.clear();
      _productsByChrtID.clear();
      _lastUpdateTime = null;

      print('🗑️ Кэш товаров очищен');
      notifyListeners();
    } catch (e) {
      print('⚠️ Ошибка очистки кэша: $e');
    }
  }

  /// Очистка кэша для конкретного товара (перезагрузка всего)
  Future<void> clearProductCache(int nmId) async {
    await refresh();
  }

  /// Получение статистики
  Map<String, dynamic> getStats() {
    return {
      'totalProducts': _products.length,
      'productsWithPhotos': _productsWithPhotos.length,
      'lastUpdate': _lastUpdateTime?.toIso8601String(),
      'uniqueChrtIDs': _productsByChrtID.length,
      'cacheSize': _products.length * 2, // Примерный размер в KB
    };
  }

  @override
  void dispose() {
    stopBackgroundUpdates();
    super.dispose();
  }
}

// Расширенные методы для работы с товарами в изоляте (для тяжелых операций)
class ProductWorker {
  static Future<List<Product>> parseProductsInBackground(String jsonString) async {
    return await compute(_parseProducts, jsonString);
  }

  static List<Product> _parseProducts(String jsonString) {
    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((json) => Product.fromJson(json)).toList();
  }
}