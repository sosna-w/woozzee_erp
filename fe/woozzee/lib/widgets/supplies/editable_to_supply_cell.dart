import 'package:flutter/material.dart';

class EditableToSupplyCell extends StatefulWidget {
  final int nmId;
  final int initialValue;
  final ValueChanged<int?> onChanged;
  final int maxValue;

  const EditableToSupplyCell({
    Key? key,
    required this.nmId,
    required this.initialValue,
    required this.onChanged,
    required this.maxValue,
  }) : super(key: key);

  @override
  State<EditableToSupplyCell> createState() => _EditableToSupplyCellState();
}

class _EditableToSupplyCellState extends State<EditableToSupplyCell> {
  late int _value;
  bool _isEditing = false;
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
    _controller = TextEditingController(text: _value.toString());
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        _submitEdit();
      }
    });
  }

  @override
  void didUpdateWidget(EditableToSupplyCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue && !_isEditing) {
      _value = widget.initialValue;
      _controller.text = _value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _increment() {
    if (_isEditing) return;
    _value++;
    widget.onChanged(_value);
  }

  void _decrement() {
    if (_isEditing) return;
    if (_value <= 0) return;
    _value--;
    widget.onChanged(_value);
  }

  void _startEditing() {
    if (_isEditing) return;
    setState(() {
      _isEditing = true;
      _controller.text = _value.toString();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    });
  }

  void _submitEdit() {
    if (!_isEditing) return;
    final newText = _controller.text.trim();
    final newValue = int.tryParse(newText);
    if (newValue != null && newValue >= 0) {
      _value = newValue;
      widget.onChanged(_value);
    } else {
      _controller.text = _value.toString();
    }
    setState(() {
      _isEditing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 16),
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            padding: EdgeInsets.zero,
            onPressed: _isEditing ? null : _decrement,
            tooltip: 'Уменьшить на 1',
          ),
          _isEditing
              ? SizedBox(
            width: 60,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 4),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _submitEdit(),
            ),
          )
              : GestureDetector(
            onDoubleTap: _startEditing,
            child: Container(
              width: 40,
              alignment: Alignment.center,
              child: Text(
                _value.toString(),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            padding: EdgeInsets.zero,
            onPressed: _isEditing ? null : _increment,
            tooltip: 'Увеличить на 1',
          ),
        ],
      ),
    );
  }
}