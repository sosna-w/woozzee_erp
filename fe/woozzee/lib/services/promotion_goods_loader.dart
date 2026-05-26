import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/promo_actions_model.dart';
import '../../models/promotion_goods_info.dart';
import '../../utils/private_token_manager.dart';

class PromotionGoodsLoader {
  String? wbApiToken;

  PromotionGoodsLoader({this.wbApiToken});

  Future<Map<int, PromotionGoodsInfo>?> loadGoodsForPromotion(Promotion promotion) async {
    if (promotion.isAutoPromotion) {
      return await _loadAutoPromotionGoods(promotion.id);
    } else {
      return await _loadRegularPromotionGoods(promotion.id);
    }
  }

  Future<Map<int, PromotionGoodsInfo>?> _loadRegularPromotionGoods(int promotionId) async {
    if (wbApiToken == null) return null;

    final mapFalse = await _fetchPromotionGoodsWithInAction(promotionId, false);
    final mapTrue = await _fetchPromotionGoodsWithInAction(promotionId, true);

    final Map<int, PromotionGoodsInfo> combined = {};
    if (mapFalse != null) combined.addAll(mapFalse);
    if (mapTrue != null) {
      for (var entry in mapTrue.entries) combined[entry.key] = entry.value;
    }
    return combined.isNotEmpty ? combined : null;
  }

  Future<Map<int, PromotionGoodsInfo>?> _fetchPromotionGoodsWithInAction(int promotionId, bool inAction) async {
    if (wbApiToken == null) return null;

    final inActionStr = inAction ? 'true' : 'false';
    int offset = 0;
    const limit = 1000;
    Map<int, PromotionGoodsInfo> goodsMap = {};
    bool hasMore = true;

    while (hasMore) {
      final url = 'https://dp-calendar-api.wildberries.ru/api/v1/calendar/promotions/nomenclatures'
          '?promotionID=$promotionId&inAction=$inActionStr&limit=$limit&offset=$offset';
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': wbApiToken!,
          },
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final nomenclaturesList = data['data']?['nomenclatures'] as List<dynamic>?;
          if (nomenclaturesList == null || nomenclaturesList.isEmpty) {
            hasMore = false;
            break;
          }
          for (var nom in nomenclaturesList) {
            final nmID = nom['id'] as int?;
            if (nmID == null) continue;
            final planDiscount = nom['planDiscount'];
            int? discountInt;
            if (planDiscount is int) discountInt = planDiscount;
            else if (planDiscount is double) discountInt = planDiscount.round();
            else if (planDiscount is String) discountInt = int.tryParse(planDiscount);
            if (discountInt != null) {
              goodsMap[nmID] = PromotionGoodsInfo(planDiscount: discountInt, inAction: inAction);
            }
          }
          if (nomenclaturesList.length < limit) hasMore = false;
          else {
            offset += limit;
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } else {
          return null;
        }
      } catch (e) {
        return null;
      }
    }
    return goodsMap.isNotEmpty ? goodsMap : null;
  }

  Future<Map<int, PromotionGoodsInfo>?> _loadAutoPromotionGoods(int promotionId) async {
    try {
      final privateTokenManager = PrivateTokenManager();
      await privateTokenManager.initialize();
      final authorizeV3 = privateTokenManager.authorizeV3;
      final wbSellerLk = privateTokenManager.wbSellerLk;
      final cookie = privateTokenManager.cookie;

      if (authorizeV3 == null || wbSellerLk == null) return null;

      final response = await http.post(
        Uri.parse('https://hide_domain.com/auto-promotions/process'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'authorize_v3': authorizeV3,
          'wb_seller_lk': wbSellerLk,
          'cookie': cookie,
          'promotion_ids': [promotionId],
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final results = data['results'] as Map<String, dynamic>;
          final promoResults = results[promotionId.toString()] as List<dynamic>?;
          if (promoResults != null) {
            final Map<int, PromotionGoodsInfo> goodsMap = {};
            for (var item in promoResults) {
              final nmID = int.tryParse(item['wb_article'].toString());
              final discount = item['discount'] is int
                  ? item['discount']
                  : (item['discount'] is double ? item['discount'].round() : int.tryParse(item['discount'].toString()));
              if (nmID != null && discount != null) {
                goodsMap[nmID] = PromotionGoodsInfo(planDiscount: discount, inAction: true);
              }
            }
            return goodsMap;
          }
        }
      }
    } catch (e) {
      print('Ошибка загрузки автоакции $promotionId: $e');
    }
    return null;
  }
}