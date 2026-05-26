import 'dart:async';
import 'package:flutter/material.dart';

class InTransitCell extends StatefulWidget {
  final int nmId;
  final int totalQuantity;
  final List<Map<String, dynamic>> details;

  const InTransitCell({
    Key? key,
    required this.nmId,
    required this.totalQuantity,
    required this.details,
  }) : super(key: key);

  @override
  State<InTransitCell> createState() => _InTransitCellState();
}

class _InTransitCellState extends State<InTransitCell> {
  OverlayEntry? _overlayEntry;
  Timer? _hideTimer;

  Color _getStatusColor(int statusID) {
    switch (statusID) {
      case 1: return Colors.grey;
      case 2: return Colors.blue;
      case 3: return Colors.orange;
      case 4: return Colors.green;
      case 5: return Colors.black;
      case 6: return Colors.green;
      default: return Colors.grey;
    }
  }

  String _getStatusName(int statusID) {
    switch (statusID) {
      case 1: return 'Не запланировано';
      case 2: return 'Запланировано';
      case 3: return 'Отгрузка разрешена';
      case 4: return 'Идёт приёмка';
      case 5: return 'Принято';
      case 6: return 'Отгружено на воротах';
      default: return 'Статус $statusID';
    }
  }

  void _showDetails(Offset globalPosition) {
    if (_overlayEntry != null) return;
    _hideTimer?.cancel();

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final children = <Widget>[];
    for (var detail in widget.details) {
      final supplyID = detail['supplyID'];
      final statusID = detail['statusID'];
      final quantity = detail['quantity'];
      final statusName = _getStatusName(statusID);
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: Text('Поставка $supplyID', style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: Text('$quantity шт.', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              Text(
                statusName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _getStatusColor(statusID),
                ),
              ),
            ],
          ),
        ),
      );
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: globalPosition.dx + 20,
        top: globalPosition.dy - 50,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 350),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Поставки в пути:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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

  void _hideDetails() {
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
    if (widget.details.isEmpty) {
      return Center(
        child: Text(
          widget.totalQuantity > 0 ? widget.totalQuantity.toString() : '',
          style: const TextStyle(fontSize: 13),
        ),
      );
    }

    return MouseRegion(
      onEnter: (event) {
        _cancelHide();
        _showDetails(event.position);
      },
      onExit: (_) => _hideDetails(),
      child: Center(
        child: Text(
          widget.totalQuantity.toString(),
          style: const TextStyle(fontSize: 13, decoration: TextDecoration.underline),
        ),
      ),
    );
  }
}