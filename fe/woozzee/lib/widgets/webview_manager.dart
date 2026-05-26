// webview_manager.dart
import 'package:flutter/material.dart'; // ДОБАВЬТЕ ЭТОТ ИМПОРТ
import 'package:webview_windows/webview_windows.dart';

class WebViewManager {
  final WebviewController _controller = WebviewController();
  bool _isInitialized = false;

  Future<WebviewController> get controller async {
    if (!_isInitialized) {
      await _initializeController();
    }
    return _controller;
  }

  Future<void> _initializeController() async {
    try {
      await _controller.initialize();
      // Настройка базовых параметров WebView
      await _controller.setBackgroundColor(Colors.white); // Теперь Colors доступен
      _isInitialized = true;
      print('WebView controller initialized successfully');
    } catch (e) {
      print('WebView controller initialization error: $e');
      rethrow;
    }
  }

  Future<void> loadUrl(String url) async {
    final webviewController = await controller;
    try {
      await webviewController.loadUrl(url);
      print('URL loaded successfully: $url');
    } catch (e) {
      print('Error loading URL $url: $e');
      rethrow;
    }
  }
}