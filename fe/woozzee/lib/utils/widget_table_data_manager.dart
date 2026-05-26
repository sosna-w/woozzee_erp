// lib/utils/widget_table_data_manager.dart - УПРОЩЕННАЯ ВЕРСИЯ
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/unified_products_data_model.dart';

/// Менеджер для предоставления данных виджетам-таблицам
/// Использует UnifiedProductsDataModel как источник данных
class WidgetTableDataManager {
  static final WidgetTableDataManager _instance = WidgetTableDataManager._internal();
  factory WidgetTableDataManager() => _instance;
  WidgetTableDataManager._internal();

  // Ссылка на модель данных
  final UnifiedProductsDataModel _dataModel = UnifiedProductsDataModel();

  // Маппинг названий атрибутов на поля в модели
  static const Map<String, String> _attributeFieldMap = {
    'Артикул': 'nm_id',
    'Мой артикул': 'vendor_code',
    'Баркод': 'barcode',
    'Наименование': 'title',
    'Остаток FBO': 'total_quantity',
    'Остаток FBS': 'fbs_quantity',
    'Тэги': 'tags', // Добавляем теги
  };

  // Метод для получения всех доступных атрибутов
  List<String> getAvailableAttributes() {
    return _attributeFieldMap.keys.toList();
  }

  // Метод для получения значения атрибута по nmId
  Future<dynamic> getAttributeValue(int nmId, String attributeName) async {
    try {
      // Получаем данные товара из модели
      final productData = _dataModel.getProductData(nmId);

      // Получаем поле из маппинга
      final fieldName = _attributeFieldMap[attributeName];
      if (fieldName == null) {
        return 'Атрибут не найден';
      }

      // Извлекаем значение
      final value = productData[fieldName];

      // Обрабатываем специальные случаи
      if (value == null) {
        if (attributeName == 'Тэги') {
          return [];
        }
        return '';
      } else if (attributeName == 'Тэги') {
        // Для тегов возвращаем как есть (список)
        return value;
      } else {
        return value.toString();
      }
    } catch (e) {
      print('❌ Ошибка получения значения атрибута $attributeName для $nmId: $e');
      if (attributeName == 'Тэги') {
        return [];
      }
      return 'Ошибка';
    }
  }

  // Метод для получения всех данных товара по nmId
  Future<Map<String, dynamic>> getProductData(int nmId) async {
    try {
      // Получаем данные из модели (синхронно, так как данные уже в памяти)
      return _dataModel.getProductData(nmId);
    } catch (e) {
      print('❌ Ошибка загрузки данных для товара $nmId: $e');
      return _getDefaultData();
    }
  }

  // Данные по умолчанию
  Map<String, dynamic> _getDefaultData() {
    return {
      'nm_id': '',
      'vendor_code': '',
      'barcode': '',
      'title': '',
      'total_quantity': '0',
      'fbs_quantity': '0',
      'tags': [], // Теги по умолчанию
    };
  }

  // Метод для принудительного обновления данных
  Future<void> refreshAllData() async {
    await _dataModel.refresh();
  }

  // Метод для получения заголовков таблицы
  static Map<String, String> getTableHeaders() {
    return _attributeFieldMap;
  }

  // Метод для получения описаний атрибутов
  static Map<String, String> getAttributeDescriptions() {
    return {
      'Артикул': 'Артикул Wildberries',
      'Мой артикул': 'Внутренний артикул товара',
      'Баркод': 'Штрихкод товара',
      'Наименование': 'Название товара',
      'Остаток FBO': 'Остаток на складе Wildberries',
      'Остаток FBS': 'Остаток на складе продавца',
      'Тэги': 'Теги товара', // Добавляем описание для тегов
    };
  }
}

/// Provider для управления состоянием данных таблиц
/// Теперь работает напрямую с моделью данных
class TableDataProvider extends ChangeNotifier {
  final WidgetTableDataManager _manager = WidgetTableDataManager();
  final Map<String, Map<int, String>> _widgetsData = {};
  final Map<String, bool> _widgetsLoading = {};

  // Метод для инициализации (проверяем, что модель загружена)
  Future<void> initializeAllData() async {
    // Данные уже загружены в модели при инициализации приложения
    notifyListeners();
  }

  // Получение данных для виджета
  Future<Map<int, String>> getWidgetData(
      String widgetId,
      int nmId,
      Map<int, String> attributeMap
      ) async {
    // Проверяем кэш для этого виджета
    final cacheKey = '${widgetId}_$nmId';

    if (_widgetsData.containsKey(cacheKey)) {
      return _widgetsData[cacheKey]!;
    }

    // Устанавливаем состояние загрузки
    _widgetsLoading[widgetId] = true;
    notifyListeners();

    try {
      final updatedData = await _updateWidgetData(nmId, attributeMap);

      // Сохраняем в кэш
      _widgetsData[cacheKey] = updatedData;
      return updatedData;
    } catch (e) {
      print('❌ Ошибка загрузки данных для виджета $widgetId: $e');
      return attributeMap.map((key, value) => MapEntry(key, 'Ошибка'));
    } finally {
      _widgetsLoading[widgetId] = false;
      notifyListeners();
    }
  }

  Future<Map<int, String>> _updateWidgetData(
      int nmId,
      Map<int, String> attributeMap
      ) async {
    final updatedData = <int, String>{};

    // Загружаем данные товара из модели
    final productData = await _manager.getProductData(nmId);

    // Заполняем значения атрибутов
    for (final entry in attributeMap.entries) {
      final rowIndex = entry.key;
      final attributeName = entry.value;

      // Получаем значение из данных
      final fieldName = WidgetTableDataManager.getTableHeaders()[attributeName];
      if (fieldName != null) {
        final value = productData[fieldName];
        if (value == null) {
          updatedData[rowIndex] = '';
        } else {
          // Для тегов формируем строку с тегами
          if (attributeName == 'Тэги' && value is List) {
            final tags = value;
            if (tags.isEmpty) {
              updatedData[rowIndex] = '';
            } else {
              // Формируем строку с тегами для простого отображения
              final tagNames = tags.map((tag) {
                if (tag is Map && tag.containsKey('name')) {
                  return tag['name'].toString();
                }
                return '';
              }).where((name) => name.isNotEmpty).toList();
              updatedData[rowIndex] = tagNames.join(', ');
            }
          } else {
            updatedData[rowIndex] = value.toString();
          }
        }
      } else {
        updatedData[rowIndex] = 'Недоступно';
      }
    }

    return updatedData;
  }

  // Очистка кэша
  void clearCache({String? widgetId, int? nmId}) {
    if (widgetId != null && nmId != null) {
      final cacheKey = '${widgetId}_$nmId';
      _widgetsData.remove(cacheKey);
    } else if (widgetId != null) {
      // Удаляем все данные для виджета
      final keysToRemove = _widgetsData.keys
          .where((key) => key.startsWith('${widgetId}_'))
          .toList();
      for (final key in keysToRemove) {
        _widgetsData.remove(key);
      }
      _widgetsLoading.remove(widgetId);
    } else {
      // Очищаем все
      _widgetsData.clear();
      _widgetsLoading.clear();
    }

    notifyListeners();
  }

  // Проверка состояния загрузки
  bool isLoading(String widgetId) {
    return _widgetsLoading[widgetId] ?? false;
  }

  // Получение кэшированных данных
  Map<int, String>? getCachedData(String widgetId, int nmId) {
    final cacheKey = '${widgetId}_$nmId';
    return _widgetsData[cacheKey];
  }
}