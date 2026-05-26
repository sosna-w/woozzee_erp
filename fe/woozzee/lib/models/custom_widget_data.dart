import 'package:flutter/material.dart';
import 'dart:convert';

class CustomWidgetData {
  final String id;
  bool isTitleVisible = true;
  final GlobalKey widgetKey = GlobalKey();
  bool isFirstColumnVisible = true;
  String chartDataType = 'stocks_history';
  String chartPeriod = '30_days';
  DateTime? chartDateFrom;
  DateTime? chartDateTo;
  bool showFBO = true;
  bool showFBS = true;

  double leftPercent;
  double topPercent;
  double widthPercent;
  double heightPercent;
  double baseRowHeight = 48.0;
  int baseRowCount = 1;

  static const double leftWidgetPadding = 120.0;

  double left = 0;
  double top = 0;
  double width = 0;
  double height = 0;

  bool isEditing;
  bool isResizing = false;
  String resizeDirection = '';
  bool isFixedLayer = false;

  static const double gridSize = 8.0;
  static const double magnetThreshold = 10.0;
  static const double widgetPadding = 16.0;
  static const double widgetSpacing = 12.0;

  String widgetType;
  String widgetTitle;
  bool isTitleEditing;

  Map<int, String> tableAttributes = {};
  List<double> tableColumnWidths = [0.4, 0.6];

  CustomWidgetData({
    required this.id,
    required this.leftPercent,
    required this.topPercent,
    required this.widthPercent,
    required this.heightPercent,
    this.isEditing = false,
    this.isFixedLayer = false,
    this.widgetType = 'table',
    this.widgetTitle = 'Новый виджет',
    this.isTitleEditing = false,
    this.isTitleVisible = true,
    this.chartDataType = 'stocks_history',
    this.chartPeriod = '30_days',
    this.chartDateFrom,
    this.chartDateTo,
    this.showFBO = true,
    this.showFBS = true,
    this.isFirstColumnVisible = true,
    Map<int, String>? tableAttributes,
    List<double>? tableColumnWidths,
  }) {
    this.tableAttributes = tableAttributes ?? {};
    this.tableColumnWidths = tableColumnWidths ?? [0.4, 0.6];
    if (chartPeriod != 'custom') {
      final days = _getDaysForPeriod(chartPeriod);
      if (days != null) {
        chartDateTo = DateTime.now();
        chartDateFrom = chartDateTo!.subtract(Duration(days: days));
      }
    }
  }

  int? _getDaysForPeriod(String period) {
    const periodDays = {'7_days': 7, '30_days': 30, '90_days': 90};
    return periodDays[period];
  }

  double calculateRequiredHeight() {
    const headerHeight = 40.0;
    const verticalPadding = 16.0;
    if (widgetType == 'table') {
      return headerHeight + verticalPadding + (tableAttributes.length * baseRowHeight);
    }
    return height;
  }

  void addTableRow() {
    if (widgetType == 'table') {
      final nextIndex = tableAttributes.length;
      tableAttributes[nextIndex] = '';
    }
  }

  void removeTableRow(int rowIndex) {
    if (widgetType == 'table' && tableAttributes.containsKey(rowIndex)) {
      final Map<int, String> newAttributes = {};
      int newIndex = 0;
      for (int i = 0; i < tableAttributes.length; i++) {
        if (i != rowIndex) {
          newAttributes[newIndex] = tableAttributes[i]!;
          newIndex++;
        }
      }
      tableAttributes = newAttributes;
    }
  }

  void updateAbsoluteValues(double availableWidth, double screenHeight, double containerHeight) {
    final heightReference = isFixedLayer ? screenHeight : containerHeight;
    width = widthPercent * availableWidth;
    height = heightPercent * heightReference;

    const minWidth = 100.0;
    const minHeight = 80.0;
    const maxWidthRatio = 0.95;
    const maxHeightRatio = 0.95;

    width = width.clamp(minWidth, availableWidth * maxWidthRatio);
    height = height.clamp(minHeight, heightReference * maxHeightRatio);

    left = leftPercent * availableWidth;
    top = topPercent * heightReference;

    leftPercent = left / availableWidth;
    topPercent = top / heightReference;
    widthPercent = width / availableWidth;
    heightPercent = height / heightReference;
  }

  CustomWidgetData copy() => CustomWidgetData(
    id: id,
    leftPercent: leftPercent,
    topPercent: topPercent,
    widthPercent: widthPercent,
    heightPercent: heightPercent,
    isEditing: isEditing,
    isFixedLayer: isFixedLayer,
    widgetType: widgetType,
    widgetTitle: widgetTitle,
    isTitleEditing: isTitleEditing,
    isFirstColumnVisible: isFirstColumnVisible,
    tableAttributes: Map<int, String>.from(tableAttributes),
    tableColumnWidths: List<double>.from(tableColumnWidths),
  );

