import 'package:http/http.dart' as http;
import 'dart:convert';

class StocksDynamicsPoint {
  final DateTime date;
  final int fboTotal;
  final int fbsTotal;

  StocksDynamicsPoint({required this.date, required this.fboTotal, required this.fbsTotal});

  factory StocksDynamicsPoint.fromJson(Map<String, dynamic> json) {
    return StocksDynamicsPoint(
      date: DateTime.parse(json['date']),
      fboTotal: json['fbo_total'] as int,
      fbsTotal: json['fbs_total'] as int,
    );
  }
}

class StocksDynamicsService {
  static const String baseUrl = 'https://hide_domain.com'; // Замените на реальный адрес сервера

  Future<List<StocksDynamicsPoint>> getDynamics({int days = 31}) async {
    final url = Uri.parse('$baseUrl/stocks/dynamics?days=$days');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => StocksDynamicsPoint.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load stocks dynamics');
    }
  }
}