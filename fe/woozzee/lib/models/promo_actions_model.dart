import 'dart:convert';

class Promotion {
  final int id;
  final String name;
  final String type; // 'regular' или 'auto'
  final DateTime? startDateTime;
  final DateTime? endDateTime;
  final Map<int, int> goods; // nmID -> planDiscount
  final String? description;
  final String? advantages;

  Promotion({
    required this.id,
    required this.name,
    required this.type,
    this.startDateTime,
    this.endDateTime,
    this.goods = const {},
    this.description,
    this.advantages,
  });

  factory Promotion.fromJson(Map<String, dynamic> json) {
    return Promotion(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Акция ${json['id']}',
      type: json['type']?.toString() ?? 'regular',
      startDateTime: json['startDateTime'] != null
          ? DateTime.parse(json['startDateTime'] as String).toUtc()
          : null,
      endDateTime: json['endDateTime'] != null
          ? DateTime.parse(json['endDateTime'] as String).toUtc()
          : null,
      description: json['description'] as String?,
      advantages: json['advantages'] as String?,
    );
  }

  String get columnKey => 'promotion_$id';
  String get displayLabel => type == 'auto' ? '[А]$id' : '$id';

  String get tooltipText {
    final buffer = StringBuffer();
    buffer.writeln('$name\n');
    if (type == 'auto') buffer.writeln('Тип: Автоакция');
    if (startDateTime != null) buffer.writeln('Начало: ${_formatDate(startDateTime!)}');
    if (endDateTime != null) buffer.writeln('Конец: ${_formatDate(endDateTime!)}');
    if (description != null && description!.isNotEmpty) buffer.writeln('\n$description');
    if (advantages != null && advantages!.isNotEmpty) buffer.writeln('\nПреимущества: $advantages');
    return buffer.toString();
  }

  bool get isAutoPromotion => type == 'auto';

  int? getDiscountForProduct(int nmId) => goods[nmId];

  Promotion copyWithGoods(Map<int, int> newGoods) {
    return Promotion(
      id: id,
      name: name,
      type: type,
      startDateTime: startDateTime,
      endDateTime: endDateTime,
      goods: newGoods,
      description: description,
      advantages: advantages,
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day}.${local.month}.${local.year} ${local.hour}:${local.minute}';
  }
}