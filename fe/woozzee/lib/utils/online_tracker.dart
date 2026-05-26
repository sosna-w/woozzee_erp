// online_tracker.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'constants.dart';

class OnlineTracker {
  static final OnlineTracker _instance = OnlineTracker._internal();
  factory OnlineTracker() => _instance;
  OnlineTracker._internal();

  static const String baseUrl = 'https://hide_domain.com';
  static const String endpoint = '/online';
  static const Duration interval = Duration(seconds: 60);

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  Timer? _timer;
  String? _username;
  bool _isTracking = false;

  /// Инициализация трекера
  Future<void> initialize() async {
    try {
      _username = await _getDeviceUsername();
      print('🔄 OnlineTracker инициализирован для пользователя: $_username');
    } catch (e) {
      print('⚠️ Ошибка инициализации OnlineTracker: $e');
      _username = 'unknown_user';
    }
  }

  /// Начать отслеживание онлайн-статуса
  void startTracking() {
    if (_isTracking) return;

    _isTracking = true;
    
    // Сразу отправляем первый запрос
    _sendOnlineStatus();
    
    // Запускаем периодическую отправку
    _timer = Timer.periodic(interval, (_) {
      _sendOnlineStatus();
    });
    
    print('🟢 OnlineTracker: начато отслеживание онлайн-статуса');
  }

  /// Остановить отслеживание
  void stopTracking() {
    _timer?.cancel();
    _timer = null;
    _isTracking = false;
    print('🟡 OnlineTracker: отслеживание остановлено');
  }

  /// Отправка статуса онлайн
  Future<void> _sendOnlineStatus() async {
    if (_username == null) {
      await initialize();
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'username': _username ?? 'unknown_user',
          'activity_type': 'online',
          'details': {
            'app_version': appVersion,
            'platform': Platform.operatingSystem,
            'platform_version': Platform.operatingSystemVersion,
            'timestamp': DateTime.now().toIso8601String(),
          }
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          print('✅ Online статус отправлен: $_username');
        }
      } else {
        print('❌ Ошибка отправки онлайн-статуса: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Ошибка сети при отправке онлайн-статуса: $e');
    }
  }

  /// Получение имени устройства
  Future<String> _getDeviceUsername() async {
    try {
      if (Platform.isWindows) {
        final windowsInfo = await _deviceInfo.windowsInfo;
        return windowsInfo.computerName ?? 'Windows_User';
      } else if (Platform.isLinux) {
        final linuxInfo = await _deviceInfo.linuxInfo;
        return linuxInfo.prettyName ?? 'Linux_User';
      } else if (Platform.isMacOS) {
        final macInfo = await _deviceInfo.macOsInfo;
        return macInfo.computerName ?? 'Mac_User';
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.device ?? 'Android_User';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.name ?? 'iOS_User';
      }
    } catch (e) {
      print('⚠️ Ошибка получения информации об устройстве: $e');
    }
    
    return 'unknown_user_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Получить текущее имя пользователя
  String? get currentUsername => _username;

  /// Проверить, активно ли отслеживание
  bool get isTracking => _isTracking;

  /// Принудительно отправить статус онлайн
  Future<void> sendManualStatus({String? activityType, Map<String, dynamic>? customDetails}) async {
    final details = {
      'app_version': appVersion,
      'platform': Platform.operatingSystem,
      'timestamp': DateTime.now().toIso8601String(),
      'manual_trigger': true,
      ...?customDetails,
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': _username ?? 'unknown_user',
          'activity_type': activityType ?? 'manual_ping',
          'details': details,
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Ручной статус отправлен успешно');
      }
    } catch (e) {
      print('❌ Ошибка отправки ручного статуса: $e');
    }
  }
}