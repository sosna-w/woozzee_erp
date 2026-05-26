import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ============================================================================
// МОДЕЛИ КАМПАНИЙ
// ============================================================================

/// Краткая информация о кампании (из /adv/v1/promotion/count)
class CampaignShort {
  final int id;
  final int type;
  final int status;
  final DateTime changeTime;

  CampaignShort({
    required this.id,
    required this.type,
    required this.status,
    required this.changeTime,
  });
}

/// Полная информация о кампании (из /api/advert/v2/adverts)
class CampaignDetails {
  final int id;
  final String name;
  final String paymentType; // 'cpm' или 'cpc'
  final String bidType;     // 'unified' или 'manual'
  final bool searchPlacement;
  final bool recommendationsPlacement;
  final List<int> nmIds;
  final int status;
  final DateTime updated;
  final Map<int, int> searchBidMap;
  final Map<int, int> recBidMap;

  CampaignDetails({
    required this.id,
    required this.name,
    required this.paymentType,
    required this.bidType,
    required this.searchPlacement,
    required this.recommendationsPlacement,
    required this.nmIds,
    required this.status,
    required this.updated,
    this.searchBidMap = const {},
    this.recBidMap = const {},
  });

  String get paymentTypeText => paymentType == 'cpm' ? 'За показы' : 'За клик';
  String get bidTypeText => bidType == 'unified' ? 'Единая' : 'Ручная';

  Color get statusColor {
    switch (status) {
      case 9: return Colors.green;
      case 11: return Colors.orange;
      default: return Colors.grey;
    }
  }

  String get statusText {
    switch (status) {
      case 9: return 'Активна';
      case 11: return 'На паузе';
      default: return 'Статус $status';
    }
  }
}

// ============================================================================
// СЕРВИС ДЛЯ РАБОТЫ С КАМПАНИЯМИ
// ============================================================================

class CampaignService {
  /// Получить краткий список всех кампаний
  Future<List<CampaignShort>> fetchCampaignsShort(String token) async {
    final url = Uri.parse('https://advert-api.wildberries.ru/adv/v1/promotion/count');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка загрузки списка кампаний: ${response.statusCode}');
    }

    final jsonData = json.decode(response.body);
    final List<dynamic> adverts = jsonData['adverts'] ?? [];
    final List<CampaignShort> result = [];

