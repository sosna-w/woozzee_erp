import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TokenManager {
  static final TokenManager _instance = TokenManager._internal();
  factory TokenManager() => _instance;
  TokenManager._internal();

  static const String _tokenKey = 'wb_api_token';
  static const String _serverTokenUrl = 'https://hide_domain.com/token';

  String? _cachedToken;

  // [ДОБАВЬТЕ ЭТОТ ПУБЛИЧНЫЙ ГЕТТЕР]
  bool get isInitialized => _isInitialized;
  bool _isInitialized = false;

  /// Инициализация менеджера - загрузка токена при старте приложения
  /// Инициализация менеджера - загрузка токена при старте приложения
  Future<void> initialize() async {
    if (_isInitialized) {
      print('✅ TokenManager уже инициализирован');
      return;
    }

    try {
      print('🔄 Инициализация TokenManager...');

      // Сначала пробуем загрузить из кэша
      await _loadFromCache();

      // Если в кэше нет, загружаем с сервера
      if (_cachedToken == null || _cachedToken!.isEmpty) {
        print('📡 Токен не найден в кэше, загружаем с сервера...');
        await _loadToken(); // ← ИСПРАВЛЕНО: было _loadFromServer()
      } else {
        print('✅ Токен загружен из кэша');
      }

    } catch (e) {
      print('⚠️ Ошибка инициализации TokenManager: $e');
      // Даже при ошибке помечаем как инициализированный
    } finally {
      _isInitialized = true;
      print('✅ TokenManager помечен как инициализированный');
    }
  }

  /// Загрузка токена с сервера и сохранение в кэш
  Future<void> _loadToken() async {
    try {
      final response = await http.get(
        Uri.parse(_serverTokenUrl),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['token_value'] as String?;
        
        if (token != null && token.isNotEmpty) {
          _cachedToken = token;
          // Сохраняем в SharedPreferences для быстрого доступа
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_tokenKey, token);
          print('✅ Токен загружен и сохранен локально');
        }
      }
    } catch (e) {
      print('⚠️ Ошибка загрузки токена с сервера: $e');
      // Пытаемся загрузить из локального хранилища
      await _loadFromCache();
    }
  }

  /// Загрузка токена из локального кэша
  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedToken = prefs.getString(_tokenKey);
      
      if (cachedToken != null && cachedToken.isNotEmpty) {
        _cachedToken = cachedToken;
        print('✅ Токен загружен из локального кэша');
      } else {
        print('⚠️ Токен не найден в кэше');
      }
    } catch (e) {
      print('⚠️ Ошибка загрузки токена из кэша: $e');
    }
  }

  /// Получение токена (синхронно, если он уже загружен)
  String? get token => _cachedToken;

  /// Асинхронное получение токена с проверкой
  Future<String?> getToken() async {
    // Если токен уже в памяти, возвращаем его
    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
      return _cachedToken;
    }
    
    // Загружаем из кэша
    await _loadFromCache();
    return _cachedToken;
  }

  /// Сохранение нового токена
  Future<bool> saveToken(String token) async {
    try {
      // Сохраняем на сервер
      final response = await http.post(
        Uri.parse(_serverTokenUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'token_value': token}),
      );

      if (response.statusCode == 200) {
        _cachedToken = token;
        
        // Сохраняем локально
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, token);
        
        print('✅ Токен успешно сохранен');
        return true;
      }
    } catch (e) {
      print('⚠️ Ошибка сохранения токена: $e');
      
      // Пытаемся сохранить хотя бы локально
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, token);
        _cachedToken = token;
        print('✅ Токен сохранен локально (оффлайн)');
        return true;
      } catch (cacheError) {
        print('⚠️ Ошибка локального сохранения: $cacheError');
      }
    }
    
    return false;
  }

  /// Очистка токена
  Future<void> clearToken() async {
    _cachedToken = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      print('✅ Токен очищен');
    } catch (e) {
      print('⚠️ Ошибка очистки токена: $e');
    }
  }

  /// Проверка наличия токена
  Future<bool> hasToken() async {
    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
      return true;
    }
    
    await _loadFromCache();
    return _cachedToken != null && _cachedToken!.isNotEmpty;
  }

  /// Быстрая проверка (синхронная)
  bool hasTokenSync() {
    return _cachedToken != null && _cachedToken!.isNotEmpty;
  }

  /// Обновление токена с сервера
  Future<bool> refreshToken() async {
    try {
      await _loadToken();
      return _cachedToken != null && _cachedToken!.isNotEmpty;
    } catch (e) {
      print('⚠️ Ошибка обновления токена: $e');
      return false;
    }
  }
}