// Создаем новый файл: lib/widgets/column_filter_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/reports_sync_provider.dart';

class ColumnFilterDialog extends StatefulWidget {
  final String field;
  final String fieldTitle;
  final List<dynamic> currentValues;
  final ReportsSyncProvider provider;
  final DateTimeRange? dateRange;
  final int? nmId;
  final String? saName;
  final Map<String, List<dynamic>>? otherFilters;

  const ColumnFilterDialog({
    Key? key,
    required this.field,
    required this.fieldTitle,
    required this.currentValues,
    required this.provider,
    this.dateRange,
    this.nmId,
    this.saName,
    this.otherFilters,
  }) : super(key: key);

  @override
  _ColumnFilterDialogState createState() => _ColumnFilterDialogState();
}

class _ColumnFilterDialogState extends State<ColumnFilterDialog> {
  late List<dynamic> _selectedValues;
  List<dynamic> _availableValues = [];
  List<dynamic> _filteredValues = [];
  String _searchQuery = '';
  bool _isLoading = false;
  bool _hasNullValues = false;
  bool _isNullSelected = false;

  @override
  void initState() {
    super.initState();
    _selectedValues = List.from(widget.currentValues);
    _isNullSelected = widget.currentValues.any((v) => v == null);
    _loadUniqueValues();
  }

  Future<void> _loadUniqueValues() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final values = await widget.provider.getUniqueValuesForField(
        field: widget.field,
        dateFrom: widget.dateRange?.start,
        dateTo: widget.dateRange?.end,
        nmId: widget.nmId,
        saName: widget.saName,
        otherFilters: widget.otherFilters,
        limit: 1000,
      );

      // Проверяем наличие NULL значений
      final nullValues = values.where((v) => v == null).toList();
      _hasNullValues = nullValues.isNotEmpty;

      // Убираем NULL из основного списка
      final nonNullValues = values.where((v) => v != null).toList();

      setState(() {
        _availableValues = nonNullValues;
        _filteredValues = nonNullValues;
      });
    } catch (e) {
      print('Ошибка загрузки уникальных значений: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка загрузки данных: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterValues(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredValues = _availableValues;
      } else {
        _filteredValues = _availableValues.where((value) {
          final strValue = value.toString().toLowerCase();
          return strValue.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  void _toggleValue(dynamic value) {
    setState(() {
      if (_selectedValues.contains(value)) {
        _selectedValues.remove(value);
      } else {
        _selectedValues.add(value);
      }
    });
  }

  void _toggleNull() {
    setState(() {
      _isNullSelected = !_isNullSelected;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedValues.clear();
      _isNullSelected = false;
    });
  }

  void _applyFilter() {
    final List<dynamic> finalValues = List.from(_selectedValues);
    if (_isNullSelected) {
      finalValues.add(null);
    }
    Navigator.pop(context, finalValues);
  }

  String _formatValue(dynamic value) {
    if (value == null) return '(пусто)';
    
    if (value is DateTime) {
      return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
    }
    
    if (value is num) {
      // Для процентных полей
      if (widget.field.endsWith('_percent') || 
          widget.field.endsWith('_prc') || 
          widget.field.contains('percent') || 
          widget.field.contains('prc')) {
        return '${value.toStringAsFixed(2)}%';
      }
      
      // Для валютных полей
      if (widget.field.endsWith('_amount') ||
          widget.field.endsWith('_price') ||
          widget.field.endsWith('_rub') ||
          widget.field.endsWith('_fee') ||
          widget.field.endsWith('_commission')) {
        return '${value.toStringAsFixed(2)} ₽';
      }
      
      // Для целых чисел
      return value.toString();
    }
    
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Фильтр по "$widget.fieldTitle"',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      content: Container(
        width: 400,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Поле поиска
            TextField(
              decoration: InputDecoration(
                hintText: 'Поиск...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onChanged: _filterValues,
            ),
            const SizedBox(height: 12),
            
            // Информация о загрузке
            if (_isLoading)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('Загрузка значений...'),
                  ],
                ),
              )
            else if (_availableValues.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'Нет доступных значений',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Expanded(
                child: Column(
                  children: [
                    // Чекбокс для NULL значений
                    if (_hasNullValues)
                      CheckboxListTile(
                        title: const Text('(пусто)'),
                        value: _isNullSelected,
                        onChanged: (value) => _toggleNull(),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    
                    // Разделитель
                    if (_hasNullValues && _filteredValues.isNotEmpty)
                      const Divider(height: 1),
                    
                    // Список значений
                    Expanded(
                      child: ListView.builder(
                        itemCount: _filteredValues.length,
                        itemBuilder: (context, index) {
                          final value = _filteredValues[index];
                          final isSelected = _selectedValues.contains(value);
                          final displayValue = _formatValue(value);
                          
                          return CheckboxListTile(
                            title: Text(
                              displayValue,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected ? Colors.black : Colors.grey[700],
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                            value: isSelected,
                            onChanged: (value) => _toggleValue(_filteredValues[index]),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        },
                      ),
                    ),
                    
                    // Информация о количестве
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Найдено: ${_filteredValues.length}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          Text(
                            'Выбрано: ${_selectedValues.length + (_isNullSelected ? 1 : 0)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _clearSelection,
          child: const Text('Сбросить'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _applyFilter,
          child: const Text('Применить'),
        ),
      ],
    );
  }
}