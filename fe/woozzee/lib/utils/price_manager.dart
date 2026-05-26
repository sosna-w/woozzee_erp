import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'token_manager.dart';

class PriceManager {
  static final PriceManager _instance = PriceManager._internal();
  factory PriceManager() => _instance;
  PriceManager._internal();

  String? _wbApiToken;
  final Map<int, Map<String, dynamic>> _priceCache = {}; // nmID -> {chrtID: {price, discount, clubDiscount}}
  final Map<String, Map<String, dynamic>> _pendingChanges = {}; // key: '${nmID}_${chrtID}' -> {price?, discount?, clubDiscount?}

  Future<void> init() async {
    final token = await TokenManager().getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Токен WB не получен');
    }
    _wbApiToken = token;
  }

  // ==========================================================================
  // ОПТИМИЗИРОВАННАЯ ЗАГРУЗКА ВСЕХ ЦЕН (ПАКЕТНАЯ ПАРАЛЛЕЛЬНО, С УЧЁТОМ RATE-LIMIT)
  // ==========================================================================

  /// Загрузить цены и скидки для всех товаров (пакетами по 5 страниц, с retry при 429)
  Future<void> loadAllPrices() async {
    final totalStart = DateTime.now();
    print('[PRICE DEBUG] ⏳ loadAllPrices START');

    if (_wbApiToken == null) await init();
    const limit = 1000;

    // Загружаем первую страницу
    final firstPage = await _fetchPageWithRetry(offset: 0, limit: limit);
    if (firstPage == null) {
      throw Exception('Не удалось загрузить первую страницу цен');
    }
    _processGoodsList(firstPage);

    // Если первая страница неполная, больше данных нет
    if (firstPage.length < limit) {
      print('[PRICE DEBUG] ✅ Всего одна страница, загрузка завершена');
      return;
    }

    // Пакетная загрузка остальных страниц (burst = 5, загружаем по 5 страниц одновременно)
    int nextOffset = limit;
    bool hasMore = true;
    const int maxConcurrent = 5; // максимальное количество параллельных запросов

    while (hasMore) {
      // Формируем пакет из maxConcurrent запросов
      final List<Future<List<dynamic>?>> batchFutures = [];
      for (int i = 0; i < maxConcurrent && hasMore; i++) {
        final offset = nextOffset;
        nextOffset += limit;
        final future = _fetchPageWithRetry(offset: offset, limit: limit).then((goodsList) {
          if (goodsList != null && goodsList.isEmpty) {
            hasMore = false; // пустая страница – конец, но остальные запросы в пакете всё равно выполнятся
          }
          return goodsList;
        });
        batchFutures.add(future);
      }

      // Ждём завершения всего пакета
      final results = await Future.wait(batchFutures);
      for (var goodsList in results) {
        if (goodsList != null && goodsList.isNotEmpty) {
          _processGoodsList(goodsList);
        } else if (goodsList != null && goodsList.isEmpty) {
          hasMore = false; // на случай, если ещё не установлено
        }
      }
    }

    final totalMs = DateTime.now().difference(totalStart).inMilliseconds;
    print('[PRICE DEBUG] 🏁 loadAllPrices FINISHED за ${totalMs}ms');
  }

  /// Выполняет один запрос страницы с обработкой rate-limit (заголовки 429)
  Future<List<dynamic>?> _fetchPageWithRetry({
    required int offset,
    required int limit,
    int retryCount = 0,
  }) async {
    const int maxRetries = 5;
    try {
      final uri = Uri.parse(
          'https://discounts-prices-api.wildberries.ru/api/v2/list/goods/filter?limit=$limit&offset=$offset');
      final response = await http.get(
        uri,
        headers: {'Authorization': _wbApiToken!, 'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final listGoods = data['data']['listGoods'] as List<dynamic>;
        // Логируем оставшийся burst для отладки
        final remainingHeader = response.headers['x-ratelimit-remaining'];
        if (remainingHeader != null) {
          final remaining = int.tryParse(remainingHeader);
          if (remaining == 0) {
            print('[RATE LIMIT] burst исчерпан для offset=$offset, следующие запросы могут требовать паузы');
          }
        }
        return listGoods;
      } else if (response.statusCode == 429) {
        // Too Many Requests – используем заголовок X-Ratelimit-Retry
        final retryAfterHeader = response.headers['x-ratelimit-retry'];
        int waitSeconds = 1;
        if (retryAfterHeader != null) {
          waitSeconds = int.tryParse(retryAfterHeader) ?? 1;
        }
        print('[RATE LIMIT] 429 для offset=$offset, ждём ${waitSeconds}с, попытка ${retryCount + 1}/$maxRetries');
        if (retryCount >= maxRetries) return null;
        await Future.delayed(Duration(seconds: waitSeconds));
        return _fetchPageWithRetry(offset: offset, limit: limit, retryCount: retryCount + 1);
      } else {
        print('[PRICE DEBUG] Ошибка HTTP ${response.statusCode} для offset=$offset, ответ: ${response.body}');
        return null;
      }
    } catch (e) {
      print('[PRICE DEBUG] Исключение при offset=$offset: $e');
      if (retryCount >= maxRetries) return null;
      // Экспоненциальная задержка: 1, 2, 4, 8, 16 секунд
      await Future.delayed(Duration(seconds: 1 << retryCount));
      return _fetchPageWithRetry(offset: offset, limit: limit, retryCount: retryCount + 1);
    }
  }

  /// Обрабатывает список товаров, складывая в _priceCache
  void _processGoodsList(List<dynamic> listGoods) {
    for (var goods in listGoods) {
      final nmID = goods['nmID'] as int;
      final discount = goods['discount'] ?? 0;
      final clubDiscount = goods['clubDiscount'] ?? 0;
      final sizes = goods['sizes'] as List<dynamic>;
      for (var size in sizes) {
        final chrtID = size['sizeID'] as int;
        final price = size['price'] as int;
        _priceCache[nmID] ??= {};
        _priceCache[nmID]![chrtID.toString()] = {
          'price': price,
          'discount': discount,
          'clubDiscount': clubDiscount,
        };
      }
    }
  }

  // ==========================================================================
  // ОСТАЛЬНЫЕ МЕТОДЫ (БЕЗ ИЗМЕНЕНИЙ)
  // ==========================================================================

  /// Получить текущую цену/скидку для позиции
  Map<String, dynamic>? getPrices(int nmID, int chrtID) {
    return _priceCache[nmID]?[chrtID.toString()];
  }

  Future<String?> getWbApiToken() async {
    final tokenManager = TokenManager();
    await tokenManager.initialize();
    return tokenManager.token;
  }

  /// Обновить цену и/или скидку (отправка на сервер)
  Future<void> updatePriceAndDiscount(int nmID, {int? price, int? discount}) async {
    if (_wbApiToken == null) await init();
    final body = {
      'data': [
        {
          'nmID': nmID,
          if (price != null) 'price': price,
          if (discount != null) 'discount': discount,
        }
      ]
    };
    final response = await http.post(
      Uri.parse('https://discounts-prices-api.wildberries.ru/api/v2/upload/task'),
      headers: {'Authorization': _wbApiToken!, 'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    _handleResponse(response);
    // после успеха обновляем кэш
    if (response.statusCode == 200 || response.statusCode == 208) {
      final cached = _priceCache[nmID];
      if (cached != null) {
        for (var entry in cached.entries) {
          if (price != null) entry.value['price'] = price;
          if (discount != null) entry.value['discount'] = discount;
        }
      }
    }
  }

  /// Обновить скидку WB Клуба
  Future<void> updateClubDiscount(int nmID, int clubDiscount) async {
    if (_wbApiToken == null) await init();
    final response = await http.post(
      Uri.parse('https://discounts-prices-api.wildberries.ru/api/v2/upload/task/club-discount'),
      headers: {'Authorization': _wbApiToken!, 'Content-Type': 'application/json'},
      body: json.encode({'data': [{'nmID': nmID, 'clubDiscount': clubDiscount}]}),
    );
    _handleResponse(response);
    if (response.statusCode == 200 || response.statusCode == 208) {
      final cached = _priceCache[nmID];
      if (cached != null) {
        for (var entry in cached.entries) {
          entry.value['clubDiscount'] = clubDiscount;
        }
      }
    }
  }

  void _handleResponse(http.Response response) {
    if (response.statusCode != 200 && response.statusCode != 208) {
      final error = json.decode(response.body)['errorText'] ?? 'Неизвестная ошибка';
      throw Exception(_translateError(error));
    }
  }

  String _translateError(String eng) {
    if (eng.contains('discounts in the file are the same')) return 'Скидки уже установлены';
    if (eng.contains('prices in the file are the same')) return 'Цены уже установлены';
    if (eng.contains('discount value is too high')) return 'Скидка не может быть больше 100%';
    return eng;
  }

  // ---- Методы для массовой отправки ----
  void addPendingChange(int nmID, int chrtID, {int? price, int? discount, int? clubDiscount}) {
    final key = _makeKey(nmID, chrtID);
    _pendingChanges.putIfAbsent(key, () => {'nmID': nmID, 'chrtID': chrtID});
    if (price != null) _pendingChanges[key]!['price'] = price;
    if (discount != null) _pendingChanges[key]!['discount'] = discount;
    if (clubDiscount != null) _pendingChanges[key]!['clubDiscount'] = clubDiscount;
  }

  void clearPending() => _pendingChanges.clear();

  Map<String, Map<String, dynamic>> get pendingChanges => Map.unmodifiable(_pendingChanges);

  Future<void> sendAllChanges() async {
    if (_pendingChanges.isEmpty) return;
    final priceDiscountList = <Map<String, dynamic>>[];
    final clubDiscountList = <Map<String, dynamic>>[];

    for (var change in _pendingChanges.values) {
      final hasPriceOrDiscount = change.containsKey('price') || change.containsKey('discount');
      final hasClub = change.containsKey('clubDiscount');
      if (hasPriceOrDiscount) {
        priceDiscountList.add({
          'nmID': change['nmID'],
          if (change.containsKey('price')) 'price': change['price'],
          if (change.containsKey('discount')) 'discount': change['discount'],
        });
      }
      if (hasClub) {
        clubDiscountList.add({'nmID': change['nmID'], 'clubDiscount': change['clubDiscount']});
      }
    }

    try {
      if (priceDiscountList.isNotEmpty) {
        await http.post(
          Uri.parse('https://discounts-prices-api.wildberries.ru/api/v2/upload/task'),
          headers: {'Authorization': _wbApiToken!, 'Content-Type': 'application/json'},
          body: json.encode({'data': priceDiscountList}),
        );
      }
      if (clubDiscountList.isNotEmpty) {
        await http.post(
          Uri.parse('https://discounts-prices-api.wildberries.ru/api/v2/upload/task/club-discount'),
          headers: {'Authorization': _wbApiToken!, 'Content-Type': 'application/json'},
          body: json.encode({'data': clubDiscountList}),
        );
      }
      // после успеха очищаем pending и перезагружаем кэш
      _pendingChanges.clear();
      await loadAllPrices(); // перезагружаем актуальные данные
    } catch (e) {
      throw Exception('Ошибка массовой отправки: $e');
    }
  }

  String _makeKey(int nmID, int chrtID) => '${nmID}_$chrtID';
}