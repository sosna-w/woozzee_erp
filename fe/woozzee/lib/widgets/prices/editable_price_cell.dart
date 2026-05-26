import 'package:flutter/material.dart';
import '../../utils/price_manager.dart';

class EditablePriceCell extends StatefulWidget {
  final int nmID;
  final int chrtID;
  final String field;
  final dynamic initialValue;
  final Function(int nmID, int chrtID, dynamic newValue) onChanged;
  final ValueChanged<int>? onDraftChanged;
  final VoidCallback? onSend;

  const EditablePriceCell({
    Key? key,
    required this.nmID,
    required this.chrtID,
    required this.field,
    required this.initialValue,
    required this.onChanged,
    this.onSend,
    this.onDraftChanged,
  }) : super(key: key);

  @override
  State<EditablePriceCell> createState() => _EditablePriceCellState();
}

class _EditablePriceCellState extends State<EditablePriceCell> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isLoading = false;
  String? _error;
  bool _isChanged = false;
  final PriceManager _priceManager = PriceManager();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue?.toString() ?? '');
    _focusNode = FocusNode();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final newVal = _controller.text.trim();
    final oldVal = widget.initialValue?.toString() ?? '';
    setState(() {
      _isChanged = newVal != oldVal;
      _error = null;
    });
  }

  void _updateValue(int newValue, {bool notifyDraft = true}) {
    _controller.text = newValue.toString();
    _onTextChanged();
    if (notifyDraft && widget.onDraftChanged != null) {
      widget.onDraftChanged!(newValue);
    }
  }

  void _step(int delta) {
    int current = int.tryParse(_controller.text) ?? 0;
    int newValue = current + delta;
    if (widget.field != 'price') {
      newValue = newValue.clamp(0, 100);
    }
    _updateValue(newValue);
  }

  Future<void> _send() async {
    if (!_isChanged) return;
    setState(() => _isLoading = true);
    try {
      final newValue = int.tryParse(_controller.text);
      if (newValue == null) throw Exception('Некорректное число');
      if (widget.field == 'price') {
        await _priceManager.updatePriceAndDiscount(widget.nmID, price: newValue);
      } else if (widget.field == 'discount') {
        await _priceManager.updatePriceAndDiscount(widget.nmID, discount: newValue);
      } else {
        await _priceManager.updateClubDiscount(widget.nmID, newValue);
      }
      widget.onChanged(widget.nmID, widget.chrtID, newValue);
      setState(() => _isChanged = false);
      widget.onSend?.call();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _focusNode.requestFocus(),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: _isChanged ? Colors.blue : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Stack(
                  children: [
                    TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.fromLTRB(6, 0, 28, 0),
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (text) {
                        final newValue = int.tryParse(text);
                        if (newValue != null && widget.onDraftChanged != null) {
                          widget.onDraftChanged!(newValue);
                        }
                        _onTextChanged();
                      },
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Column(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _step(1),
                              child: const Icon(Icons.arrow_drop_up, size: 16),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => _step(-1),
                              child: const Icon(Icons.arrow_drop_down, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 28,
            height: 28,
            child: _isLoading
                ? const CircularProgressIndicator(strokeWidth: 2)
                : IconButton(
                    icon: Icon(_error != null ? Icons.error : Icons.send, size: 16),
                    color: _isChanged ? Colors.blue : Colors.grey,
                    onPressed: _isChanged ? _send : null,
                    padding: EdgeInsets.zero,
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}