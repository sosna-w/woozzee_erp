import 'package:flutter/material.dart';
import '../../providers/reports_sync_provider.dart';
import '../../constants/reports_constants.dart';

class CustomColumnManagementDialog extends StatefulWidget {
  final ReportsSyncProvider provider;
  final List<Map<String, dynamic>> templates;
  final List<String> availableFields;
  final Map<String, String> columnTranslations;
  final VoidCallback onColumnsChanged;

  const CustomColumnManagementDialog({
    Key? key,
    required this.provider,
    required this.templates,
    required this.availableFields,
    required this.columnTranslations,
    required this.onColumnsChanged,
  }) : super(key: key);

  @override
  State<CustomColumnManagementDialog> createState() => _CustomColumnManagementDialogState();
}

class _CustomColumnManagementDialogState extends State<CustomColumnManagementDialog> {
  List<Map<String, dynamic>> _customColumns = [];
  bool _isLoading = true;
  String? _selectedTemplateDisplayName;
  String? _editingColumnName;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _formulaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadColumns();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _formulaController.dispose();
    super.dispose();
  }

  Future<void> _loadColumns() async {
    final cols = await widget.provider.getCustomColumns();
    if (mounted) {
      setState(() {
        _customColumns = cols;
        _isLoading = false;
      });
    }
  }

  String _simplifyFormula(String formula) {
    final regex = RegExp(r'COALESCE\(\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*,\s*0\s*\)');
    return formula.replaceAllMapped(regex, (match) {
      final field = match.group(1)!;
      return widget.columnTranslations[field] ?? field;
    });
  }

  void _refreshAfterOperation() async {
    final cols = await widget.provider.getCustomColumns();
    if (mounted) {
      setState(() => _customColumns = cols);
    }
    widget.onColumnsChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: FractionallySizedBox(
        widthFactor: 0.8,
        heightFactor: 0.8,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 50, child: Center(child: Text('Управление кастомными столбцами', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Левая панель – существующие колонки
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Существующие столбцы:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _isLoading
                                ? const Center(child: CircularProgressIndicator())
                                : _customColumns.isEmpty
                                    ? const Center(child: Text('Нет кастомных столбцов'))
                                    : ListView.builder(
                                        itemCount: _customColumns.length,
                                        itemBuilder: (ctx, index) {
                                          final col = _customColumns[index];
                                          final colName = col['column_name'] as String;
                                          final displayName = col['display_name'] as String;
                                          final formula = col['formula'] as String;
                                          return Card(
                                            margin: const EdgeInsets.only(bottom: 8),
                                            child: Padding(
                                              padding: const EdgeInsets.all(8.0),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                                  const SizedBox(height: 4),
                                                  Text(_simplifyFormula(formula), style: const TextStyle(fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.end,
                                                    children: [
                                                      IconButton(
                                                        icon: const Icon(Icons.edit, size: 18),
                                                        onPressed: () {
                                                          _nameController.text = displayName;
                                                          _formulaController.text = formula;
                                                          setState(() {
                                                            _editingColumnName = colName;
                                                            _selectedTemplateDisplayName = null;
                                                          });
                                                        },
                                                        tooltip: 'Редактировать',
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                                        onPressed: () async {
                                                          final confirm = await showDialog<bool>(
                                                            context: context,
                                                            builder: (ctx) => AlertDialog(
                                                              title: const Text('Удаление столбца'),
                                                              content: Text('Удалить столбец "$displayName"?'),
                                                              actions: [
                                                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                                                                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Удалить')),
                                                              ],
                                                            ),
                                                          );
                                                          if (confirm == true) {
                                                            try {
                                                              await widget.provider.deleteCustomColumn(colName);
                                                              if (mounted) {
                                                                if (_editingColumnName == colName) {
                                                                  _nameController.clear();
                                                                  _formulaController.clear();
                                                                  _editingColumnName = null;
                                                                }
                                                                _refreshAfterOperation();
                                                              }
                                                            } catch (e) {
                                                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка удаления: $e')));
                                                            }
                                                          }
                                                        },
                                                        tooltip: 'Удалить',
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Правая панель – создание/редактирование
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.templates.isNotEmpty) ...[
                            const Text('Шаблон:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<String>(
                              value: _selectedTemplateDisplayName,
                              hint: const Text('— выберите —'),
                              isExpanded: true,
                              items: widget.templates.map((t) => DropdownMenuItem<String>(value: t['display_name'] as String, child: Text(t['display_name'] as String))).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  final template = widget.templates.firstWhere((t) => t['display_name'] == value);
                                  _nameController.text = template['display_name'] as String;
                                  _formulaController.text = template['formula'] as String;
                                  setState(() {
                                    _selectedTemplateDisplayName = value;
                                    _editingColumnName = null;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Название столбца', border: OutlineInputBorder())),
                          const SizedBox(height: 8),
                          SizedBox(height: 100, child: TextField(controller: _formulaController, decoration: const InputDecoration(labelText: 'Формула', border: OutlineInputBorder(), hintText: 'например: retail_price + delivery_rub'), maxLines: 3)),
                          const SizedBox(height: 8),
                          const Text('Операторы:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            children: ['+', '-', '*', '/', '(', ')'].map((op) => ElevatedButton(onPressed: () => _formulaController.text += op, style: ElevatedButton.styleFrom(minimumSize: const Size(40, 36), padding: EdgeInsets.zero), child: Text(op, style: const TextStyle(fontSize: 16)))).toList(),
                          ),
                          const SizedBox(height: 16),
                          const Text('Доступные поля:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: widget.availableFields.map((field) => ActionChip(label: Text(widget.columnTranslations[field] ?? field, style: const TextStyle(fontSize: 11)), onPressed: () => _formulaController.text += field)).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final name = _nameController.text.trim();
                      final formula = _formulaController.text.trim();
                      if (name.isEmpty || formula.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Название и формула не могут быть пустыми'), backgroundColor: Colors.orange));
                        return;
                      }
                      final regex = RegExp(r'[a-zA-Z_][a-zA-Z0-9_]*');
                      final matches = regex.allMatches(formula);
                      final usedFields = matches.map((m) => m.group(0)).toSet();
                      final invalidFields = usedFields.where((f) => !widget.availableFields.contains(f)).toList();
                      if (invalidFields.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Неизвестные поля: ${invalidFields.join(', ')}'), backgroundColor: Colors.orange));
                        return;
                      }
                      try {
                        if (_editingColumnName != null) {
                          await widget.provider.updateCustomColumn(_editingColumnName!, name, formula);
                        } else {
                          await widget.provider.addCustomColumn(name, formula);
                        }
                        if (mounted) {
                          _nameController.clear();
                          _formulaController.clear();
                          setState(() {
                            _editingColumnName = null;
                            _selectedTemplateDisplayName = null;
                          });
                          _refreshAfterOperation();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_editingColumnName != null ? 'Столбец "$name" обновлён' : 'Столбец "$name" создан'), backgroundColor: Colors.green));
                        }
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
                      }
                    },
                    child: Text(_editingColumnName != null ? 'Обновить' : 'Создать'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}