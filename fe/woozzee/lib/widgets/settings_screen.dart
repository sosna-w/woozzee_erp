import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import '../utils/photo_cache_manager.dart';
import 'tag_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedSection = 0;
  double _intervalValue = 15.0;
  String _modeValue = 'uniform';
  String _warehouseMode = 'Один как все';
  bool _autoReplenishmentEnabled = false;

  List<dynamic> _warehouses = [];
  List<dynamic> _tags = [];
  Map<String, dynamic> _warehouseConfig = {};
  Map<String, dynamic> _individualConfigs = {};
  Map<String, dynamic> _tagConfigs = {};
  bool _isLoading = false;
  bool _isLoadingWarehouses = false;
  bool _isLoadingTags = false;
  bool _isLoadingAutoConfig = false;

  @override
  void initState() {
    super.initState();
    _loadWarehouseConfig();
    _loadWarehouses();
    _loadTags();
    _loadTagConfig();
    _loadAutoReplenishmentConfig();
  }

  Future<void> _loadAutoReplenishmentConfig() async {
    if (!mounted) return;

    setState(() {
      _isLoadingAutoConfig = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://hide_domain.com/auto-replenishment-config'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final config = json.decode(response.body);
        if (mounted) {
          setState(() {
            _autoReplenishmentEnabled = config['enabled'] ?? false;
            _intervalValue = (config['interval_minutes'] ?? 15).toDouble();
          });
        }
      }
    } catch (e) {
      _showErrorSnackbar('Ошибка загрузки конфигурации автообновления: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAutoConfig = false;
        });
      }
    }
  }

  Future<void> _saveAutoReplenishmentConfig() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final config = {
        'enabled': _autoReplenishmentEnabled,
        'interval_minutes': _intervalValue.round(),
        'batch_size': 100,
      };

      final response = await http.post(
        Uri.parse('https://hide_domain.com/auto-replenishment-config'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(config),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _showSuccessSnackbar('Настройки автообновления сохранены');
        _loadAutoReplenishmentConfig();
      } else {
        _showErrorSnackbar('Ошибка сохранения автообновления: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackbar('Ошибка подключения: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildFinancialReportSettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // можно оставить, чтобы колонка не растягивалась
          children: [
            Text(
              'Экран цен',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),

            FutureBuilder<bool?>(
              future: _loadHideCartSetting(),
              builder: (context, snapshot) {
                final hideCart = snapshot.data ?? true;
                return SwitchListTile(
                  title: const Text('Скрыть товары в Корзине'),
                  value: hideCart,
                  onChanged: (value) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('hideCartProducts', value);
                    setState(() {});
                    _showSuccessSnackbar('Настройка сохранена');
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _loadHideCartSetting() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hideCartProducts');
  }

  Future<void> _loadWarehouses() async {
    if (!mounted) return;

    setState(() {
      _isLoadingWarehouses = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://hide_domain.com/warehouses'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _warehouses = json.decode(response.body);
          });
        }
      } else {
        _showErrorSnackbar('Ошибка загрузки складов: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackbar('Ошибка подключения: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingWarehouses = false;
        });
      }
    }
  }

  Future<void> _loadTags() async {
    if (!mounted) return;

    setState(() {
      _isLoadingTags = true;
    });

    try {
      // Используем общий менеджер тегов
      await TagManager().loadTags();
      if (mounted) {
        setState(() {
          _tags = TagManager().tags.map((name) => {'name': name}).toList();
        });
      }
    } catch (e) {
      _showErrorSnackbar('Ошибка загрузки тегов: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTags = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _getCacheInfoWithInit() async {
    await PhotoCacheManager().initialize();
    return PhotoCacheManager().getCacheInfo();
  }

  List<String> getTagNames() {
    return _tags.map<String>((tag) => tag['name']?.toString() ?? '').where((name) => name.isNotEmpty).toList();
  }

  Future<void> _loadWarehouseConfig() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://hide_domain.com/warehouse-config'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final config = json.decode(response.body);
        if (mounted) {
          setState(() {
            _warehouseConfig = config;
            _modeValue = config['mode'] ?? 'uniform';
            _warehouseMode = _modeValue == 'uniform' ? 'Один как все' : 'Индивидуально';
            _individualConfigs = config['individual_config'] ?? {};
          });
        }
      }
    } catch (e) {
      _showErrorSnackbar('Ошибка загрузки конфигурации: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTagConfig() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://hide_domain.com/tag-config'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final config = json.decode(response.body);
        if (mounted) {
          setState(() {
            _tagConfigs = config;
          });
        }
      }
    } catch (e) {
      _showErrorSnackbar('Ошибка загрузки конфигурации тегов: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveWarehouseConfig() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final config = {
        'mode': _modeValue,
        'uniform_threshold': _warehouseConfig['uniform_threshold'] ?? 0,
        'uniform_minimum': _warehouseConfig['uniform_minimum'] ?? 0,
        'individual_config': _individualConfigs,
      };

      final response = await http.post(
        Uri.parse('https://hide_domain.com/warehouse-config'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(config),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _showSuccessSnackbar('Конфигурация складов сохранена');
        _loadWarehouseConfig();
      } else {
        _showErrorSnackbar('Ошибка сохранения: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackbar('Ошибка подключения: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveTagConfig() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('https://hide_domain.com/tag-config'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(_tagConfigs),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _showSuccessSnackbar('Конфигурация тегов сохранена');
        _loadTagConfig();
      } else {
        _showErrorSnackbar('Ошибка сохранения тегов: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackbar('Ошибка подключения: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSuccessSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _updateIndividualConfig(int warehouseId, String key, dynamic value) {
    setState(() {
      final warehouseKey = warehouseId.toString();
      if (!_individualConfigs.containsKey(warehouseKey)) {
        _individualConfigs[warehouseKey] = {};
      }
      _individualConfigs[warehouseKey][key] = value;
    });
  }

  void _updateTagConfig(String tagName, String key, dynamic value) {
    setState(() {
      if (!_tagConfigs.containsKey(tagName)) {
        _tagConfigs[tagName] = {};
      }
      _tagConfigs[tagName][key] = value;
    });
  }

  String _getBehaviorDescription(String behavior) {
    switch (behavior) {
      case 'as_warehouse':
        return 'Товары с этим тегом будут использовать настройки склада (порог FBO и минимум FBS)';
      case 'always_zero':
        return 'Товары с этим тегом всегда будут иметь 0 остатков на FBS';
      case 'ignore':
        return 'Товары с этим тегом будут игнорироваться при автообновлении остатков';
      case 'always_n':
        return 'Товары с этим тегом всегда будут иметь фиксированное количество остатков';
      default:
        return '';
    }
  }

  Widget _buildMenuButton(BuildContext context, String title, IconData icon, int index) {
    final isSelected = _selectedSection == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: TextButton(
        onPressed: () {
          setState(() {
            _selectedSection = index;
          });
        },
        style: TextButton.styleFrom(
          foregroundColor: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          backgroundColor: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (_selectedSection) {
      case 0: // Остатки
        return _buildStockSettings();
      case 1: // Теги
        return _buildTagSettings();
      case 2: // Фото
        return _buildPhotoSettings();
      case 3: // Финансовый отчет
        return _buildFinancialReportSettings();
      default:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.settings_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Настройки',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Раздел настроек в разработке',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildPhotoSettings() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getCacheInfoWithInit(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Ошибка загрузки информации о кэше',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() {});
                  },
                  child: const Text('Повторить'),
                ),
              ],
            ),
          );
        }

        final cacheInfo = snapshot.data ?? {};
        final totalFiles = cacheInfo['totalFiles'] ?? 0;
        final totalSize = cacheInfo['totalSize'] ?? 0;
        final cacheStats = cacheInfo['cacheStats'] ?? {};
        final cachePath = cacheInfo['cachePath'] ?? '';

        final double totalSizeMB = totalSize / (1024 * 1024);
        final int uniqueProducts = cacheStats.keys.length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Кэш фотографий',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),

              const SizedBox(height: 16),
              Text(
                'Управление кэшированными фотографиями товаров',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),

              const SizedBox(height: 32),

              // Статистика кэша
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.photo_library),
                      title: const Text('Всего фото в кэше'),
                      subtitle: Text('$totalFiles файлов'),
                      trailing: Chip(
                        label: Text('$totalFiles'),
                        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      ),
                    ),

                    ListTile(
                      leading: const Icon(Icons.storage),
                      title: const Text('Занято места'),
                      subtitle: Text('${totalSizeMB.toStringAsFixed(2)} МБ'),
                      trailing: Chip(
                        label: Text('${totalSizeMB.toStringAsFixed(1)} МБ'),
                        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      ),
                    ),

                    ListTile(
                      leading: const Icon(Icons.inventory_2),
                      title: const Text('Уникальных товаров'),
                      subtitle: Text('$uniqueProducts товаров'),
                      trailing: Chip(
                        label: Text('$uniqueProducts'),
                        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      ),
                    ),

                    ListTile(
                      leading: const Icon(Icons.folder_open),
                      title: const Text('Папка кэша'),
                      subtitle: Text(
                        cachePath,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Детальная статистика по товарам
              if (uniqueProducts > 0) ...[
                Text(
                  'Детальная статистика',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 16),

                Container(
                  height: 300,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    itemCount: cacheStats.keys.length,
                    itemBuilder: (context, index) {
                      final nmId = cacheStats.keys.elementAt(index);
                      final productStats = cacheStats[nmId];
                      final photoCount = productStats?['photoCount'] ?? 0;
                      final productSize = productStats?['totalSize'] ?? 0;
                      final productSizeMB = productSize / (1024 * 1024);

                      return ListTile(
                        leading: const Icon(Icons.tag, size: 20),
                        title: Text('Артикул: $nmId'),
                        subtitle: Text('$photoCount фото (${productSizeMB.toStringAsFixed(2)} МБ)'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () async {
                            final productId = int.tryParse(nmId);
                            if (productId != null) {
                              await PhotoCacheManager().clearCacheForProduct(productId);
                              setState(() {});
                            }
                          },
                          tooltip: 'Очистить кэш для этого товара',
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 24),
              ],

              // Кнопки управления
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await PhotoCacheManager().openCacheFolder();
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open, size: 20),
                          SizedBox(width: 8),
                          Text('Открыть папку кэша'),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 16),

                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Очистка кэша'),
                            content: const Text('Вы уверены, что хотите удалить все кэшированные фотографии?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Отмена'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  await PhotoCacheManager().clearAllCache();
                                  setState(() {});
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: Theme.of(context).colorScheme.error,
                                ),
                                child: const Text('Очистить'),
                              ),
                            ],
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Theme.of(context).colorScheme.error.withOpacity(0.1),
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_outline, size: 20),
                          SizedBox(width: 8),
                          Text('Очистить весь кэш'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Информация
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Информация о кэше:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Фото кэшируются в папке Downloads/cache_woozzee_wb',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    Text(
                      '• Файлы сохраняются в формате {nm_id}_{индекс}.jpg',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    Text(
                      '• При просмотре товара кэшируются 10 предыдущих и 10 следующих товаров',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    Text(
                      '• Кэш сохраняется между сессиями работы программы',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStockSettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Настройки остатков',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 32),

          _buildAutoReplenishmentSwitch(),
          const SizedBox(height: 24),

          if (_autoReplenishmentEnabled) ...[
            _buildIntervalSetting(),
            const SizedBox(height: 24),
          ],

          _buildWarehouseModeSetting(),
          const SizedBox(height: 24),

          if (_modeValue == 'uniform')
            _buildUniformSettings()
          else
            _buildIndividualSettings(),

          const SizedBox(height: 32),
          _buildSaveButtons(),
          const SizedBox(height: 16),
          _buildResetButton(),
        ],
      ),
    );
  }

  Widget _buildAutoReplenishmentSwitch() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Автообновление остатков',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Tooltip(
                message: 'Автоматическое пополнение остатков на FBS складах по расписанию',
                child: Icon(
                  Icons.help_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _autoReplenishmentEnabled ? 'Включено' : 'Выключено',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: _autoReplenishmentEnabled
                            ? Colors.green
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _autoReplenishmentEnabled
                          ? 'Остатки будут обновляться автоматически каждые ${_intervalValue.round()} минут'
                          : 'Автоматическое обновление отключено',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoadingAutoConfig)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Switch(
                  value: _autoReplenishmentEnabled,
                  onChanged: (value) {
                    setState(() {
                      _autoReplenishmentEnabled = value;
                    });
                    // Сохраняем настройки сразу при переключении
                    _saveAutoReplenishmentConfig();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTagSettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Настройки тегов',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Управление поведением остатков для товаров с определенными тегами',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 32),

          if (_isLoadingTags)
            const Center(child: CircularProgressIndicator())
          else if (_tags.isEmpty)
            _buildNoTagsMessage()
          else
            _buildTagsList(),

          const SizedBox(height: 32),
          _buildSaveTagsButton(),
        ],
      ),
    );
  }

  Widget _buildNoTagsMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Icon(Icons.local_offer_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Теги не найдены',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Добавьте теги к товарам в личном кабинете Wildberries',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadTags,
            child: const Text('Обновить список тегов'),
          ),
        ],
      ),
    );
  }

  Widget _buildTagsList() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Всего тегов: ${_tags.length}',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Text(
                'Настроено: ${_tagConfigs.length}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        ..._tags.map((tag) => _buildTagConfig(tag)),
      ],
    );
  }

  Widget _buildTagConfig(dynamic tag) {
    final tagName = tag['name']?.toString() ?? '';
    final tagColor = tag['color']?.toString() ?? 'D1CFD7';
    final config = _tagConfigs[tagName] ?? {};
    final behavior = config['behavior'] ?? 'as_warehouse';
    final fixedAmount = config['fixed_amount'] ?? 0;

    Color backgroundColor;
    try {
      String hexColor = tagColor;
      if (hexColor.startsWith('#')) {
        hexColor = hexColor.substring(1);
      }
      if (hexColor.length == 6) {
        backgroundColor = Color(0xFF000000 + int.parse(hexColor, radix: 16));
      } else {
        backgroundColor = Colors.grey;
      }
    } catch (e) {
      backgroundColor = Colors.grey;
    }

    bool isDark = backgroundColor.computeLuminance() < 0.5;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '#$tagName',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(Icons.local_offer_outlined, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              value: behavior,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Поведение остатков',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'as_warehouse',
                  child: Text('Как склад - использовать настройки склада'),
                ),
                DropdownMenuItem(
                  value: 'always_zero',
                  child: Text('Всегда 0 - никогда не передавать остатки'),
                ),
                DropdownMenuItem(
                  value: 'ignore',
                  child: Text('Игнорировать - не применять автообновление'),
                ),
                DropdownMenuItem(
                  value: 'always_n',
                  child: Text('Всегда N - фиксированное количество'),
                ),
              ],
              onChanged: (value) {
                _updateTagConfig(tagName, 'behavior', value);
              },
            ),

            if (behavior == 'always_n') ...[
              const SizedBox(height: 16),
              TextFormField(
                initialValue: fixedAmount.toString(),
                decoration: const InputDecoration(
                  labelText: 'Фиксированное количество',
                  hintText: 'Введите количество остатков',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  _updateTagConfig(tagName, 'fixed_amount', int.tryParse(value) ?? 0);
                },
              ),
            ],

            const SizedBox(height: 8),
            Text(
              _getBehaviorDescription(behavior),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveTagsButton() {
    return Center(
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveTagConfig,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        ),
        child: _isLoading
            ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : const Text('Сохранить настройки тегов'),
      ),
    );
  }

  Widget _buildIntervalSetting() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Интервал автообновления остатков',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Tooltip(
                message: 'Укажите частоту автоматического обновления данных об остатках',
                child: Icon(
                  Icons.help_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Slider(
            value: _intervalValue,
            min: 1,
            max: 90,
            divisions: 89,
            label: '${_intervalValue.round()} минут',
            onChanged: (value) {
              setState(() {
                _intervalValue = value;
              });
            },
            onChangeEnd: (value) {
              // Сохраняем настройки при окончании изменения слайдера
              _saveAutoReplenishmentConfig();
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_intervalValue.round()} минут',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarehouseModeSetting() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Режим управления складами',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _warehouseMode,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Режим',
              alignLabelWithHint: true,
              suffixIcon: Tooltip(
                message: 'Выберите режим управления остатками на складах',
                child: Icon(
                  Icons.help_outline,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                ),
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: 'Один как все',
                child: Text('Один как все - одинаковые настройки для всех складов'),
              ),
              DropdownMenuItem(
                value: 'Индивидуально',
                child: Text('Индивидуально - разные настройки для каждого склада'),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _warehouseMode = value!;
                _modeValue = value == 'Один как все' ? 'uniform' : 'individual';
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildUniformSettings() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Общие настройки для всех складов',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),

          TextFormField(
            initialValue: (_warehouseConfig['uniform_threshold'] ?? 0).toString(),
            decoration: const InputDecoration(
              labelText: 'Порог FBO',
              hintText: 'Минимальный остаток для FBO',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              setState(() {
                _warehouseConfig['uniform_threshold'] = int.tryParse(value) ?? 0;
              });
            },
          ),
          const SizedBox(height: 16),

          TextFormField(
            initialValue: (_warehouseConfig['uniform_minimum'] ?? 0).toString(),
            decoration: const InputDecoration(
              labelText: 'Мин. остаток FBS',
              hintText: 'Минимальный остаток для FBS',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              setState(() {
                _warehouseConfig['uniform_minimum'] = int.tryParse(value) ?? 0;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIndividualSettings() {
    if (_isLoadingWarehouses) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_warehouses.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            const Icon(Icons.warehouse_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Склады не найдены',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadWarehouses,
              child: const Text('Обновить список складов'),
            ),
          ],
        ),
      );
    }

    final activeWarehousesCount = _warehouses.where((warehouse) {
      final warehouseKey = warehouse['id'].toString();
      final config = _individualConfigs[warehouseKey] ?? {};
      return config['is_activate'] ?? true;
    }).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Индивидуальные настройки по складам',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Chip(
                label: Text('Активировано: $activeWarehousesCount/${_warehouses.length}'),
                backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._warehouses.map((warehouse) => _buildWarehouseConfig(warehouse)),
        ],
      ),
    );
  }

  Widget _buildWarehouseConfig(Map<String, dynamic> warehouse) {
    final warehouseId = warehouse['id'];
    final warehouseKey = warehouseId.toString();
    final config = _individualConfigs[warehouseKey] ?? {};
    final bool isActivated = config['is_activate'] ?? true;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    warehouse['name'],
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isActivated
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                Switch(
                  value: isActivated,
                  onChanged: (value) {
                    _updateIndividualConfig(warehouseId, 'is_activate', value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'ID: $warehouseId • ${warehouse['cargoType'] == 1 ? 'МГТ' : warehouse['cargoType'] == 2 ? 'СГТ' : 'КГТ+'}',
              style: TextStyle(
                color: isActivated ? Colors.grey[600] : Colors.grey[400],
              ),
            ),
            const SizedBox(height: 16),

            Opacity(
              opacity: isActivated ? 1.0 : 0.5,
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      enabled: isActivated,
                      initialValue: (config['threshold'] ?? 0).toString(),
                      decoration: const InputDecoration(
                        labelText: 'Порог FBO',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        _updateIndividualConfig(warehouseId, 'threshold', int.tryParse(value) ?? 0);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      enabled: isActivated,
                      initialValue: (config['minimum'] ?? 0).toString(),
                      decoration: const InputDecoration(
                        labelText: 'Мин. остаток FBS',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        _updateIndividualConfig(warehouseId, 'minimum', int.tryParse(value) ?? 0);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveWarehouseConfig,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: _isLoading
                ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Text('Сохранить настройки складов'),
          ),
        ),
        const SizedBox(width: 16),
        if (_autoReplenishmentEnabled)
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveAutoReplenishmentConfig,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _isLoading
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Text('Сохранить автообновление'),
            ),
          ),
      ],
    );
  }

  Widget _buildResetButton() {
    return Center(
      child: TextButton(
        onPressed: _isLoading ? null : _showResetConfirmationDialog,
        child: Text(
          'Сбросить настройки',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
    );
  }

  void _showResetConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Сброс настроек'),
          content: const Text('Вы уверены, что хотите сбросить все настройки складов к значениям по умолчанию?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                _resetWarehouseSettings();
                Navigator.of(context).pop();
              },
              child: Text(
                'Сбросить',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _resetWarehouseSettings() {
    setState(() {
      _intervalValue = 15.0;
      _modeValue = 'uniform';
      _warehouseMode = 'Один как все';
      _warehouseConfig = {
        'uniform_threshold': 0,
        'uniform_minimum': 0,
        'is_activate': true,
      };
      _individualConfigs = {};
    });

    _saveWarehouseConfig();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // Drawer header with close button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Настройки',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Закрыть настройки',
                ),
              ],
            ),
          ),
          // Main content (same as before)
          Expanded(
            child: Row(
              children: [
                // Left menu
                Container(
                  width: 200,
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
                      _buildMenuButton(context, 'Остатки', Icons.inventory_2_outlined, 0),
                      _buildMenuButton(context, 'Теги', Icons.local_offer_outlined, 1),
                      _buildMenuButton(context, 'Фото', Icons.photo_library_outlined, 2),
                      _buildMenuButton(context, 'Экран цен', Icons.account_balance_outlined, 3),
                    ],
                  ),
                ),
                // Content area
                Expanded(
                  child: _buildSettingsContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}