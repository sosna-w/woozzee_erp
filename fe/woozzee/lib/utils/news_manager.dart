// news_manager.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'token_manager.dart';

class NewsItem {
  final int id;
  final String header;
  final String content;
  final DateTime date;
  final List<Map<String, dynamic>> types;

  NewsItem({
    required this.id,
    required this.header,
    required this.content,
    required this.date,
    required this.types,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'header': header,
    'content': content,
    'date': date.toIso8601String(),
    'types': types,
  };

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    return NewsItem(
      id: json['id'],
      header: json['header'],
      content: json['content'],
      date: DateTime.parse(json['date']),
      types: List<Map<String, dynamic>>.from(json['types'] ?? []),
    );
  }
}

class NewsManager extends ChangeNotifier {
  static final NewsManager _instance = NewsManager._internal();
  factory NewsManager() => _instance;
  NewsManager._internal();

  List<NewsItem> _news = [];
  Set<int> _archivedIds = {};
  bool _isLoading = false;
  bool _isInitialized = false;

  List<NewsItem> get news => List.unmodifiable(_news);
  bool get isLoading => _isLoading;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _loadCachedNews();
    await _loadArchivedIds();
    _isInitialized = true;
    refreshNews();
  }

  Future<void> _loadCachedNews() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_news');
      if (cached != null && cached.isNotEmpty) {
        final List<dynamic> decoded = json.decode(cached);
        final allNews = decoded.map((item) => NewsItem.fromJson(item)).toList();
        _news = allNews.where((n) => !_archivedIds.contains(n.id)).toList();
        notifyListeners();
        debugPrint('Загружено ${_news.length} новостей из кэша');
      }
    } catch (e) {
      debugPrint('Ошибка загрузки кэша новостей: $e');
    }
  }

  Future<void> _saveNewsToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode(_news.map((n) => n.toJson()).toList());
      await prefs.setString('cached_news', encoded);
    } catch (e) {
      debugPrint('Ошибка сохранения новостей в кэш: $e');
    }
  }

  Future<void> _loadArchivedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final archived = prefs.getStringList('archived_news_ids');
      if (archived != null) {
        _archivedIds = archived.map(int.parse).toSet();
      }
    } catch (e) {
      debugPrint('Ошибка загрузки архива: $e');
    }
  }

  Future<void> _saveArchivedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _archivedIds.map((id) => id.toString()).toList();
      await prefs.setStringList('archived_news_ids', list);
    } catch (e) {
      debugPrint('Ошибка сохранения архива: $e');
    }
  }

  Future<void> refreshNews() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      final token = await TokenManager().getToken();
      if (token == null || token.isEmpty) {
        debugPrint('Нет токена для запроса новостей');
        return;
      }

      // За последние 7 дней
      final fromDate = DateTime.now().subtract(const Duration(days: 7));
      final fromParam = fromDate.toIso8601String().split('T').first;
      final url = Uri.parse('https://common-api.wildberries.ru/api/communications/v2/news?from=$fromParam');

      final response = await http.get(
        url,
        headers: {
          'Authorization': token,
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        final List<dynamic> data = responseData['data'] ?? [];
        final List<NewsItem> fetchedNews = data.map((item) => NewsItem.fromJson(item)).toList();

        // Добавляем только те новости, которых ещё нет в списке и нет в архиве
        final existingIds = _news.map((n) => n.id).toSet();
        for (final newItem in fetchedNews) {
          if (!existingIds.contains(newItem.id) && !_archivedIds.contains(newItem.id)) {
            _news.add(newItem);
          }
        }

        _news.sort((a, b) => b.date.compareTo(a.date));
        await _saveNewsToCache();
        notifyListeners();
        debugPrint('Получено ${fetchedNews.length} новостей, добавлено ${_news.length}');
      } else {
        debugPrint('Ошибка загрузки новостей: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Исключение при загрузке новостей: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Навсегда скрыть новость (отметить "Ознакомлен")
  Future<void> archiveNews(int newsId) async {
    if (_archivedIds.contains(newsId)) return;
    _archivedIds.add(newsId);
    _news.removeWhere((n) => n.id == newsId);
    await _saveArchivedIds();
    await _saveNewsToCache();
    notifyListeners();
  }

  List<NewsItem> getLatestNews(int count) {
    return _news.take(count).toList();
  }
}