import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../utils/color_utils.dart';

class MinimalistChartPainter extends CustomPainter {
  final List<String> labels;
  final List<String> detailedLabels;
  final List<Map<String, dynamic>> datasets;
  final double widgetHeight;
  final double widgetWidth;
  final Offset? hoverPosition;
  final List<DateTime> timestamps;
  final Function(int?, String?) onHover;

  const MinimalistChartPainter({
    required this.labels,
    required this.detailedLabels,
    required this.datasets,
    required this.widgetHeight,
    required this.widgetWidth,
    this.hoverPosition,
    required this.timestamps,
    required this.onHover,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty || datasets.isEmpty) return;

    final width = size.width;
    final height = size.height;
    const padding = 16.0;
    final chartWidth = width - 2 * padding;
    final chartHeight = height - 2 * padding;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    double maxValue = 0;
    for (final dataset in datasets) {
      final List<dynamic> data = dataset['data'] ?? [];
      for (final value in data) {
        if (value is num) {
          final doubleValue = value.toDouble();
          if (doubleValue.isFinite && doubleValue > maxValue) maxValue = doubleValue;
        }
      }
    }
    if (maxValue == 0) maxValue = 10.0;
    else maxValue *= 1.1;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.black.withOpacity(0.1),
    );

    _drawYAxisLabels(canvas, padding, chartHeight, chartWidth, maxValue);

    final gridPaint = Paint()..color = Colors.white.withOpacity(0.15)..strokeWidth = 0.5;
    for (int i = 0; i <= 5; i++) {
      final y = padding + (chartHeight / 5) * i;
      if (y.isFinite) canvas.drawLine(Offset(padding, y), Offset(padding + chartWidth, y), gridPaint);
    }

    if (labels.length > 1) {
      final labelStep = chartWidth / (labels.length - 1);
      for (int i = 0; i < labels.length; i++) {
        final x = padding + labelStep * i;
        if (x.isFinite) canvas.drawLine(Offset(x, padding), Offset(x, padding + chartHeight), gridPaint);
      }
    }

    final axisPaint = Paint()..color = Colors.white.withOpacity(0.3)..strokeWidth = 1.0;
    canvas.drawLine(Offset(padding, padding + chartHeight), Offset(padding + chartWidth, padding + chartHeight), axisPaint);
    canvas.drawLine(Offset(padding, padding), Offset(padding, padding + chartHeight), axisPaint);

    final allPoints = <Map<String, dynamic>>[];

    for (final dataset in datasets) {
      final List<dynamic> data = dataset['data'] ?? [];
      final Color color = hexToColor(dataset['color']?.toString() ?? '#FFFFFF');
      final String datasetLabel = dataset['label']?.toString() ?? '';
      final linePaint = Paint()
        ..color = color.withOpacity(0.8)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final pointPaint = Paint()..color = color..style = PaintingStyle.fill;

      if (data.isNotEmpty) {
        final path = Path();
        final pointSize = 4.0;
        final dataLength = data.length;

        for (int i = 0; i < dataLength; i++) {
          final value = data[i];
          if (value is! num) continue;
          final double yValue = value.toDouble();
          double x = dataLength > 1 ? padding + (chartWidth / (dataLength - 1)) * i : padding + chartWidth / 2;
          double y = padding + chartHeight - (yValue / maxValue) * chartHeight;

          if (x.isFinite && y.isFinite) {
            if (i == 0) path.moveTo(x, y);
            else path.lineTo(x, y);

            allPoints.add({
              'position': Offset(x, y),
              'value': yValue,
              'label': datasetLabel,
              'datasetIndex': datasets.indexOf(dataset),
              'dataIndex': i,
              'color': color,
              'timestamp': i < timestamps.length ? timestamps[i] : null,
            });

            if (dataLength <= 20) canvas.drawCircle(Offset(x, y), pointSize, pointPaint);
          }
        }
        canvas.drawPath(path, linePaint);
      }
    }

    if (hoverPosition != null) {
      _drawTooltip(canvas, hoverPosition!, allPoints, padding, chartWidth, chartHeight);
    }

