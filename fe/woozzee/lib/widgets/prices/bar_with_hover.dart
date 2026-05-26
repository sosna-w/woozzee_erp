import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BarWithHover extends StatefulWidget {
  final double value;
  final String label;
  final DateTime? dateTime;
  final double width;
  final double height;
  final Color baseColor;
  final VoidCallback? onTap;

  const BarWithHover({
    Key? key,
    required this.value,
    required this.label,
    this.dateTime,
    required this.width,
    required this.height,
    required this.baseColor,
    this.onTap,
  }) : super(key: key);

  @override
  State<BarWithHover> createState() => _BarWithHoverState();
}

class _BarWithHoverState extends State<BarWithHover> {
  bool _isHovering = false;
  OverlayEntry? _overlayEntry;
  Timer? _hideTimer;

  String _getFormattedDate() {
    if (widget.dateTime == null) return widget.label;
    final date = DateTime(widget.dateTime!.year, widget.dateTime!.month, widget.dateTime!.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final formatter = DateFormat('d MMMM', 'ru');
    final dateStr = formatter.format(date);
    String weekdayStr;
    if (date == today) {
      weekdayStr = 'сегодня';
    } else if (date == yesterday) {
      weekdayStr = 'вчера';
    } else {
      weekdayStr = DateFormat('EEEE', 'ru').format(date).toLowerCase();
    }
    return '$dateStr\n$weekdayStr';
  }

  void _showCustomTooltip(Offset globalPosition) {
    if (_overlayEntry != null) return;
    _hideTimer?.cancel();

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final quantity = widget.value.toInt();

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: globalPosition.dx + 15,
        top: globalPosition.dy + 20,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_getFormattedDate(), style: const TextStyle(fontSize: 12, color: Colors.black87)),
                const SizedBox(height: 4),
                Text(quantity.toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange)),
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _hideCustomTooltip() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 100), () {
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
    return MouseRegion(
      onEnter: (event) {
        setState(() => _isHovering = true);
        _cancelHide();
        _showCustomTooltip(event.position);
      },
      onExit: (_) {
        setState(() => _isHovering = false);
        _hideCustomTooltip();
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: _isHovering ? Colors.orange : widget.baseColor.withOpacity(widget.value > 0 ? 0.7 : 0.2),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}