    for (var group in adverts) {
      final int type = group['type'] ?? 0;
      final int status = group['status'] ?? 0;
      final List<dynamic> advertList = group['advert_list'] ?? [];
      for (var item in advertList) {
        final int id = item['advertId'];
        final DateTime changeTime = DateTime.parse(item['changeTime']);
        result.add(CampaignShort(
          id: id,
          type: type,
          status: status,
          changeTime: changeTime,
        ));
      }
    }
    return result;
  }

  /// Получить детали кампаний по списку ID (пачками по 50)
  Future<Map<int, CampaignDetails>> fetchCampaignsDetails(
    String token,
    List<int> ids,
  ) async {
    final Map<int, CampaignDetails> detailsMap = {};

    // Разбиваем на пачки по 50
    for (var i = 0; i < ids.length; i += 50) {
      final chunk = ids.sublist(i, i + 50 > ids.length ? ids.length : i + 50);
      final idsParam = chunk.join(',');
      final url = Uri.parse('https://advert-api.wildberries.ru/api/advert/v2/adverts?ids=$idsParam');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки деталей: ${response.statusCode}');
      }

      final jsonData = json.decode(response.body);
      final List<dynamic> adverts = jsonData['adverts'] ?? [];
      for (var adv in adverts) {
        final int id = adv['id'];
        final String name = adv['settings']['name'] ?? 'Без имени';
        final String paymentType = adv['settings']['payment_type'] ?? 'cpm';
        final String bidType = adv['bid_type'] ?? 'unified';
        final bool search = adv['settings']['placements']['search'] ?? false;
        final bool recommendations = adv['settings']['placements']['recommendations'] ?? false;
        final int status = adv['status'];
        final DateTime updated = DateTime.parse(adv['timestamps']['updated']);

        final List<dynamic> nmSettings = adv['nm_settings'] ?? [];
        final List<int> nmIds = [];
        for (var nm in nmSettings) {
          final int nmId = nm['nm_id'];
          if (nmId != null) nmIds.add(nmId);
        }

        final searchMap = <int, int>{};
        final recMap = <int, int>{};
        for (var nm in nmSettings) {
          final nmId = nm['nm_id'] as int;
          final bids = nm['bids_kopecks'] as Map?;
          final search = bids?['search'] as int? ?? 0;
          final rec = bids?['recommendations'] as int? ?? 0;
          searchMap[nmId] = search;
          recMap[nmId] = rec;
        }

        detailsMap[id] = CampaignDetails(
          id: id,
          name: name,
          paymentType: paymentType,
          bidType: bidType,
          searchPlacement: search,
          recommendationsPlacement: recommendations,
          nmIds: nmIds,
          status: status,
          updated: updated,
          searchBidMap: searchMap,
          recBidMap: recMap,
        );
      }
    }
    return detailsMap;
  }

  // В campaign_service.dart добавить:

  /// Загружает бюджеты для списка кампаний асинхронно, соблюдая лимиты API.
  /// Возвращает Stream, который выдаёт пары (campaignId, budget) по мере готовности.
  Stream<MapEntry<int, int>> loadBudgetsStream(
      String token,
      List<CampaignDetails> campaigns,
      ) async* {
    if (campaigns.isEmpty) return;

    // Копируем список, чтобы не мутировать оригинал
    final remaining = List<CampaignDetails>.from(campaigns);
    int consecutiveErrors = 0;
    const maxConsecutiveErrors = 5;

    while (remaining.isNotEmpty) {
      // Ограничиваем количество одновременных запросов с учётом burst (4)
      final batch = remaining.take(4).toList();
      final futures = <Future<MapEntry<int, int>?>>[];

      for (final campaign in batch) {
        futures.add(_fetchBudgetWithRateLimit(token, campaign.id).then(
              (budget) => budget != null ? MapEntry(campaign.id, budget) : null,
        ));
      }

      final results = await Future.wait(futures);
      int successCount = 0;

      for (final result in results) {
        if (result != null) {
          yield result;
          successCount++;
        }
      }

      if (successCount == 0) {
        consecutiveErrors++;
        if (consecutiveErrors >= maxConsecutiveErrors) {
          debugPrint('❌ Слишком много ошибок при загрузке бюджетов, останавливаемся');
          break;
        }
        // Если все запросы в пачке упали, ждём подольше
        await Future.delayed(const Duration(seconds: 2));
      } else {
        consecutiveErrors = 0;
      }

      // Удаляем обработанные кампании
      remaining.removeWhere((c) => batch.any((b) => b.id == c.id));

      // Небольшая задержка между пачками для соблюдения лимита (250 мс)
      if (remaining.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  /// Внутренний метод с обработкой 429 и заголовков rate limit
  Future<int?> _fetchBudgetWithRateLimit(String token, int campaignId) async {
    int attempt = 0;
    const maxAttempts = 3;

    while (attempt < maxAttempts) {
      try {
        final url = Uri.parse('https://advert-api.wildberries.ru/adv/v1/budget?id=$campaignId');
        final response = await http.get(
          url,
          headers: {'Authorization': 'Bearer $token'},
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          return data['total'] as int?;
        } else if (response.statusCode == 429) {
          // Извлекаем заголовки для повторной попытки
          final retryAfter = response.headers['x-ratelimit-retry'];
          final resetAfter = response.headers['x-ratelimit-reset'];
          int waitSeconds = 1;
          if (retryAfter != null) waitSeconds = int.tryParse(retryAfter) ?? 1;
          else if (resetAfter != null) waitSeconds = int.tryParse(resetAfter) ?? 1;

          debugPrint('⚠️ Rate limit для кампании $campaignId, ждём $waitSeconds сек');
          await Future.delayed(Duration(seconds: waitSeconds));
          attempt++;
          continue;
        } else {
          debugPrint('⚠️ Ошибка ${response.statusCode} для кампании $campaignId');
          return null;
        }
      } catch (e) {
        debugPrint('❌ Исключение при загрузке бюджета $campaignId: $e');
        attempt++;
        if (attempt < maxAttempts) await Future.delayed(const Duration(seconds: 1));
      }
    }
    return null;
  }

  // campaign_service.dart

  /// Загружает статистику для списка кампаний за указанный период.
  /// ids — список ID кампаний (не более 50).
  /// beginDate, endDate — даты в формате YYYY-MM-DD.
  /// Возвращает Map<advertId, статистика>.
  Future<Map<int, Map<String, dynamic>>> fetchCampaignsStats(
      String token,
      List<int> ids,
      DateTime beginDate,
      DateTime endDate,
      ) async {
    if (ids.isEmpty) return {};
    if (ids.length > 50) {
      throw Exception('Максимум 50 кампаний за один запрос');
    }

    final idsParam = ids.join(',');
    final begin = DateFormat('yyyy-MM-dd').format(beginDate);
    final end = DateFormat('yyyy-MM-dd').format(endDate);
    final url = Uri.parse(
      'https://advert-api.wildberries.ru/adv/v3/fullstats?ids=$idsParam&beginDate=$begin&endDate=$end',
    );

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> list = json.decode(response.body);
        final Map<int, Map<String, dynamic>> result = {};
        for (var item in list) {
          final id = item['advertId'] as int;
          result[id] = {
            'sum': (item['sum'] as num?)?.toDouble() ?? 0.0,
            'views': item['views'] ?? 0,
            'ctr': (item['ctr'] as num?)?.toDouble() ?? 0.0,
            'shks': item['shks'] ?? 0,
            'sum_price': (item['sum_price'] as num?)?.toDouble() ?? 0.0,
            'atbs': item['atbs'] ?? 0,
            'clicks': item['clicks'] ?? 0,
            'cpc': (item['cpc'] as num?)?.toDouble() ?? 0.0,
            'cr': (item['cr'] as num?)?.toDouble() ?? 0.0,
            // дополнительные поля (canceled, orders, boosterStats) при необходимости
          };
        }
        return result;
      } else if (response.statusCode == 429) {
        // Слишком много запросов — можно выбросить исключение или повторить позже
        throw Exception('Rate limit (429): слишком много запросов к статистике');
      } else {
        throw Exception('Ошибка загрузки статистики: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Ошибка запроса статистики: $e');
      rethrow;
    }
  }

  /// Подсчитать количество кампаний для каждого товара (nmId)
  Map<int, int> countProductCampaigns(Map<int, CampaignDetails> detailsMap) {
    final Map<int, int> countMap = {};
    for (final campaign in detailsMap.values) {
      for (final nmId in campaign.nmIds) {
        countMap[nmId] = (countMap[nmId] ?? 0) + 1;
      }
    }
    return countMap;
  }

  /// Удобный метод: загрузить все нужные данные (краткий список + детали для статусов 9,11)
  Future<({
    List<CampaignShort> short,
    Map<int, CampaignDetails> details,
    Map<int, int> productCount,
  })> loadFullCampaignData(String token) async {
    final shortList = await fetchCampaignsShort(token);
    final activeOrPausedIds = shortList
        .where((c) => c.status == 9 || c.status == 11)
        .map((c) => c.id)
        .toList();

    Map<int, CampaignDetails> detailsMap = {};
    if (activeOrPausedIds.isNotEmpty) {
      detailsMap = await fetchCampaignsDetails(token, activeOrPausedIds);
    }
    final productCount = countProductCampaigns(detailsMap);
    return (short: shortList, details: detailsMap, productCount: productCount);
  }
  Future<int?> fetchCampaignBudget(String token, int campaignId) async {
    final url = Uri.parse('https://advert-api.wildberries.ru/adv/v1/budget?id=$campaignId');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body);
      return jsonData['total'] as int?;
    } else if (response.statusCode == 401 || response.statusCode == 429) {
      debugPrint('⚠️ Ошибка получения бюджета для кампании $campaignId: ${response.statusCode}');
      return null;
    } else {
      throw Exception('Ошибка загрузки бюджета: ${response.statusCode}');
    }
  }

  /// Получить данные баланса (счёт, баланс, бонусы, промо-бонусы)
  Future<Map<String, dynamic>> fetchBalance(String token) async {
    final url = Uri.parse('https://advert-api.wildberries.ru/adv/v1/balance');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 401 || response.statusCode == 429) {
      debugPrint('⚠️ Ошибка получения баланса: ${response.statusCode}');
      return {};
    } else {
      throw Exception('Ошибка загрузки баланса: ${response.statusCode}');
    }
  }

  Future<int?> depositBudget({
    required String token,
    required int campaignId,
    required int sum,
    required int type,
    bool returnBudget = true,
  }) async {
    final url = Uri.parse('https://advert-api.wildberries.ru/adv/v1/budget/deposit?id=$campaignId');
    final body = {
      'sum': sum,
      'type': type,
      'return': returnBudget,
    };
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (returnBudget && data.containsKey('total')) {
        return data['total'] as int;
      }
      return null;
    } else {
      final errorBody = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      throw Exception('${response.statusCode}: ${errorBody['error'] ?? errorBody}');
    }
  }

  Future<void> pauseCampaign(String token, int campaignId) async {
    final url = Uri.parse('https://advert-api.wildberries.ru/adv/v0/pause?id=$campaignId');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      final errorBody = response.body.isNotEmpty ? json.decode(response.body) : {};
      throw Exception('Ошибка паузы кампании: ${errorBody['error'] ?? response.statusCode}');
    }
  }

  /// Запустить кампанию (статус 11 -> 9)
  Future<void> startCampaign(String token, int campaignId) async {
    final url = Uri.parse('https://advert-api.wildberries.ru/adv/v0/start?id=$campaignId');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      final errorBody = response.body.isNotEmpty ? json.decode(response.body) : {};
      throw Exception('Ошибка запуска кампании: ${errorBody['error'] ?? response.statusCode}');
    }
  }

  /// Завершить кампанию (статус 4/9/11 -> завершена)
  Future<void> stopCampaign(String token, int campaignId) async {
    final url = Uri.parse('https://advert-api.wildberries.ru/adv/v0/stop?id=$campaignId');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      final errorBody = response.body.isNotEmpty ? json.decode(response.body) : {};
      throw Exception('Ошибка завершения кампании: ${errorBody['error'] ?? response.statusCode}');
    }
  }
}