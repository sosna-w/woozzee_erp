import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/batch.dart';

class BatchDetailsCell extends StatefulWidget {
  final int nmId;
  final BatchEntry? entry;

  const BatchDetailsCell({Key? key, required this.nmId, required this.entry}) : super(key: key);

  @override
  State<BatchDetailsCell> createState() => _BatchDetailsCellState();
}

class _BatchDetailsCellState extends State<BatchDetailsCell> {
  OverlayEntry? _overlayEntry;
  Timer? _hideTimer;

  void _showTooltip(Offset globalPosition) {
    if (_overlayEntry != null) return;
    _hideTimer?.cancel();

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final details = widget.entry?.details ?? [];
    if (details.isEmpty) return;

    final children = <Widget>[];
    for (int i = 0; i < details.length; i++) {
      final d = details[i];
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Text('Коробов: ${d.boxesCount}', style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 12),
              Text('× ${d.qtyInBox} шт.', style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 12),
              Text('= ${d.total}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: globalPosition.dx + 20,
        top: globalPosition.dy - 20,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Детали партии:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _hideTooltip() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 200), () {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  void _cancelHide() {
    _hideTimer?.cancel();
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.entry?.total ?? 0;
    if (total == 0) return const SizedBox.shrink();

    return MouseRegion(
      onEnter: (event) {
        _cancelHide();
        _showTooltip(event.position);
      },
      onExit: (_) => _hideTooltip(),
      child: Center(
        child: Text(
          total.toString(),
          style: const TextStyle(fontSize: 13, decoration: TextDecoration.underline),
        ),
      ),
    );
  }
}