  Rect get rect => Rect.fromLTWH(left, top, width, height);

  bool intersects(CustomWidgetData other) => rect.overlaps(other.rect);

  bool containsPoint(Offset point) => rect.contains(point);

  double snapToGrid(double value) => (value / gridSize).roundToDouble() * gridSize;

  void applyMagneticSnap(List<CustomWidgetData> allWidgets, double availableWidth, double heightReference) {
    final minLeft = leftWidgetPadding;
    final maxLeft = availableWidth - width - widgetPadding;
    final minTop = widgetPadding;
    final maxTop = heightReference - height - widgetPadding;

    left = left.clamp(minLeft, maxLeft);
    top = top.clamp(minTop, maxTop);

    left = snapToGrid(left);
    top = snapToGrid(top);

    for (var other in allWidgets) {
      if (other.id != id) {
        if ((top + height - other.top).abs() < magnetThreshold) {
          top = other.top - height - widgetSpacing;
        }
        if ((top - (other.top + other.height)).abs() < magnetThreshold) {
          top = other.top + other.height + widgetSpacing;
        }
        if ((left - other.left).abs() < magnetThreshold) {
          left = other.left;
        }
        if ((left + width - (other.left + other.width)).abs() < magnetThreshold) {
          left = other.left + other.width - width;
        }
      }
    }

    leftPercent = left / availableWidth;
    topPercent = top / heightReference;
  }

  Map<String, dynamic> toJson() {
    final json = {
      'id': id,
      'leftPercent': leftPercent,
      'topPercent': topPercent,
      'widthPercent': widthPercent,
      'heightPercent': heightPercent,
      'isFixedLayer': isFixedLayer,
      'widgetType': widgetType,
      'widgetTitle': widgetTitle,
      'isTitleVisible': isTitleVisible,
      'isFirstColumnVisible': isFirstColumnVisible,
      'chartDataType': chartDataType,
      'chartPeriod': chartPeriod,
      'chartDateFrom': chartDateFrom?.toIso8601String(),
      'chartDateTo': chartDateTo?.toIso8601String(),
      'showFBO': showFBO,
      'showFBS': showFBS,
    };

    if (widgetType == 'table') {
      json['tableAttributes'] = tableAttributes.map((key, value) => MapEntry(key.toString(), value));
      json['tableColumnWidths'] = tableColumnWidths;
    }

    return json;
  }

  factory CustomWidgetData.fromJson(Map<String, dynamic> json) {
    final widget = CustomWidgetData(
      id: json['id'],
      leftPercent: (json['leftPercent'] as num).toDouble(),
      topPercent: (json['topPercent'] as num).toDouble(),
      widthPercent: (json['widthPercent'] as num).toDouble(),
      heightPercent: (json['heightPercent'] as num).toDouble(),
      isEditing: false,
      isFixedLayer: json['isFixedLayer'] ?? false,
      widgetType: json['widgetType'] ?? 'table',
      widgetTitle: json['widgetTitle'] ?? 'Новый виджет',
      isTitleVisible: json['isTitleVisible'] ?? true,
      isFirstColumnVisible: json['isFirstColumnVisible'] ?? true,
      chartDataType: json['chartDataType'] ?? 'stocks_history',
      chartPeriod: json['chartPeriod'] ?? '30_days',
      chartDateFrom: json['chartDateFrom'] != null ? DateTime.parse(json['chartDateFrom']) : null,
      chartDateTo: json['chartDateTo'] != null ? DateTime.parse(json['chartDateTo']) : null,
      showFBO: json['showFBO'] ?? true,
      showFBS: json['showFBS'] ?? true,
    );

    if (widget.widgetType == 'table') {
      try {
        final attributesJson = json['tableAttributes'] as Map<String, dynamic>?;
        if (attributesJson != null) {
          widget.tableAttributes = attributesJson.map((key, value) => MapEntry(int.parse(key), value.toString()));
        }
        final columnWidthsJson = json['tableColumnWidths'] as List<dynamic>?;
        if (columnWidthsJson != null) {
          widget.tableColumnWidths = columnWidthsJson.map((e) => (e as num).toDouble()).toList();
        }
      } catch (e) {
        widget.tableAttributes = {};
        widget.tableColumnWidths = [0.4, 0.6];
      }
    }

    return widget;
  }
}