import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SimpleBarChart extends StatelessWidget {
  final List<double>? values;
  final List<String>? labels;
  final List<DateTime>? dates;
  final int barCount;
  final double barWidth;
  final double maxHeight;
  final Color barColor;
  final void Function(int index)? onBarTap;
  final double minBarHeight;

  const SimpleBarChart({
    Key? key,
    this.values,
    this.labels,
    this.dates,
    this.barCount = 21,
    this.barWidth = 4,
    this.maxHeight = 40,
    this.barColor = Colors.grey,
    this.minBarHeight = 2.0,
    this.onBarTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool hasData = values != null && values!.length == barCount;
    if (!hasData) return const SizedBox.shrink();

    final List<double> chartValues = values!;
    final double maxVal = chartValues.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return const SizedBox.shrink();

    final double minPositive = chartValues
        .where((v) => v > 0)
        .fold<double>(double.infinity, (a, b) => a < b ? a : b);
    final bool allSame = (minPositive == maxVal);

    return Container(
      height: maxHeight,
      alignment: Alignment.bottomCenter,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(barCount, (i) {
          final double value = chartValues[i];
          if (value == 0) return _EmptyBar(width: barWidth);

          double height;
          if (allSame) {
            height = maxHeight;
          } else {
            height = minBarHeight +
                (value - minPositive) / (maxVal - minPositive) *
                    (maxHeight - minBarHeight);
          }

          if (height < 0.1) return _EmptyBar(width: barWidth);

          final label = labels != null && i < labels!.length ? labels![i] : '';
          final dateTime = dates != null && i < dates!.length ? dates![i] : null;

          return _BarWithHover(
            value: value,
            label: label,
            onTap: onBarTap != null ? () => onBarTap!(i) : null,
            dateTime: dateTime,
            width: barWidth,
            height: height,
            baseColor: barColor,
          );
        }),
      ),
    );
  }
}

class _EmptyBar extends StatelessWidget {
  final double width;

  const _EmptyBar({Key? key, required this.width}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, height: 0);
  }
}

class _BarWithHover extends StatefulWidget {
  final double value;
  final String label;
  final DateTime? dateTime;
  final double width;
  final double height;
  final Color baseColor;
  final VoidCallback? onTap;

  const _BarWithHover({
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
  State<_BarWithHover> createState() => _BarWithHoverState();
}

class _BarWithHoverState extends State<_BarWithHover> {
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