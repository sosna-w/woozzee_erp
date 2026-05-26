import 'dart:convert';
import 'package:http/http.dart' as http;

class TagManager {
  static final TagManager _instance = TagManager._internal();
  factory TagManager() => _instance;
  TagManager._internal();

  List<String> _tags = [];
  bool _isLoading = false;

  List<String> get tags => _tags;
  bool get isLoading => _isLoading;

  Future<void> loadTags() async {
    if (_isLoading) return;

    _isLoading = true;

    try {
      final response = await http.get(
        Uri.parse('https://hide_domain.com/tags'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        _tags = data.map<String>((tag) => tag['name']?.toString() ?? '').where((name) => name.isNotEmpty).toList();
      }
    } catch (e) {
      print('Error loading tags: $e');
      _tags = [];
    } finally {
      _isLoading = false;
    }
  }

  List<String> getTagNames() {
    return _tags;
  }

  void clearTags() {
    _tags = [];
  }
}