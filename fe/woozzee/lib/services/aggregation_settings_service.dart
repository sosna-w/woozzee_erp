// lib/services/aggregation_settings_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AggregationSettingsService {
  static const String _key = 'aggregation_settings';
  static const String _displayModeKey = 'display_mode_settings';
  static const String _frozenKey = 'frozen_settings';
  static const String _columnOrderKey = 'column_order';
  static const String _hiddenColumnsKey = 'hidden_columns'; // новый ключ

  Map<String, String> _methods = {};
  Map<String, String> _displayModes = {};
  Map<String, String> _frozen = {};
  Set<String> _hiddenColumns = {}; // множество скрытых полей

  Future<void> init() async {
    await load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // Загружаем методы агрегации
    final jsonString = prefs.getString(_key);
    if (jsonString != null) {
      try {
        final Map<String, dynamic> data = json.decode(jsonString);
        _methods = data.map((key, value) => MapEntry(key, value.toString()));
      } catch (e) {
        _methods = {};
      }
    }

    // Загружаем режимы отображения
    final displayJson = prefs.getString(_displayModeKey);
    if (displayJson != null) {
      try {
        final Map<String, dynamic> data = json.decode(displayJson);
        _displayModes = data.map((key, value) => MapEntry(key, value.toString()));
      } catch (e) {
        _displayModes = {};
      }
    }

    // Загружаем frozen состояния
    final frozenJson = prefs.getString(_frozenKey);
    if (frozenJson != null) {
      try {
        final Map<String, dynamic> data = json.decode(frozenJson);
        _frozen = data.map((key, value) => MapEntry(key, value.toString()));
      } catch (e) {
        _frozen = {};
      }
    }

    // Загружаем скрытые колонки
    await _loadHiddenColumnsInternal(prefs);
  }

  // Внутренний метод загрузки скрытых колонок
  Future<void> _loadHiddenColumnsInternal(SharedPreferences prefs) async {
    final list = prefs.getStringList(_hiddenColumnsKey);
    if (list != null) {
      _hiddenColumns = Set.from(list);
    } else {
      _hiddenColumns.clear();
    }
  }

  // Публичный метод для загрузки скрытых колонок (возвращает копию)
  Future<Set<String>> loadHiddenColumns() async {
    final prefs = await SharedPreferences.getInstance();
    await _loadHiddenColumnsInternal(prefs);
    return Set.from(_hiddenColumns);
  }

  // Сохранение скрытых колонок
  Future<void> saveHiddenColumns(Set<String> fields) async {
    final prefs = await SharedPreferences.getInstance();
    _hiddenColumns = Set.from(fields);
    await prefs.setStringList(_hiddenColumnsKey, fields.toList());
  }

  // Получить текущие скрытые колонки
  Set<String> getHiddenColumns() {
    return Set.from(_hiddenColumns);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();

    final jsonString = json.encode(_methods);
    await prefs.setString(_key, jsonString);

    final displayJson = json.encode(_displayModes);
    await prefs.setString(_displayModeKey, displayJson);

    final frozenJson = json.encode(_frozen);
    await prefs.setString(_frozenKey, frozenJson);

    // hiddenColumns не сохраняем здесь, т.к. сохраняем отдельно через saveHiddenColumns
  }

  // Методы агрегации
  String getMethod(String field) {
    return _methods[field] ?? 'none';
  }

  Future<void> setMethod(String field, String method) async {
    _methods[field] = method;
    await _save();
  }

  Map<String, String> getAllMethods() {
    return Map.from(_methods);
  }

  // Режимы отображения
  String getDisplayMode(String field) {
    return _displayModes[field] ?? 'sum';
  }

  Future<void> setDisplayMode(String field, String mode) async {
    _displayModes[field] = mode;
    await _save();
  }

  Map<String, String> getAllDisplayModes() {
    return Map.from(_displayModes);
  }

  // Frozen состояния
  String getFrozen(String field) {
    return _frozen[field] ?? 'none';
  }

  Future<void> setFrozen(String field, String frozen) async {
    if (frozen == 'none') {
      _frozen.remove(field);
    } else {
      _frozen[field] = frozen;
    }
    await _save();
  }

  Map<String, String> getAllFrozen() {
    return Map.from(_frozen);
  }

  Future<void> clear() async {
    _methods.clear();
    _displayModes.clear();
    _frozen.clear();
    _hiddenColumns.clear();
    await _save();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_columnOrderKey);
    await prefs.remove(_hiddenColumnsKey); // удаляем и скрытые колонки
  }

  // Порядок колонок
  Future<void> saveColumnOrder(List<String> fields) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_columnOrderKey, fields);
  }

  Future<List<String>?> loadColumnOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final order = prefs.getStringList(_columnOrderKey);
    print('📂 Загрузка порядка колонок из SharedPreferences: ${order ?? 'нет сохранённого порядка'}');
    return order;
  }
}