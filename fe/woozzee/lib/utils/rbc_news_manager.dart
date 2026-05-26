// utils/rbc_news_manager.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';

class RbcNewsItem {
  final String id;
  final String title;
  final String body;          // краткое описание (lead) из API
  final String url;
  final String imageUrl;
  final DateTime date;

  RbcNewsItem({
    required this.id,
    required this.title,
    required this.body,
    required this.url,
    required this.imageUrl,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'url': url,
    'imageUrl': imageUrl,
    'date': date.toIso8601String(),
  };

  factory RbcNewsItem.fromJson(Map<String, dynamic> json) {
    return RbcNewsItem(
      id: json['id'],
      title: json['title'],
      body: json['body'] ?? '',
      url: json['url'],
      imageUrl: json['imageUrl'] ?? '',
      date: DateTime.parse(json['date']),
    );
  }
}

class RbcNewsManager extends ChangeNotifier {
  static final RbcNewsManager _instance = RbcNewsManager._internal();
  factory RbcNewsManager() => _instance;
  RbcNewsManager._internal();

  List<RbcNewsItem> _news = [];
  Set<String> _archivedIds = {};   // Хранилище ID прочитанных новостей
  bool _isLoading = false;
  bool _isInitialized = false;

  List<RbcNewsItem> get news => List.unmodifiable(_news);
  bool get isLoading => _isLoading;

  // ----------------------------------------------------------------------
  // Инициализация и загрузка кэша
  // ----------------------------------------------------------------------
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _loadArchivedIds();        // сначала архив
    await _loadCachedNews();         // потом кэш (с учётом архива)
    _isInitialized = true;
    refreshNews();                   // обновим из API
  }