    _drawXAxisLabels(canvas, padding, chartHeight, chartWidth);
  }

  void _drawTooltip(Canvas canvas, Offset hoverPos, List<Map<String, dynamic>> allPoints,
      double padding, double chartWidth, double chartHeight) {
    Map<String, dynamic>? nearestPoint;
    double minDistance = double.infinity;
    int? nearestDataIndex;
    String? nearestDatasetLabel;

    final pointsByDataset = <int, List<Map<String, dynamic>>>{};
    for (final point in allPoints) {
      final datasetIndex = point['datasetIndex'] as int;
      pointsByDataset.putIfAbsent(datasetIndex, () => []).add(point);
    }

    for (final datasetPoints in pointsByDataset.values) {
      for (final point in datasetPoints) {
        final position = point['position'] as Offset;
        final distance = (hoverPos - position).distance;
        if (distance < minDistance && distance < 30) {
          minDistance = distance;
          nearestPoint = point;
          nearestDatasetLabel = point['label'] as String;
          nearestDataIndex = point['dataIndex'] as int;
        }
      }
    }

    onHover(nearestDataIndex, nearestDatasetLabel);
    if (nearestPoint == null) return;

    final position = nearestPoint['position'] as Offset;
    final value = nearestPoint['value'] as double;
    final label = nearestPoint['label'] as String;
    final color = nearestPoint['color'] as Color;
    final timestamp = nearestPoint['timestamp'] as DateTime?;
    final dataIndex = nearestPoint['dataIndex'] as int;

    String dateTimeStr = '';
    if (timestamp != null) {
      const months = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
      dateTimeStr = '${timestamp.day} ${months[timestamp.month - 1]}\n${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (dataIndex < detailedLabels.length) {
      dateTimeStr = detailedLabels[dataIndex];
    }

    final tooltipText = '$label: $value\n$dateTimeStr';
    final textLines = tooltipText.split('\n');
    const textStyle = TextStyle(color: Colors.white, fontSize: 12);
    final textPainters = <TextPainter>[];
    double totalHeight = 0;
    double maxWidth = 0;

    for (final line in textLines) {
      final tp = TextPainter(text: TextSpan(text: line, style: textStyle), textDirection: TextDirection.ltr);
      tp.layout();
      textPainters.add(tp);
      totalHeight += tp.height + 2;
      maxWidth = math.max(maxWidth, tp.width);
    }

    const tooltipPadding = 8.0;
    final tooltipWidth = maxWidth + tooltipPadding * 2;
    final tooltipHeight = totalHeight + tooltipPadding * 2;

    double tooltipX = position.dx + 10;
    double tooltipY = position.dy - tooltipHeight - 10;
    if (tooltipX + tooltipWidth > padding + chartWidth) tooltipX = position.dx - tooltipWidth - 10;
    if (tooltipY < padding) tooltipY = position.dy + 10;

    final tooltipRect = Rect.fromLTWH(tooltipX, tooltipY, tooltipWidth, tooltipHeight);
    canvas.drawRRect(RRect.fromRectAndRadius(tooltipRect, const Radius.circular(4)),
        Paint()..color = Colors.black.withOpacity(0.8)..style = PaintingStyle.fill);
    canvas.drawRRect(RRect.fromRectAndRadius(tooltipRect, const Radius.circular(4)),
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.0);

    double currentY = tooltipY + tooltipPadding;
    for (final tp in textPainters) {
      tp.paint(canvas, Offset(tooltipX + tooltipPadding, currentY));
      currentY += tp.height + 2;
    }

    canvas.drawLine(Offset(position.dx, position.dy), Offset(tooltipX + tooltipWidth / 2, tooltipY + tooltipHeight),
        Paint()..color = color..strokeWidth = 1.0);
  }

  void _drawXAxisLabels(Canvas canvas, double padding, double chartHeight, double chartWidth) {
    if (labels.isEmpty) return;
    const textStyle = TextStyle(color: Colors.white, fontSize: 10);
    int step = 1;
    if (labels.length > 10) step = (labels.length / 5).ceil();

    for (int i = 0; i < labels.length; i += step) {
      double x = labels.length > 1 ? padding + (chartWidth / (labels.length - 1)) * i : padding + chartWidth / 2;
      String detailedLabel = i < detailedLabels.length ? detailedLabels[i] : '${labels[i]}\n00:00';
      final lines = detailedLabel.split('\n');
      if (lines.length >= 2) {
        final tp1 = TextPainter(text: TextSpan(text: lines[0], style: textStyle), textDirection: TextDirection.ltr);
        tp1.layout();
        tp1.paint(canvas, Offset(x - tp1.width / 2, padding + chartHeight + 5));
        final tp2 = TextPainter(text: TextSpan(text: lines[1], style: textStyle), textDirection: TextDirection.ltr);
        tp2.layout();
        tp2.paint(canvas, Offset(x - tp2.width / 2, padding + chartHeight + 5 + tp1.height));
      }
    }
  }

  void _drawYAxisLabels(Canvas canvas, double padding, double chartHeight, double chartWidth, double maxValue) {
    const textStyle = TextStyle(color: Colors.white, fontSize: 10);
    for (int i = 0; i <= 5; i++) {
      final value = (maxValue / 5) * i;
      final y = padding + chartHeight - (value / maxValue) * chartHeight;
      String label = maxValue < 1000 ? value.round().toString() : '${(value / 1000).toStringAsFixed(1)}k';
      final tp = TextPainter(text: TextSpan(text: label, style: textStyle), textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(padding - tp.width - 5, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}