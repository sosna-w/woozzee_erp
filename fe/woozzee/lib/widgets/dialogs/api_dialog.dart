// api_dialog.dart
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../utils/token_manager.dart';
import '../../utils/private_token_manager.dart';

class ApiDialog extends StatefulWidget {
  @override
  _ApiDialogState createState() => _ApiDialogState();
}

class _ApiDialogState extends State<ApiDialog> {
  final TextEditingController _tokenController = TextEditingController();
  bool _isLoading = false;
  bool _tokenExists = false;

  // Контроллеры для приватных ключей
  final TextEditingController _authorizeV3Controller = TextEditingController();
  final TextEditingController _wbSellerLkController = TextEditingController();
  final TextEditingController _cookieController = TextEditingController();
  bool _privateKeysExist = false;
  bool _isLoadingPrivateKeys = false;

  // Флаги для показа/скрытия
  bool _showToken = false;
  bool _showAuthorizeV3 = false;
  bool _showWbSellerLk = false;
  bool _showCookie = false;

  Map<String, dynamic> _serviceStatus = {};
  Map<String, String> _serviceUrls = {
    'Контент': 'https://content-api.wildberries.ru/ping',
    'Аналитика': 'https://seller-analytics-api.wildberries.ru/ping',
    'Цены и скидки': 'https://discounts-prices-api.wildberries.ru/ping',
    'Маркетплейс': 'https://marketplace-api.wildberries.ru/ping',
    'Статистика': 'https://statistics-api.wildberries.ru/ping',
    'Продвижение': 'https://advert-api.wildberries.ru/ping',
    'Вопросы и отзывы': 'https://feedbacks-api.wildberries.ru/ping',
    'Чат с покупателями': 'https://buyer-chat-api.wildberries.ru/ping',
    'Поставки': 'https://supplies-api.wildberries.ru/ping',
    'Возвраты': 'https://returns-api.wildberries.ru/ping',
    'Документы': 'https://documents-api.wildberries.ru/ping',
    'Финансы': 'https://finance-api.wildberries.ru/ping',
    'Общее': 'https://common-api.wildberries.ru/ping',
  };

  final TokenManager _tokenManager = TokenManager();
  final PrivateTokenManager _privateTokenManager = PrivateTokenManager();

  @override
  void initState() {
    super.initState();
    _loadTokenFromManager();
    _loadPrivateKeysFromServer(); // ← загружаем с сервера
    _loadServiceStatus();
  }

  Future<void> _loadTokenFromManager() async {
    final token = _tokenManager.token;
    if (token != null && token.isNotEmpty) {
      setState(() {
        _tokenController.text = token;
        _tokenExists = true;
      });
    } else {
      await _checkTokenOnServer();
    }
  }

  Future<void> _loadPrivateKeysFromServer() async {
    setState(() => _isLoadingPrivateKeys = true);
    try {
      // Сначала загружаем с сервера (синхронизируем локальный менеджер)
      await _privateTokenManager.loadFromServer();
      final auth = _privateTokenManager.authorizeV3;
      final wb = _privateTokenManager.wbSellerLk;
      final ck = _privateTokenManager.cookie;

      final hasAny = (auth != null && auth.isNotEmpty) ||
          (wb != null && wb.isNotEmpty) ||
          (ck != null && ck.isNotEmpty);

      setState(() {
        _authorizeV3Controller.text = auth ?? '';
        _wbSellerLkController.text = wb ?? '';
        _cookieController.text = ck ?? '';
        _privateKeysExist = hasAny;
      });
    } catch (e) {
      print('⚠️ Ошибка загрузки приватных ключей: $e');
    } finally {
      setState(() => _isLoadingPrivateKeys = false);
    }
  }

  Future<void> _checkTokenOnServer() async {
    try {
      final response = await http.get(Uri.parse('https://hide_domain.com/token/exists'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() => _tokenExists = data['exists']);
        if (_tokenExists) await _getTokenFromServer();
      }
    } catch (e) {
      print('⚠️ Ошибка проверки токена на сервере: $e');
    }
  }

