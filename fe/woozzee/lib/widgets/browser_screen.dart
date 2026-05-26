// browser_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Добавьте этот импорт
import 'package:webview_windows/webview_windows.dart';
import 'global_browser_manager.dart';

class BrowserScreen extends StatefulWidget {
  final GlobalBrowserManager browserManager;
  
  const BrowserScreen({super.key, required this.browserManager});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final _textController = TextEditingController();
  bool _isLoading = false;
  bool _isWebViewReady = false;
  String? _errorMessage;
  final FocusNode _focusNode = FocusNode(); // Добавлено: для обработки клавиш

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus(); // Фокус для обработки клавиш
    _initializeWebView();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Добавлено: обработка нажатия клавиш
  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      // Проверяем, нажата ли клавиша Alt (левый или правый)
      if (event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.space) {
        // Переключение обратно на предыдущую вкладку обрабатывается в родительском виджете
        // Здесь мы просто позволяем событию всплывать
      }
    }
  }

  void _initializeWebView() async {
    try {
      if (!widget.browserManager.isInitialized) {
        await widget.browserManager.initialize();
      }
      
      setState(() {
        _isWebViewReady = true;
      });
      _textController.text = 'https://seller.wildberries.ru/';
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка инициализации браузера: $e';
      });
      print('Browser initialization error: $e');
    }
  }

  Future<void> _loadUrl(String url) async {
    if (url.isEmpty) return;
    
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      
      // Добавляем схему если отсутствует
      final formattedUrl = url.startsWith('http') ? url : 'https://$url';
      await widget.browserManager.webViewManager.loadUrl(formattedUrl);
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ошибка загрузки URL: $e';
      });
      print('Error loading URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _textController,
            decoration: const InputDecoration(
              hintText: 'Введите URL...',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8.0),
            ),
            onSubmitted: _loadUrl,
          ),
          actions: [
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                if (_textController.text.isNotEmpty) {
                  _loadUrl(_textController.text);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.home),
              onPressed: () {
                _textController.text = 'https://seller.wildberries.ru/';
                _loadUrl('https://seller.wildberries.ru/');
              },
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeWebView,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (!_isWebViewReady) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Инициализация браузера...'),
          ],
        ),
      );
    }

    return FutureBuilder<WebviewController>(
      future: widget.browserManager.webViewManager.controller,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Ошибка WebView: ${snapshot.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _initializeWebView,
                  child: const Text('Повторить'),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: Text('WebView не доступен'));
        }

        return Stack(
          children: [
            Webview(
              snapshot.data!,
              permissionRequested: _onPermissionRequested,
            ),
            if (_isLoading)
              const LinearProgressIndicator(),
          ],
        );
      },
    );
  }

  Future<WebviewPermissionDecision> _onPermissionRequested(
      String url, WebviewPermissionKind kind, bool isUserInitiated) async {
    return WebviewPermissionDecision.allow;
  }
}