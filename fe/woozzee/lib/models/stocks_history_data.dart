import 'dart:convert';
import 'package:intl/intl.dart';

class StocksHistoryData {
  final DateTime createdAt;
  final int totalQuantity;  // Было fbo
  final int fbsQuantity;    // Было fbs
  final int nmId;

  StocksHistoryData({
    required this.createdAt,
    required this.totalQuantity,
    required this.fbsQuantity,
    required this.nmId,
  });

  factory StocksHistoryData.fromJson(Map<String, dynamic> json) {
    // Парсим время как UTC
    final utcTime = DateTime.parse(json['created_at']);

    // Конвертируем UTC в московское время (UTC+3)
    final mskTime = utcTime.add(Duration(hours: 3));

    return StocksHistoryData(
      createdAt: mskTime,  // Сохраняем как московское время
      totalQuantity: json['total_quantity'] ?? 0,
      fbsQuantity: json['fbs_quantity'] ?? 0,
      nmId: json['nm_id'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'created_at': createdAt.toIso8601String(),
      'total_quantity': totalQuantity,  // Исправлено
      'fbs_quantity': fbsQuantity,      // Исправлено
      'nm_id': nmId,
    };
  }
}

class StocksHistoryResponse {
  final List<StocksHistoryData> history;
  final Map<String, dynamic> pagination;
  final Map<String, dynamic> filters;

  StocksHistoryResponse({
    required this.history,
    required this.pagination,
    required this.filters,
  });

  factory StocksHistoryResponse.fromJson(Map<String, dynamic> json) {
    final historyList = (json['history'] as List<dynamic>)
        .map((item) => StocksHistoryData.fromJson(item))
        .toList();

    return StocksHistoryResponse(
      history: historyList,
      pagination: Map<String, dynamic>.from(json['pagination'] ?? {}),
      filters: Map<String, dynamic>.from(json['filters'] ?? {}),
    );
  }
}