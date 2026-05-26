// business_analytics_app.dart - ОБНОВЛЕННАЯ ВЕРСИЯ С АВТОПОКАЗОМ ОБНОВЛЕНИЙ И УПРАВЛЕНИЕМ ONLINE ТРЕКЕРОМ
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/left_sidebar.dart';
import '../widgets/main_content.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/dialogs/menu_dialog.dart';
import '../widgets/dialogs/api_dialog.dart';
import '../widgets/dialogs/update_dialog.dart';
import '../widgets/settings_screen.dart';
import '../widgets/logs_screen.dart';
import '../widgets/database_screen.dart';
import '../widgets/cost_screen.dart';
import '../widgets/global_browser_manager.dart';
import '../utils/update_manager.dart';
import '../utils/online_tracker.dart';
import 'theme.dart';
import '../utils/constants.dart';

class BusinessAnalyticsApp extends StatefulWidget {
  final GlobalBrowserManager browserManager;

  const BusinessAnalyticsApp({super.key, required this.browserManager});

  @override
  State<BusinessAnalyticsApp> createState() => _BusinessAnalyticsAppState();
}

class _BusinessAnalyticsAppState extends State<BusinessAnalyticsApp> with WidgetsBindingObserver {
  int _currentBottomIndex = 7;
  int _previousBottomIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FocusNode _focusNode = FocusNode();
  late final OnlineTracker _onlineTracker;
  Timer? _appActivityTimer;
  DateTime _lastUserActivity = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _onlineTracker = OnlineTracker();
    _focusNode.requestFocus();

    // Запускаем таймер для отслеживания активности приложения
    _startActivityTracking();

