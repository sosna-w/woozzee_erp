// update_dialog.dart
import 'package:flutter/material.dart';
import '../../utils/update_manager.dart';
import './version_history_dialog.dart';

class UpdateDialog extends StatefulWidget {
  final Map<String, dynamic> updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  void _showVersionHistory() {
    showDialog(
      context: context,
      builder: (context) => const VersionHistoryDialog(),
    );
  }

  Future<void> _downloadUpdate() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      final updateManager = UpdateManager();
      final filename = widget.updateInfo['filename'];

      // Реальный прогресс через callback
      await updateManager.downloadUpdateWithProgress(
        context,
        filename,
            (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Ошибка'),
            content: Text('Не удалось скачать обновление: $e'),
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
    final updateInfo = widget.updateInfo;
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width > 600 ? 500.0 : screenSize.width * 0.85;

    // Проверяем, есть ли доступное обновление
    final bool hasUpdate = updateInfo['current_version'] != updateInfo['latest_version'];

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: screenSize.height * 0.7,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasUpdate ? Icons.system_update : Icons.check_circle,
                      color: hasUpdate ? Colors.blue : Colors.green,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasUpdate ? 'Доступно обновление' : 'Обновлений нет',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasUpdate
                                ? '${updateInfo['current_version']} → ${updateInfo['latest_version']}'
                                : 'У вас установлена последняя версия приложения (${updateInfo['current_version']}).',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Контент (показываем только если есть обновление)
              if (hasUpdate) ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        updateInfo['title'] ?? 'Новая версия',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Описание с прокруткой
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(
                          maxHeight: 150, // Ограничиваем высоту описания
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            updateInfo['description'] ?? '',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Прогресс загрузки
                      if (_isDownloading) ...[
                        const Text(
                          'Скачивание обновления...',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: _downloadProgress,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              // Кнопки
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!_isDownloading) ...[
                      // Кнопка "История версий" - всегда доступна
                      TextButton(
                        onPressed: _showVersionHistory,
                        child: const Text('ИСТОРИЯ ВЕРСИЙ'),
                      ),

                      const SizedBox(width: 8),

                      // Показываем кнопки в зависимости от наличия обновления
                      if (hasUpdate) ...[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('ПОЗЖЕ'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _downloadUpdate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('ОБНОВИТЬ'),
                        ),
                      ] else ...[
                        // Если нет обновления, показываем кнопку ОК
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('OK'),
                        ),
                      ],
                    ] else ...[
                      // Показываем прогресс во время загрузки
                      Expanded(
                        child: Text(
                          'Загрузка... ${(_downloadProgress * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}