  Future<void> _getTokenFromServer() async {
    try {
      final response = await http.get(Uri.parse('https://hide_domain.com/token'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['token_value'] ?? '';
        if (token.isNotEmpty) {
          await _tokenManager.saveToken(token);
          setState(() {
            _tokenController.text = token;
            _tokenExists = true;
          });
        }
      }
    } catch (e) {
      print('⚠️ Ошибка получения токена с сервера: $e');
    }
  }

  Future<void> _saveToken() async {
    if (_tokenController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final success = await _tokenManager.saveToken(_tokenController.text);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Токен сохранён'), backgroundColor: Colors.green),
        );
        setState(() => _tokenExists = true);
        _loadServiceStatus();
      } else {
        throw Exception('Не удалось сохранить токен');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _savePrivateKeys() async {
    final authorizeV3 = _authorizeV3Controller.text.trim();
    final wbSellerLk = _wbSellerLkController.text.trim();
    final cookie = _cookieController.text.trim();

    if (authorizeV3.isEmpty || wbSellerLk.isEmpty || cookie.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Все три поля должны быть заполнены'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoadingPrivateKeys = true);
    try {
      await _privateTokenManager.saveToServer(authorizeV3, wbSellerLk, cookie);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Приватные данные сохранены'), backgroundColor: Colors.green),
      );
      setState(() => _privateKeysExist = true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoadingPrivateKeys = false);
    }
  }

  Future<void> _clearPrivateKeys() async {
    setState(() => _isLoadingPrivateKeys = true);
    try {
      await _privateTokenManager.clearOnServer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Приватные данные очищены'), backgroundColor: Colors.orange),
      );
      setState(() {
        _authorizeV3Controller.clear();
        _wbSellerLkController.clear();
        _cookieController.clear();
        _privateKeysExist = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка очистки: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoadingPrivateKeys = false);
    }
  }

  Future<void> _loadServiceStatus() async {
    if (!_tokenExists) return;
    setState(() => _serviceStatus = {});
    final token = _tokenManager.token;
    if (token == null || token.isEmpty) return;

    for (final entry in _serviceUrls.entries) {
      final serviceName = entry.key;
      final url = entry.value;
      if (!mounted) return;
      setState(() => _serviceStatus[serviceName] = 'checking');
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: {'Authorization': token},
        ).timeout(const Duration(seconds: 5));
        if (!mounted) return;
        setState(() {
          if (response.statusCode == 200) _serviceStatus[serviceName] = 'available';
          else if (response.statusCode == 401) _serviceStatus[serviceName] = 'unauthorized';
          else if (response.statusCode == 429) _serviceStatus[serviceName] = 'rate_limit';
          else _serviceStatus[serviceName] = 'error';
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _serviceStatus[serviceName] = 'error');
      }
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'available': return 'Доступен';
      case 'unauthorized': return 'Не авторизован';
      case 'rate_limit': return 'Лимит запросов';
      case 'checking': return 'Проверка...';
      case 'error': return 'Ошибка';
      default: return 'Не проверен';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'available': return Colors.green;
      case 'unauthorized': return Colors.orange;
      case 'rate_limit': return Colors.yellow[700]!;
      case 'checking': return Colors.blue;
      case 'error': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('API Настройки', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
      backgroundColor: Theme.of(context).colorScheme.surface,
      content: SingleChildScrollView(
        child: Container(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ----- Публичный токен -----
              Text('Публичный API токен Wildberries:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tokenController,
                      decoration: InputDecoration(
                        hintText: 'Введите ваш API токен',
                        border: OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _showToken = !_showToken),
                        ),
                      ),
                      obscureText: !_showToken,
                    ),
                  ),
                  SizedBox(width: 8),
                  _isLoading
                      ? CircularProgressIndicator()
                      : ElevatedButton(onPressed: _saveToken, child: Text('Сохранить')),
                ],
              ),
              SizedBox(height: 16),

              if (_tokenExists) ...[
                Text('Статус публичных сервисов:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Container(
                  height: 200,
                  child: ListView(
                    children: _serviceUrls.keys.map((service) {
                      final status = _serviceStatus[service] ?? 'not_checked';
                      return ListTile(
                        leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: _getStatusColor(status), shape: BoxShape.circle)),
                        title: Text(service),
                        trailing: Text(_getStatusText(status), style: TextStyle(color: _getStatusColor(status))),
                      );
                    }).toList(),
                  ),
                ),
                Center(child: TextButton(onPressed: _loadServiceStatus, child: Text('Обновить статус'))),
              ],

              SizedBox(height: 24),
              Divider(),
              SizedBox(height: 16),

              // ----- Приватные ключи -----
              Text('Приватные ключи для автоакций:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),

              // authorizev3
              Text('Authorizev3:', style: TextStyle(fontWeight: FontWeight.w500)),
              SizedBox(height: 4),
              TextField(
                controller: _authorizeV3Controller,
                decoration: InputDecoration(
                  hintText: 'Введите authorizev3 ключ',
                  border: OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_showAuthorizeV3 ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showAuthorizeV3 = !_showAuthorizeV3),
                  ),
                ),
                obscureText: !_showAuthorizeV3,
              ),
              SizedBox(height: 12),

              // wb-seller-lk
              Text('wb-seller-lk:', style: TextStyle(fontWeight: FontWeight.w500)),
              SizedBox(height: 4),
              TextField(
                controller: _wbSellerLkController,
                decoration: InputDecoration(
                  hintText: 'Введите wb-seller-lk ключ',
                  border: OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_showWbSellerLk ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showWbSellerLk = !_showWbSellerLk),
                  ),
                ),
                obscureText: !_showWbSellerLk,
              ),
              SizedBox(height: 12),

              // cookie
              Text('Cookie:', style: TextStyle(fontWeight: FontWeight.w500)),
              SizedBox(height: 4),
              TextField(
                controller: _cookieController,
                decoration: InputDecoration(
                  hintText: 'Введите cookie',
                  border: OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_showCookie ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showCookie = !_showCookie),
                  ),
                ),
                obscureText: !_showCookie,
              ),
              SizedBox(height: 16),

              Row(
                children: [
                  if (_privateKeysExist)
                    OutlinedButton(
                      onPressed: _clearPrivateKeys,
                      child: Text('Очистить'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _isLoadingPrivateKeys
                        ? CircularProgressIndicator()
                        : ElevatedButton(
                      onPressed: _savePrivateKeys,
                      child: Text(_privateKeysExist ? 'Обновить данные' : 'Сохранить данные'),
                    ),
                  ),
                ],
              ),

              if (_privateKeysExist) ...[
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Expanded(child: Text('Приватные данные сохранены. Автоакции доступны.', style: TextStyle(color: Colors.green[800]))),
                    ],
                  ),
                ),
              ],

              SizedBox(height: 8),
              Text(
                '⚠️ Приватные данные хранятся на сервере и локально на вашем устройстве.',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Закрыть', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        ),
      ],
    );
  }
}