    // Показываем диалог обновлений после инициализации виджета
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPendingUpdateDialog();
    });

    // Отправляем начальный статус "app_started"
    _sendAppStartedStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Обработка изменений состояния приложения
    switch (state) {
      case AppLifecycleState.resumed:
      // Приложение снова активно
        print('🔄 Приложение возобновило работу');
        if (!_onlineTracker.isTracking) {
          _onlineTracker.startTracking();
        }
        // Отправляем статус возврата
        _onlineTracker.sendManualStatus(
            activityType: 'app_resumed',
            customDetails: {
              'resume_time': DateTime.now().toIso8601String(),
              'inactive_duration': _calculateInactiveDuration(),
            }
        );
        _lastUserActivity = DateTime.now();
        break;

      case AppLifecycleState.paused:
      // Приложение неактивно или свернуто
        print('⏸️ Приложение приостановлено');
        _onlineTracker.sendManualStatus(
            activityType: 'app_paused',
            customDetails: {
              'pause_time': DateTime.now().toIso8601String(),
              'last_activity': _lastUserActivity.toIso8601String(),
            }
        );
        break;

      case AppLifecycleState.inactive:
      // Приложение неактивно (переходное состояние)
        print('⚫ Приложение неактивно');
        break;

      case AppLifecycleState.detached:
      // Приложение закрывается (в основном для iOS)
        print('🔴 Приложение отсоединено');
        _cleanupResources();
        break;

      case AppLifecycleState.hidden:
      // Приложение скрыто
        print('👁️ Приложение скрыто');
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.dispose();
    _appActivityTimer?.cancel();

    // Очищаем ресурсы при уничтожении виджета
    _cleanupResources();

    super.dispose();
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        _toggleBrowserTab();
      }
      // Обновляем время последней активности при любом нажатии клавиши
      _updateUserActivity();
    }
  }

  void _toggleBrowserTab() {
    final browserTabIndex = 6;

    setState(() {
      if (_currentBottomIndex != browserTabIndex) {
        _previousBottomIndex = _currentBottomIndex;
        _currentBottomIndex = browserTabIndex;
      } else {
        _currentBottomIndex = _previousBottomIndex;
      }
    });

    _updateUserActivity();
  }

  void _updateUserActivity() {
    _lastUserActivity = DateTime.now();
  }

  int _calculateInactiveDuration() {
    final now = DateTime.now();
    final difference = now.difference(_lastUserActivity);
    return difference.inSeconds;
  }

  void _startActivityTracking() {
    // Проверяем активность каждые 30 секунд
    _appActivityTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      final inactiveDuration = _calculateInactiveDuration();

      // Если пользователь неактивен более 5 минут, отправляем специальный статус
      if (inactiveDuration > 300) {
        _onlineTracker.sendManualStatus(
            activityType: 'user_inactive',
            customDetails: {
              'inactive_duration_seconds': inactiveDuration,
              'last_activity_time': _lastUserActivity.toIso8601String(),
            }
        );
      }
    });
  }

  Future<void> _sendAppStartedStatus() async {
    // Небольшая задержка перед отправкой начального статуса
    await Future.delayed(const Duration(seconds: 2));

    await _onlineTracker.sendManualStatus(
        activityType: 'app_started',
        customDetails: {
          'startup_time': DateTime.now().toIso8601String(),
          'platform': Platform.operatingSystem,
          'platform_version': Platform.operatingSystemVersion,
          'screen_size': '${WidgetsBinding.instance.window.physicalSize.width}x${WidgetsBinding.instance.window.physicalSize.height}',
        }
    );
  }

  void _cleanupResources() {
    // Останавливаем отслеживание при уничтожении виджета
    _onlineTracker.stopTracking();
    _appActivityTimer?.cancel();

    // Отправляем финальный статус
    _onlineTracker.sendManualStatus(
        activityType: 'app_disposed',
        customDetails: {
          'dispose_time': DateTime.now().toIso8601String(),
          'total_session_duration': DateTime.now().difference(_lastUserActivity).inSeconds,
        }
    );
  }

  // Метод для показа диалога обновлений при запуске
  void _showPendingUpdateDialog() {
    final pendingUpdate = UpdateManager.getPendingUpdate();
    print('🔄 _showPendingUpdateDialog вызван');
    print('📊 pendingUpdate: $pendingUpdate');

    // Всегда показываем диалог, даже если нет обновления
    final updateInfo = pendingUpdate ?? {
      'update_available': false,
      'current_version': appVersion,
      'latest_version': appVersion,
    };

    // Добавляем небольшую задержку, чтобы приложение успело отрисоваться
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_scaffoldKey.currentContext != null) {
        print('🎯 Показываем UpdateDialog с данными: $updateInfo');
        showDialog(
          context: _scaffoldKey.currentContext!,
          barrierDismissible: false,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        ).then((_) {
          // Очищаем информацию об ожидающем обновлении после показа диалога
          UpdateManager.clearPendingUpdate();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Слушаем клики мыши для отслеживания активности
    return Listener(
      onPointerDown: (_) => _updateUserActivity(),
      child: RawKeyboardListener(
        focusNode: _focusNode,
        onKey: _handleKeyEvent,
        child: MaterialApp(
          theme: buildLightTheme(),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            key: _scaffoldKey,
            backgroundColor: Theme.of(context).colorScheme.background,
            body: Row(
              children: [
                LeftSideBar(
                  onMenuPressed: _showMenu,
                  onSettingsPressed: _showSettings,
                  onApiPressed: _showApiDialog,
                  onLogsPressed: _showLogs,
                  onDatabasePressed: _showDatabase,
                  onCostPressed: _showCostDialog,
                ),
                MainContent(
                  currentIndex: _currentBottomIndex,
                  browserManager: widget.browserManager,
                ),
              ],
            ),
            bottomNavigationBar: BottomNavBar(
              currentIndex: _currentBottomIndex,
              onIndexChanged: (index) {
                setState(() {
                  if (index != 6) {
                    _previousBottomIndex = _currentBottomIndex;
                  }
                  _currentBottomIndex = index;
                });
                _updateUserActivity();
              },
            ),
          ),
        ),
      ),
    );
  }

  void _showMenu() {
    _updateUserActivity();
    showDialog(
      context: _scaffoldKey.currentContext!,
      builder: (context) => MenuDialog(),
    );
  }

  void _showSettings() {
    _updateUserActivity();
    showGeneralDialog(
      context: _scaffoldKey.currentContext!,
      barrierDismissible: true,          // закрытие по клику вне панели
      barrierLabel: 'Закрыть настройки',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 1000,                   // ширина выезжающей панели
            height: double.infinity,
            child: const SettingsScreen(),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(-1.0, 0.0); // начальная позиция – левее экрана
        const end = Offset.zero;          // конечная – в видимой области
        final tween = Tween(begin: begin, end: end);
        final offsetAnimation = animation.drive(tween);
        return SlideTransition(
          position: offsetAnimation,
          child: child,
        );
      },
    );
  }

  void _showApiDialog() {
    _updateUserActivity();
    showDialog(
      context: _scaffoldKey.currentContext!,
      builder: (context) => ApiDialog(),
    );
  }

  void _showLogs() {
    _updateUserActivity();
    Navigator.of(_scaffoldKey.currentContext!).push(
      MaterialPageRoute(builder: (context) => LogsScreen()),
    );
  }

  void _showDatabase() {
    _updateUserActivity();
    Navigator.of(_scaffoldKey.currentContext!).push(
      MaterialPageRoute(builder: (context) => DatabaseScreen()),
    );
  }

  void _showCostDialog() {
    _updateUserActivity();
    showDialog(
      context: _scaffoldKey.currentContext!,
      builder: (context) => CostDialog(),
    );
  }
}