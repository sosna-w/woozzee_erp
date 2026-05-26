// left_sidebar.dart - ДОБАВЛЕН СЧЁТЧИК ОШИБОК ЗА 24 ЧАСА НА КНОПКУ ЛОГОВ
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';
import '../utils/update_manager.dart';
import '../widgets/dialogs/update_dialog.dart';

class LeftSideBar extends StatefulWidget {
  final VoidCallback onMenuPressed;
  final VoidCallback onSettingsPressed;
  final VoidCallback onApiPressed;
  final VoidCallback onLogsPressed;
  final VoidCallback onDatabasePressed;
  final VoidCallback onCostPressed;

  const LeftSideBar({
    super.key,
    required this.onMenuPressed,
    required this.onSettingsPressed,
    required this.onApiPressed,
    required this.onLogsPressed,
    required this.onDatabasePressed,
    required this.onCostPressed,
  });

  @override
  State<LeftSideBar> createState() => _LeftSideBarState();
}

class _LeftSideBarState extends State<LeftSideBar> {
  bool _hasUpdate = false;
  int _errorCount24h = 0;
  Timer? _errorRefreshTimer;

  @override
  void initState() {
    super.initState();
    _hasUpdate = UpdateManager.hasPendingUpdate();
    _fetchErrorCount(); // первый запрос
    // обновляем счётчик каждые 5 минут
    _errorRefreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _fetchErrorCount();
    });
  }

  @override
  void dispose() {
    _errorRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _closeApp() async {
    await windowManager.close();
  }

  Future<void> _toggleWindowMode() async {
    final isFullScreen = await windowManager.isFullScreen();

    if (!isFullScreen) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await Future.delayed(const Duration(milliseconds: 50));
      await windowManager.setFullScreen(true);
    } else {
      await windowManager.setFullScreen(false);
      await Future.delayed(const Duration(milliseconds: 50));
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      await windowManager.setSize(const Size(1800, 1000));
      await windowManager.center();
      await windowManager.setMinimizable(true);
      await windowManager.setMaximizable(true);
      await windowManager.setClosable(true);
      await windowManager.show();
    }
  }

  /// Запрашивает логи ошибок и считает количество за последние 24 часа
  Future<void> _fetchErrorCount() async {
    try {
      final response = await http.get(
        Uri.parse('https://hide_domain.com/logs?level=ERROR'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        if (mounted) setState(() => _errorCount24h = 0);
        return;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final List logs = data['logs'] as List? ?? [];
      final now = DateTime.now();
      final twentyFourHoursAgo = now.subtract(const Duration(hours: 24));

      int count = 0;
      for (final log in logs) {
        final timestampStr = log['timestamp'] as String?;
        if (timestampStr == null) continue;
        final timestamp = DateTime.tryParse(timestampStr);
        if (timestamp != null && timestamp.isAfter(twentyFourHoursAgo)) {
          count++;
        }
      }

      if (mounted) setState(() => _errorCount24h = count);
    } catch (e) {
      // при ошибке запроса просто показываем 0 (или оставляем предыдущее значение)
      if (mounted) setState(() => _errorCount24h = 0);
    }
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    try {
      final updateManager = UpdateManager();
      final updateInfo = await updateManager.checkForUpdates();

      setState(() {
        _hasUpdate = updateInfo['update_available'] == true;
      });

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        ).then((_) {
          setState(() {
            _hasUpdate = UpdateManager.hasPendingUpdate();
          });
        });
      }
    } catch (e) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Ошибка'),
            content: Text('Не удалось проверить обновления: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          _buildLeftBarButton(
            icon: Icons.menu,
            tooltip: 'Меню',
            onPressed: widget.onMenuPressed,
          ),
          _buildLeftBarButton(
            icon: Icons.storage,
            tooltip: 'Базы данных',
            onPressed: widget.onDatabasePressed,
          ),
          _buildLeftBarButton(
            icon: Icons.currency_ruble,
            tooltip: 'Себестоимость',
            onPressed: widget.onCostPressed,
          ),
          _buildLeftBarButton(
            icon: Icons.settings_outlined,
            tooltip: 'Настройки',
            onPressed: widget.onSettingsPressed,
          ),
          _buildLeftBarButton(
            icon: Icons.api_outlined,
            tooltip: 'API',
            onPressed: widget.onApiPressed,
          ),
          // Кнопка логов с бейджем количества ошибок
          _buildLogsButton(),
          const Spacer(),
          _buildUpdateButton(context),
          _buildLeftBarButton(
            icon: Icons.fullscreen,
            tooltip: 'Переключить полноэкранный режим',
            onPressed: _toggleWindowMode,
          ),
          _buildLeftBarButton(
            icon: Icons.power_settings_new,
            tooltip: 'Закрыть программу',
            onPressed: _closeApp,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Отдельная кнопка для логов с числовым бейджем
  Widget _buildLogsButton() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildLeftBarButton(
          icon: Icons.list_alt_outlined,
          tooltip: 'Логи',
          onPressed: widget.onLogsPressed,
        ),
        if (_errorCount24h > 0)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(2),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _errorCount24h > 99 ? '99+' : '$_errorCount24h',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildUpdateButton(BuildContext context) {
    return Stack(
      children: [
        _buildLeftBarButton(
          icon: _hasUpdate ? Icons.system_update_alt : Icons.system_update,
          tooltip: 'Проверить обновления',
          onPressed: () => _checkForUpdates(context),
        ),
        if (_hasUpdate)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLeftBarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}