// hint_manager.dart - Менеджер для управления подсказками с сохранением в SharedPreferences
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HintManager {
  static const String _keyHintConstructor = 'hint_constructor';
  static HintManager? _instance;
  late SharedPreferences _prefs;

  HintManager._internal();

  static Future<HintManager> getInstance() async {
    if (_instance == null) {
      _instance = HintManager._internal();
      await _instance!._init();
    }
    return _instance!;
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Проверка, нужно ли показывать подсказку для конструктора
  bool shouldShowConstructorHint() {
    final isDisabled = _prefs.getBool(_keyHintConstructor);
    // Если isDisabled == true (подсказка отключена), возвращаем false
    // В противном случае (null или false) возвращаем true
    return isDisabled != true;
  }

  // Отключить подсказку для конструктора навсегда
  Future<void> disableConstructorHint() async {
    await _prefs.setBool(_keyHintConstructor, true);
  }

  // Сбросить все подсказки (для тестирования)
  Future<void> resetAllHints() async {
    await _prefs.remove(_keyHintConstructor);
  }
}