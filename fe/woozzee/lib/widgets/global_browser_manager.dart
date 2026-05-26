// global_browser_manager.dart
import 'package:webview_windows/webview_windows.dart';
import 'webview_manager.dart';

class GlobalBrowserManager {
  static final GlobalBrowserManager _instance = GlobalBrowserManager._internal();
  factory GlobalBrowserManager() => _instance;
  GlobalBrowserManager._internal();

  final WebViewManager _webViewManager = WebViewManager();
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (!_isInitialized) {
      try {
        // Сначала инициализируем контроллер
        await _webViewManager.controller;
        
        // Затем загружаем URL
        await _webViewManager.loadUrl('https://seller.wildberries.ru/');
        
        _isInitialized = true;
        print('Global browser manager initialized successfully');
      } catch (e) {
        print('Global browser manager initialization error: $e');
        // Не повторяем бесконечно, лучше показать ошибку пользователю
        throw Exception('Failed to initialize browser: $e');
      }
    }
  }

  WebViewManager get webViewManager => _webViewManager;
  bool get isInitialized => _isInitialized;
}