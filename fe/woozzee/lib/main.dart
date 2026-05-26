// main.dart - ОБНОВЛЕННАЯ ВЕРСИЯ С DUCKDB
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import '../app/business_analytics_app.dart';
import '../utils/token_manager.dart';
import '../utils/private_token_manager.dart';
import 'widgets/global_browser_manager.dart';
import '../utils/product_manager.dart';
import '../models/unified_products_data_model.dart';
import '../utils/update_manager.dart';
import '../utils/online_tracker.dart';
import '../providers/reports_sync_provider.dart';
import '../services/database_service.dart'; // Импортируем DatabaseService
import 'package:intl/date_symbol_data_local.dart';
import '../utils/sales_funnel_manager.dart';
import '../utils/news_manager.dart';
import '../utils/rbc_news_manager.dart';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация window_manager
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = WindowOptions(
    size: const Size(5000, 2000),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    minimumSize: const Size(800, 600),
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.maximize();
    await windowManager.focus();

  });

  // ИНИЦИАЛИЗАЦИЯ БАЗЫ ДАННЫХ DUCKDB
  final dbService = DatabaseService();
  await dbService.init();

  // ИНИЦИАЛИЗАЦИЯ МЕНЕДЖЕРА ПУБЛИЧНЫХ ТОКЕНОВ
  await TokenManager().initialize();

  // ИНИЦИАЛИЗАЦИЯ МЕНЕДЖЕРА ПРИВАТНЫХ КЛЮЧЕЙ
  await PrivateTokenManager().initialize();
  await PrivateTokenManager().loadFromServer();

  // Инициализация глобального менеджера браузера
  final browserManager = GlobalBrowserManager();
  await browserManager.initialize();

  // ИНИЦИАЛИЗАЦИЯ МЕНЕДЖЕРА ТОВАРОВ
  await ProductManager().initialize();

  // ИНИЦИАЛИЗАЦИЯ МОДЕЛИ ДАННЫХ ДЛЯ ВИДЖЕТОВ
  await UnifiedProductsDataModel().initialize();

  await SalesFunnelManager().initialize();

  await NewsManager().initialize();

  await RbcNewsManager().initialize();

  HttpOverrides.global = MyHttpOverrides();

  // ИНИЦИАЛИЗАЦИЯ ONLINE ТРЕКЕРА
  final onlineTracker = OnlineTracker();
  await onlineTracker.initialize();

  // НАЧАТЬ ОТСЛЕЖИВАНИЕ ОНЛАЙН-СТАТУСА
  onlineTracker.startTracking();

  // Автоматическая проверка обновлений при запуске
  await _checkForUpdatesOnStart();

  await initializeDateFormatting('ru_RU', null);

  runApp(
    // ОБЕРТЫВАЕМ ПРИЛОЖЕНИЕ В PROVIDER ДЛЯ УПРАВЛЕНИЯ СОСТОЯНИЕМ ОТЧЕТОВ
    ChangeNotifierProvider(
      create: (context) => ReportsSyncProvider(dbService),
      child: BusinessAnalyticsApp(browserManager: browserManager),
    ),
  );
}

Future<void> _checkForUpdatesOnStart() async {
  try {
    final updateManager = UpdateManager();
    final updateInfo = await updateManager.checkForUpdates();

    if (updateInfo['update_available'] == true) {
      print('Доступно обновление: ${updateInfo['latest_version']}');
    } else {
      print('Установлена последняя версия');
    }
  } catch (e) {
    print('Ошибка при проверке обновлений: $e');
  }
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return client;
  }
}