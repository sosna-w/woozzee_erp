// logs_screen.dart
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'dart:async';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  List<dynamic> _logs = [];
  List<dynamic> _filteredLogs = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;

  // Параметры пагинации
  int _currentOffset = 0;
  int _itemsPerPage = 100;
  int _totalLogsCount = 0;
  bool _hasMore = true;

  // Параметры сортировки и фильтрации
  String? _sortColumn;
  bool _sortAscending = true;
  final Map<String, List<String>> _filters = {};
  final Map<String, List<String>> _availableFilterValues = {};
  final Map<String, bool> _filterVisibility = {};

  // Переменные для управления детализацией при наведении
  OverlayEntry? _overlayEntry;
  dynamic _hoveredLog;
  Offset _hoverPosition = Offset.zero;

  // Параметры для стриминга
  int _lastStreamId = 0;
  bool _isStreaming = false;
  bool _autoScrollEnabled = false;
  Timer? _streamTimer;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listKey = GlobalKey();

  // Очередь для плавного добавления логов
  final List<dynamic> _streamBuffer = [];
  bool _isProcessingBuffer = false;
  Timer? _bufferProcessingTimer;
  static const Duration _bufferProcessingInterval = Duration(milliseconds: 50);

  // Фиксированные ширины столбцов
  final Map<String, double> _columnWidths = {
    'ID': 80.0,
    'Время': 120.0,
    'Уровень': 100.0,
    'Метод': 150.0,
    'Событие': 200.0,
    'Детали': 200.0,
    'Длит.': 100.0,
    'nmID': 120.0,
    'Статус': 100.0,
    'Записи': 100.0,
  };

  @override
  void initState() {
    super.initState();
    _loadInitialData();

    // Добавляем слушатель для подгрузки при прокрутке
    _scrollController.addListener(_scrollListener);

    // Автопрокрутка вверх при включении
    _scrollController.addListener(() {
      if (_autoScrollEnabled && _isStreaming) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && _scrollController.offset < 100) {
            _scrollController.jumpTo(0);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _removeHoverOverlay();
    _stopStreaming();
    _stopBufferProcessing();
    super.dispose();
  }

  void _scrollListener() {
    // Подгрузка данных при прокрутке вниз
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore &&
        !_isStreaming) {
      _loadMoreLogs();
    }
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _currentOffset = 0;
      _hasMore = true;
    });

    try {
      // Загружаем начальные данные через /logs/initial
      await _loadInitialLogs();

      // Запускаем стриминг
      _startStreaming();
    } catch (e) {
      _showErrorSnackbar('Ошибка загрузки: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadInitialLogs() async {
    try {
      final uri = Uri.parse('https://hide_domain.com/logs/initial')
          .replace(queryParameters: {
        'limit': _itemsPerPage.toString(),
      });

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final logs = data['logs'] as List<dynamic>;
          _lastStreamId = data['last_id'] ?? 0;

          // Устанавливаем максимальный ID из начальных данных
          if (logs.isNotEmpty) {
            final maxId = logs.map<int>((log) => log['id'] as int).reduce((a, b) => a > b ? a : b);
            _lastStreamId = maxId;
          }

          // Сортируем по ID по убыванию (новые сверху)
          logs.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));

          setState(() {
            _logs = logs;
            _filteredLogs = _applyFilters(logs);
            _totalLogsCount = logs.length;
          });
        } else {
          throw Exception(data['error'] ?? 'Unknown error');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading initial logs: $e');
      rethrow;
    }
  }

  Future<void> _loadMoreLogs() async {
    if (!_hasMore || _isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextOffset = _currentOffset + _itemsPerPage;
      final uri = Uri.parse('https://hide_domain.com/logs')
          .replace(queryParameters: {
        'limit': _itemsPerPage.toString(),
        'offset': nextOffset.toString(),
      });

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newLogs = data['logs'] as List<dynamic>;

        if (newLogs.isNotEmpty) {
          // Сортируем по ID по убыванию
          newLogs.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));

          setState(() {
            _logs.addAll(newLogs);
            _filteredLogs = _applyFilters(_logs);
            _currentOffset = nextOffset;
            _totalLogsCount = data['total_count'] ?? _totalLogsCount;
            _hasMore = newLogs.length == _itemsPerPage;
          });
        } else {
          setState(() {
            _hasMore = false;
          });
        }
      } else {
        _showErrorSnackbar('Ошибка загрузки: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackbar('Ошибка подключения: $e');
    } finally {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  // Стриминг логов в реальном времени
  void _startStreaming() {
    if (_isStreaming) return;

    setState(() {
      _isStreaming = true;
    });

    // Запускаем таймер для периодического опроса
    _streamTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _fetchStreamLogs();
    });

    // Первый запрос сразу
    _fetchStreamLogs();
  }

  void _stopStreaming() {
    _streamTimer?.cancel();
    _streamTimer = null;
    setState(() {
      _isStreaming = false;
    });
    _stopBufferProcessing();
  }

  void _toggleAutoScroll() {
    setState(() {
      _autoScrollEnabled = !_autoScrollEnabled;
    });

    if (_autoScrollEnabled && _isStreaming) {
      _scrollToTop();
    }
  }

  Future<void> _fetchStreamLogs() async {
    if (!_isStreaming) return;

    try {
      final uri = Uri.parse('https://hide_domain.com/logs/stream')
          .replace(queryParameters: {
        'last_id': _lastStreamId.toString(),
        'timeout': '1',
        'limit': '100',
      });

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final newLogs = data['logs'] as List<dynamic>;
          if (newLogs.isNotEmpty) {
            _lastStreamId = data['last_id'] ?? _lastStreamId;
            _addToStreamBuffer(newLogs);
          }
        }
      }
    } catch (e) {
      print('Stream error: $e');
    }
  }

  void _addToStreamBuffer(List<dynamic> newLogs) {
    if (newLogs.isEmpty) return;

    // Сортируем по ID по убыванию (новые сверху)
    newLogs.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));

    // Обновляем последний ID
    final maxId = newLogs.map<int>((log) => log['id'] as int).reduce((a, b) => a > b ? a : b);
    if (maxId > _lastStreamId) {
      _lastStreamId = maxId;
    }

    // Добавляем в буфер для плавного отображения
    _streamBuffer.addAll(newLogs);

    // Запускаем обработку буфера, если еще не запущена
    if (!_isProcessingBuffer) {
      _startBufferProcessing();
    }
  }

  void _startBufferProcessing() {
    _isProcessingBuffer = true;
    _bufferProcessingTimer = Timer.periodic(_bufferProcessingInterval, (_) {
      _processBufferItem();
    });
  }

  void _stopBufferProcessing() {
    _bufferProcessingTimer?.cancel();
    _bufferProcessingTimer = null;
    _isProcessingBuffer = false;
    _streamBuffer.clear();
  }

  void _processBufferItem() {
    if (_streamBuffer.isEmpty) {
      _stopBufferProcessing();
      return;
    }

    // Берем следующий лог из буфера
    final log = _streamBuffer.removeAt(0);

    // Добавляем по одному с анимацией
    setState(() {
      _logs.insert(0, log);
      _filteredLogs = _applyFilters(_logs);
      _totalLogsCount += 1;
    });

    // Прокрутка к началу при включенной автопрокрутке
    if (_autoScrollEnabled && _isStreaming) {
      _scrollToTopSmoothly();
    }

    // Если буфер опустел, останавливаем обработку
    if (_streamBuffer.isEmpty) {
      _stopBufferProcessing();
    }
  }

  void _scrollToTopSmoothly() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _scrollController.offset > 0) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Новый метод для очистки базы данных
  Future<void> _clearDatabase() async {
    final bool? shouldClear = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Очистка базы данных'),
          content: const Text(
            'Вы уверены, что хотите удалить ВСЕ данные логов? '
                'Это действие нельзя отменить.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Удалить все',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );

    if (shouldClear == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        final uri = Uri.parse('https://hide_domain.com/logs/clear');
        final response = await http.get(uri);

        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('База данных успешно очищена'),
                backgroundColor: Colors.green,
              ),
            );
          }

          // Сбрасываем стриминг и обновляем данные
          _stopStreaming();
          _stopBufferProcessing();
          setState(() {
            _logs = [];
            _filteredLogs = [];
            _totalLogsCount = 0;
            _lastStreamId = 0;
            _currentOffset = 0;
            _hasMore = true;
          });

          // Загружаем заново и запускаем стриминг
          await _loadInitialData();
        } else {
          _showErrorSnackbar('Ошибка очистки базы: ${response.statusCode}');
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

  Future<void> _copyRowToClipboard(dynamic log) async {
    final String formattedLog = '''
ID: ${log['id'] ?? ''}
Время: ${log['timestamp'] ?? ''}
Уровень: ${log['level'] ?? ''}
Метод: ${log['method'] ?? ''}
Событие: ${log['event'] ?? ''}
Детали: ${log['details'] != null ? json.encode(log['details']) : ''}
Длительность: ${log['duration_ms']?.toString() ?? ''} мс
nmID: ${log['nm_id'] ?? ''}
Статус: ${log['response_status'] ?? ''}
Записей: ${log['records_processed'] ?? ''}
''';

    await Clipboard.setData(ClipboardData(text: formattedLog));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Данные строки скопированы в буфер обмена'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // Функции для управления детализацией при наведении
  void _showHoverOverlay(dynamic log, Offset position) {
    _removeHoverOverlay();

    _hoveredLog = log;
    _hoverPosition = position;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: position.dx + 10,
        top: position.dy + 10,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 500,
            constraints: const BoxConstraints(maxHeight: 600),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300, width: 1),
            ),
            child: SingleChildScrollView(
              child: _buildLogDetails(log),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeHoverOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _hoveredLog = null;
  }

  Widget _buildLogDetails(dynamic log) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDetailRow('ID:', log['id']?.toString() ?? ''),
        _buildDetailRow('Время:', log['timestamp']?.toString() ?? ''),
        _buildDetailRow('Уровень:', log['level']?.toString() ?? ''),
        _buildDetailRow('Метод:', log['method']?.toString() ?? ''),
        _buildDetailRow('Событие:', log['event']?.toString() ?? ''),
        _buildDetailRow('Детали:',
            log['details'] != null ? json.encode(log['details']) : ''),
        _buildDetailRow('Длительность:',
            log['duration_ms'] != null ? '${log['duration_ms']} мс' : ''),
        _buildDetailRow('nmID:', log['nm_id']?.toString() ?? ''),
        _buildDetailRow('Статус:', log['response_status']?.toString() ?? ''),
        _buildDetailRow('Записей:', log['records_processed']?.toString() ?? ''),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 12),
                softWrap: true,
              ),
            ),
          ],
        )
    );
  }

  // Функции для сортировки и фильтрации
  void _sortColumnBy(String columnName) {
    setState(() {
      if (_sortColumn == columnName) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = columnName;
        _sortAscending = true;
      }

      // Применяем сортировку к отфильтрованным логам
      _filteredLogs.sort((a, b) {
        final aValue = a[_getFieldName(columnName)]?.toString() ?? '';
        final bValue = b[_getFieldName(columnName)]?.toString() ?? '';

        final comparison = aValue.compareTo(bValue);
        return _sortAscending ? comparison : -comparison;
      });
    });
  }

  String _getFieldName(String columnName) {
    final fieldMap = {
      'ID': 'id',
      'Время': 'timestamp',
      'Уровень': 'level',
      'Метод': 'method',
      'Событие': 'event',
      'Детали': 'details',
      'Длит.': 'duration_ms',
      'nmID': 'nm_id',
      'Статус': 'response_status',
      'Записи': 'records_processed',
    };
    return fieldMap[columnName] ?? columnName.toLowerCase();
  }

  List<dynamic> _applyFilters(List<dynamic> logs) {
    if (_filters.isEmpty) return List.from(logs);

    return logs.where((log) {
      for (final entry in _filters.entries) {
        final fieldName = _getFieldName(entry.key);
        final value = log[fieldName]?.toString() ?? '';
        if (!entry.value.contains(value)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  // Функции для фильтрации
  void _toggleFilterVisibility(String columnName) {
    setState(() {
      _filterVisibility[columnName] = !(_filterVisibility[columnName] ?? false);
    });
  }

  void _updateFilter(String columnName, String value, bool checked) {
    setState(() {
      if (checked) {
        if (!_filters.containsKey(columnName)) {
          _filters[columnName] = [];
        }
        _filters[columnName]!.add(value);
      } else {
        _filters[columnName]?.remove(value);
        if (_filters[columnName]?.isEmpty ?? false) {
          _filters.remove(columnName);
        }
      }
      _filteredLogs = _applyFilters(_logs);
    });
  }

  void _clearFilters() {
    setState(() {
      _filters.clear();
      _filterVisibility.clear();
      _filteredLogs = _applyFilters(_logs);
    });
  }

  Widget _buildFilterButton(String columnName) {
    return IconButton(
      icon: Icon(
        Icons.filter_list,
        color: _filters.containsKey(columnName) ? Colors.blue : Colors.grey,
        size: 16,
      ),
      onPressed: () => _toggleFilterVisibility(columnName),
      tooltip: 'Фильтр по столбцу',
    );
  }

  Widget _buildFilterPanel(String columnName) {
    if (!(_filterVisibility[columnName] ?? false)) {
      return const SizedBox.shrink();
    }

    // Собираем уникальные значения для этого столбца из всех загруженных данных
    final uniqueValues = <String>{};
    for (final log in _logs) {
      final value = log[_getFieldName(columnName)]?.toString() ?? '';
      if (value.isNotEmpty) {
        uniqueValues.add(value);
      }
    }

    final valuesList = uniqueValues.toList()..sort();

    return Container(
      width: _columnWidths[columnName]! + 100,
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Фильтр: $columnName',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => _toggleFilterVisibility(columnName),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: ListView.builder(
              itemCount: valuesList.length,
              itemBuilder: (context, index) {
                final value = valuesList[index];
                final isChecked = _filters[columnName]?.contains(value) ?? false;
                return CheckboxListTile(
                  title: Text(
                    value,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  value: isChecked,
                  onChanged: (checked) => _updateFilter(columnName, value, checked ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      height: 56,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _columnWidths.entries.map((entry) {
            return SizedBox(
              width: entry.value,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _buildFilterButton(entry.key),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTableRow(dynamic log, int index, {bool isNew = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isNew
            ? Colors.green.shade50
            : index % 2 == 0 ? Colors.white : Colors.grey.shade50,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _copyRowToClipboard(log),
          child: Container(
            height: 40,
            child: Row(
              children: [
                _buildTableCell('ID', log, _columnWidths['ID']!),
                _buildTableCell('Время', log, _columnWidths['Время']!),
                _buildTableCell('Уровень', log, _columnWidths['Уровень']!),
                _buildTableCell('Метод', log, _columnWidths['Метод']!),
                _buildTableCell('Событие', log, _columnWidths['Событие']!),
                _buildTableCell('Детали', log, _columnWidths['Детали']!),
                _buildTableCell('Длит.', log, _columnWidths['Длит.']!),
                _buildTableCell('nmID', log, _columnWidths['nmID']!),
                _buildTableCell('Статус', log, _columnWidths['Статус']!),
                _buildTableCell('Записи', log, _columnWidths['Записи']!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableCell(String columnName, dynamic log, double width) {
    Widget content;
    switch (columnName) {
      case 'ID':
        content = Text(log['id']?.toString() ?? '');
        break;
      case 'Время':
        content = Text(log['timestamp'] != null
            ? log['timestamp'].toString().substring(11, 19)
            : '');
        break;
      case 'Уровень':
        content = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getLevelColor(log['level']),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            log['level'] ?? '',
            style: const TextStyle(color: Colors.white),
          ),
        );
        break;
      case 'Метод':
        content = Text(log['method']?.toString() ?? '');
        break;
      case 'Событие':
        content = Text(
          log['event']?.toString() ?? '',
          overflow: TextOverflow.ellipsis,
        );
        break;
      case 'Детали':
        content = Text(
          log['details'] != null
              ? json.encode(log['details'])
              : '',
          overflow: TextOverflow.ellipsis,
        );
        break;
      case 'Длит.':
        content = Text(log['duration_ms']?.toStringAsFixed(2) ?? '');
        break;
      case 'nmID':
        content = Text(log['nm_id']?.toString() ?? '');
        break;
      case 'Статус':
        content = Text(log['response_status']?.toString() ?? '');
        break;
      case 'Записи':
        content = Text(log['records_processed']?.toString() ?? '');
        break;
      default:
        content = Text(log[_getFieldName(columnName)]?.toString() ?? '');
    }

    return MouseRegion(
      onEnter: (event) {
        final renderBox = context.findRenderObject() as RenderBox;
        final offset = renderBox.localToGlobal(event.localPosition);
        _showHoverOverlay(log, offset);
      },
      onHover: (event) {
        if (_overlayEntry != null) {
          final renderBox = context.findRenderObject() as RenderBox;
          final offset = renderBox.localToGlobal(event.localPosition);
          _removeHoverOverlay();
          _showHoverOverlay(log, offset);
        }
      },
      onExit: (event) => _removeHoverOverlay(),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: content,
        ),
      ),
    );
  }

  Widget _buildDataTable() {
    if (_isLoading && _filteredLogs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredLogs.isEmpty) {
      return const Center(
        child: Text(
          'Логи не найдены',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return Expanded(
      child: Column(
        children: [
          // Индикатор новых записей в реальном времени
          if (_isStreaming && _isProcessingBuffer)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 40,
              color: Colors.blue.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    child: Icon(
                      Icons.arrow_upward,
                      color: Colors.blue,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Добавляется ${_streamBuffer.length} новых записей...',
                    style: TextStyle(color: Colors.blue.shade700),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                  ),
                ],
              ),
            ),

          // Панель фильтров
          if (_filterVisibility.values.any((visible) => visible))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Text(
                    'Активные фильтры:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  ..._filters.entries.map((entry) {
                    return Row(
                      children: [
                        Chip(
                          label: Text('${entry.key}: ${entry.value.length}'),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () {
                            setState(() {
                              _filters.remove(entry.key);
                              _filteredLogs = _applyFilters(_logs);
                            });
                          },
                        ),
                        const SizedBox(width: 4),
                      ],
                    );
                  }),
                  const Spacer(),
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text('Очистить все'),
                  ),
                ],
              ),
            ),

          // Заголовок таблицы
          _buildTableHeader(),

          // Тело таблицы
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (scrollNotification) {
                return false;
              },
              child: CustomScrollView(
                key: _listKey,
                controller: _scrollController,
                slivers: [
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, index) {
                        if (index < _filteredLogs.length) {
                          // Определяем, является ли запись новой (первые 10 записей при активной обработке буфера)
                          bool isNew = _isProcessingBuffer && index < 10;
                          return _buildTableRow(_filteredLogs[index], index, isNew: isNew);
                        }
                        return null;
                      },
                      childCount: _filteredLogs.length,
                    ),
                  ),

                  // Индикатор загрузки
                  if (_isLoadingMore)
                    SliverToBoxAdapter(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ),

                  // Сообщение о конце списка
                  if (!_hasMore && !_isStreaming)
                    SliverToBoxAdapter(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        child: const Center(
                          child: Text(
                            'Все записи загружены',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text('Логи системы'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          // Кнопка управления автопрокруткой
          IconButton(
            onPressed: _toggleAutoScroll,
            icon: Icon(
              _autoScrollEnabled ? Icons.arrow_upward : Icons.arrow_downward,
              color: _autoScrollEnabled ? Colors.blue : Colors.grey,
            ),
            tooltip: _autoScrollEnabled ? 'Выключить автопрокрутку' : 'Включить автопрокрутку',
          ),

          // Индикатор стриминга
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  color: _isStreaming ? Colors.green : Colors.grey,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  _isStreaming ? 'Live' : 'Off',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isStreaming ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ),

          // Кнопка очистки базы данных
          IconButton(
            onPressed: _clearDatabase,
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Очистить базу данных',
          ),

          if (_filters.isNotEmpty)
            IconButton(
              onPressed: _clearFilters,
              icon: const Icon(Icons.filter_alt_off),
              tooltip: 'Очистить фильтры',
            ),

          IconButton(
            onPressed: _loadInitialData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          // Информация о количестве записей
          Container(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Всего записей: ${_filteredLogs.length}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Режим: ',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          _isStreaming ? 'Реальное время' : 'История',
                          style: TextStyle(
                            color: _isStreaming ? Colors.green : Colors.blue,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Автопрокрутка: ',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          _autoScrollEnabled ? 'Вкл' : 'Выкл',
                          style: TextStyle(
                            color: _autoScrollEnabled ? Colors.green : Colors.grey,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_isStreaming) ...[
                          const SizedBox(width: 16),
                          Text(
                            'Добавляется: ${_isProcessingBuffer ? 'построчно' : 'пачками'}',
                            style: TextStyle(
                              color: _isProcessingBuffer ? Colors.green : Colors.blue.shade700,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ),

          // Панели фильтров
          ..._columnWidths.keys.map((columnName) => _buildFilterPanel(columnName)),

          // Таблица
          _buildDataTable(),
        ],
      ),
    );
  }

  Color _getLevelColor(String? level) {
    switch (level) {
      case 'ERROR': return Colors.red;
      case 'WARNING': return Colors.orange;
      case 'INFO': return Colors.blue;
      case 'DEBUG': return Colors.grey;
      default: return Colors.grey;
    }
  }
}