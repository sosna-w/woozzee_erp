import '../../models/promo_actions_model.dart';

extension PromotionExtension on Promotion {
  bool get isRegularPromotion => type == 'regular';
  bool get isAutoPromotion => type == 'auto';
}