// private_token_manager.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class PrivateTokenManager {
  static final PrivateTokenManager _instance = PrivateTokenManager._internal();
  factory PrivateTokenManager() => _instance;
  PrivateTokenManager._internal();

  static const String _authorizeV3Key = 'wb_private_authorizev3';
  static const String _wbSellerLkKey = 'wb_private_wb_seller_lk';
  static const String _cookieKey = 'wb_private_cookie';

  // Кэшированные значения
  String? _cachedAuthorizeV3;
  String? _cachedWbSellerLk;
  String? _cachedCookie;
  bool _isInitialized = false;

  // ========== Инициализация и загрузка из локального хранилища ==========
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _loadFromCache();
    } catch (e) {
      print('⚠️ Ошибка инициализации PrivateTokenManager: $e');
    } finally {
      _isInitialized = true;
    }
  }

  Future<void> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedAuthorizeV3 = prefs.getString(_authorizeV3Key);
    _cachedWbSellerLk = prefs.getString(_wbSellerLkKey);
    _cachedCookie = prefs.getString(_cookieKey);
  }

  // ========== Геттеры (синхронные – используют кэш) ==========
  String? get authorizeV3 => _cachedAuthorizeV3;
  String? get wbSellerLk => _cachedWbSellerLk;
  String? get cookie => _cachedCookie;

  // ========== Локальное сохранение (используется как fallback и при синхронизации) ==========
  Future<void> _saveToLocal({
    required String? authorizeV3,
    required String? wbSellerLk,
    required String? cookie,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (authorizeV3 != null) {
      _cachedAuthorizeV3 = authorizeV3;
      await prefs.setString(_authorizeV3Key, authorizeV3);
    }
    if (wbSellerLk != null) {
      _cachedWbSellerLk = wbSellerLk;
      await prefs.setString(_wbSellerLkKey, wbSellerLk);
    }
    if (cookie != null) {
      _cachedCookie = cookie;
      await prefs.setString(_cookieKey, cookie);
    }
  }

  Future<void> _clearLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authorizeV3Key);
    await prefs.remove(_wbSellerLkKey);
    await prefs.remove(_cookieKey);
    _cachedAuthorizeV3 = null;
    _cachedWbSellerLk = null;
    _cachedCookie = null;
  }

  // ========== Серверная синхронизация ==========
  /// Загружает ключи с сервера и сохраняет локально (если на сервере есть непустые значения)
  Future<void> loadFromServer() async {
    try {
      final response = await http.get(
        Uri.parse('https://hide_domain.com/private-keys'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final auth = data['authorize_v3']?.toString() ?? '';
        final wb = data['wb_seller_lk']?.toString() ?? '';
        final ck = data['cookie']?.toString() ?? '';

        // Если сервер вернул непустые значения – сохраняем их локально
        if (auth.isNotEmpty || wb.isNotEmpty || ck.isNotEmpty) {
          await _saveToLocal(
            authorizeV3: auth.isNotEmpty ? auth : null,
            wbSellerLk: wb.isNotEmpty ? wb : null,
            cookie: ck.isNotEmpty ? ck : null,
          );
          print('✅ Приватные ключи загружены с сервера');
        } else {
          // На сервере пустые ключи – чистим локально
          await _clearLocal();
          print('ℹ️ На сервере нет приватных ключей, локальные очищены');
        }
      } else {
        print('⚠️ Ошибка загрузки ключей с сервера: ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ Ошибка сети при загрузке ключей с сервера: $e');
    }
  }

  /// Сохраняет ключи на сервер и локально
  Future<void> saveToServer(String authorizeV3, String wbSellerLk, String cookie) async {
    try {
      final response = await http.post(
        Uri.parse('https://hide_domain.com/private-keys'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'authorize_v3': authorizeV3,
          'wb_seller_lk': wbSellerLk,
          'cookie': cookie,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('✅ Ключи сохранены на сервере');
        // Сохраняем локально (кеш)
        await _saveToLocal(
          authorizeV3: authorizeV3,
          wbSellerLk: wbSellerLk,
          cookie: cookie,
        );
      } else {
        print('⚠️ Ошибка сохранения на сервере: ${response.statusCode}');
        // Если сервер недоступен – сохраняем хотя бы локально
        await _saveToLocal(
          authorizeV3: authorizeV3,
          wbSellerLk: wbSellerLk,
          cookie: cookie,
        );
        throw Exception('Не удалось сохранить ключи на сервере');
      }
    } catch (e) {
      print('⚠️ Ошибка сети при сохранении на сервере: $e');
      // Fallback – локальное сохранение
      await _saveToLocal(
        authorizeV3: authorizeV3,
        wbSellerLk: wbSellerLk,
        cookie: cookie,
      );
      rethrow;
    }
  }

  /// Очищает ключи на сервере и локально
  Future<void> clearOnServer() async {
    try {
      final response = await http.delete(
        Uri.parse('https://hide_domain.com/private-keys'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('✅ Ключи на сервере очищены');
      } else {
        print('⚠️ Ошибка очистки на сервере: ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ Ошибка сети при очистке на сервере: $e');
    } finally {
      // В любом случае очищаем локально
      await _clearLocal();
    }
  }

  // ========== Вспомогательные методы ==========
  Future<bool> hasKeys() async {
    await initialize();
    return (_cachedAuthorizeV3 != null && _cachedAuthorizeV3!.isNotEmpty &&
        _cachedWbSellerLk != null && _cachedWbSellerLk!.isNotEmpty &&
        _cachedCookie != null && _cachedCookie!.isNotEmpty);
  }

  bool hasKeysSync() {
    return (_cachedAuthorizeV3 != null && _cachedAuthorizeV3!.isNotEmpty &&
        _cachedWbSellerLk != null && _cachedWbSellerLk!.isNotEmpty &&
        _cachedCookie != null && _cachedCookie!.isNotEmpty);
  }

  Map<String, String> getPrivateHeaders() {
    return {
      'authorizev3': _cachedAuthorizeV3 ?? '',
      'wb-seller-lk': _cachedWbSellerLk ?? '',
      'Cookie': _cachedCookie ?? '',
      'Content-Type': 'application/json',
    };
  }

  // Для обратной совместимости (старые названия методов)
  @Deprecated('Use saveToServer instead')
  Future<void> saveKeys({required String authorizeV3, required String wbSellerLk, required String cookie}) async {
    await saveToServer(authorizeV3, wbSellerLk, cookie);
  }

  @Deprecated('Use clearOnServer instead')
  Future<void> clearKeys() async {
    await clearOnServer();
  }
}