// lib/services/counts_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class CountsService {
  static const String baseUrl = 'https://hide_domain.com';

  /// Получить агрегированные данные:
  /// - количество товаров с остатками (любыми, FBO, FBS, без остатков)
  /// - суммы остатков (общая, FBO, FBS)
  Future<Map<String, dynamic>> fetchUnifiedProductsCounts() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/unified-products/counts'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return data;
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Не удалось загрузить статистику: $e');
    }
  }
}