  Future<void> _loadArchivedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final archived = prefs.getStringList('rbc_archived_ids');
      if (archived != null) {
        _archivedIds = archived.toSet();
        debugPrint('Загружено ${_archivedIds.length} архивных ID РБК');
      }
    } catch (e) {
      debugPrint('Ошибка загрузки архива РБК: $e');
    }
  }

  Future<void> _saveArchivedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('rbc_archived_ids', _archivedIds.toList());
    } catch (e) {
      debugPrint('Ошибка сохранения архива РБК: $e');
    }
  }

  Future<void> _loadCachedNews() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('rbc_news');
      if (cached != null && cached.isNotEmpty) {
        final List<dynamic> decoded = json.decode(cached);
        final allNews = decoded.map((item) => RbcNewsItem.fromJson(item)).toList();
        // Удаляем те, что в архиве
        _news = allNews.where((item) => !_archivedIds.contains(item.id)).toList();
        notifyListeners();
        debugPrint('Загружено ${_news.length} новостей РБК из кэша (${allNews.length - _news.length} архивных пропущено)');
      }
    } catch (e) {
      debugPrint('Ошибка загрузки кэша РБК: $e');
    }
  }

  Future<void> _saveNewsToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode(_news.map((n) => n.toJson()).toList());
      await prefs.setString('rbc_news', encoded);
    } catch (e) {
      debugPrint('Ошибка сохранения новостей РБК в кэш: $e');
    }
  }

  // ----------------------------------------------------------------------
  // Архивация новости (ознакомлен)
  // ----------------------------------------------------------------------
  Future<void> archiveNews(String newsId) async {
    if (_archivedIds.contains(newsId)) return;
    _archivedIds.add(newsId);
    _news.removeWhere((item) => item.id == newsId);
    await _saveArchivedIds();
    await _saveNewsToCache();
    notifyListeners();
    debugPrint('Новость РБК $newsId архивирована');
  }

  // ----------------------------------------------------------------------
  // Обновление из API
  // ----------------------------------------------------------------------
  Future<void> refreshNews() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      final fetchedNews = await _fetchRbcNewsApi();
      if (fetchedNews.isNotEmpty) {
        // Фильтруем архивные
        final filtered = fetchedNews.where((item) => !_archivedIds.contains(item.id)).toList();
        _news = filtered;
        await _saveNewsToCache();
        notifyListeners();
        debugPrint('Сохранено ${_news.length} новостей РБК из API (${fetchedNews.length - _news.length} архивных пропущено)');
      } else {
        debugPrint('API не вернул новости');
      }
    } catch (e) {
      debugPrint('Ошибка при получении новостей РБК: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Запрос к AJAX API РБК (список новостей)
  Future<List<RbcNewsItem>> _fetchRbcNewsApi() async {
    const apiUrl = 'https://www.rbc.ru/search/ajax/?project=rbcnews&tag=Wildberries&page=0';
    debugPrint('Загрузка новостей через API: $apiUrl');

    final response = await http.get(
      Uri.parse(apiUrl),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.rbc.ru/tags?tag=Wildberries',
      },
    );

    if (response.statusCode != 200) {
      debugPrint('Ошибка API: ${response.statusCode}');
      return [];
    }

    final Map<String, dynamic> data = json.decode(response.body);
    final List<dynamic> items = data['items'] ?? [];

    final List<RbcNewsItem> news = [];
    for (final item in items) {
      final id = item['id'] as String?;
      final title = item['title'] as String?;
      final body = item['body'] as String? ?? '';
      final url = item['fronturl'] as String?;
      final imageUrl = item['picture'] as String? ?? '';
      final publishDateStr = item['publish_date'] as String?;

      if (id == null || title == null || url == null) continue;

      DateTime date;
      try {
        date = DateTime.parse(publishDateStr!);
      } catch (e) {
        date = DateTime.now();
      }

      news.add(RbcNewsItem(
        id: id,
        title: title,
        body: body,
        url: url,
        imageUrl: imageUrl,
        date: date,
      ));
    }

    news.sort((a, b) => b.date.compareTo(a.date));
    debugPrint('Получено ${news.length} новостей по тегу Wildberries');
    return news;
  }

  /// Загружает полный текст статьи по URL
  /// Возвращает строку, содержащую описание (lead) и все параграфы (body)
  Future<String?> fetchFullArticleContent(String url) async {
    debugPrint('Загрузка полного текста статьи: $url');
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.rbc.ru/tags?tag=Wildberries',
        },
      );

      if (response.statusCode != 200) {
        debugPrint('Ошибка загрузки статьи: ${response.statusCode}');
        return null;
      }

      final document = parser.parse(response.body);

      // 1. Ищем lead (описание) — стиль может отличаться на разных страницах
      String lead = '';
      final leadElement = document.querySelector('.styles_lead__ttwoP p') ??
          document.querySelector('.article__lead p') ??
          document.querySelector('[itemprop="description"]');
      if (leadElement != null) {
        lead = leadElement.text.trim();
      }

      // 2. Ищем все параграфы статьи
      final paragraphs = <String>[];
      final paragraphElements = document.querySelectorAll('p.paragraph');
      for (final p in paragraphElements) {
        final text = p.text.trim();
        if (text.isNotEmpty) {
          paragraphs.add(text);
        }
      }

      // Если не нашли параграфов с классом .paragraph, пробуем любые p внутри основного контейнера статьи
      if (paragraphs.isEmpty) {
        final container = document.querySelector('div[data-metronome-unit="article"]');
        if (container != null) {
          final allParagraphs = container.querySelectorAll('p');
          for (final p in allParagraphs) {
            final text = p.text.trim();
            if (text.isNotEmpty && !text.contains(lead)) {
              paragraphs.add(text);
            }
          }
        }
      }

      // 3. Собираем полный текст: lead + все параграфы
      final fullText = StringBuffer();
      if (lead.isNotEmpty) {
        fullText.writeln(lead);
        fullText.writeln();
      }
      for (final p in paragraphs) {
        fullText.writeln(p);
        fullText.writeln();
      }

      final result = fullText.toString().trim();
      if (result.isEmpty) {
        debugPrint('Не удалось извлечь текст статьи (пусто)');
        return null;
      }
      debugPrint('Извлечено символов: ${result.length}');
      return result;
    } catch (e) {
      debugPrint('Ошибка при парсинге статьи: $e');
      return null;
    }
  }

  List<RbcNewsItem> getLatestNews(int count) {
    return _news.take(count).toList();
  }
}