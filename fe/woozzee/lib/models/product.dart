import 'dart:convert';

/// Модель размера/варианта товара (скидки, артикулы)
class ProductSize {
  final int chrtID;
  final List<String> skus;
  final String techSize;
  final String wbSize;

  ProductSize({
    required this.chrtID,
    required this.skus,
    required this.techSize,
    required this.wbSize,
  });

  factory ProductSize.fromJson(Map<String, dynamic> json) {
    return ProductSize(
      chrtID: json['chrtID'] as int? ?? 0,
      skus: (json['skus'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      techSize: json['techSize'] as String? ?? '',
      wbSize: json['wbSize'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chrtID': chrtID,
      'skus': skus,
      'techSize': techSize,
      'wbSize': wbSize,
    };
  }
}

class Product {
  final int nmID;
  final int imtID;
  final String nmUUID;
  final int subjectID;
  final String subjectName;
  final String vendorCode;
  final String brand;
  final String title;
  final String description;
  final bool needKiz;
  final String? video;
  final bool wholesaleEnabled;
  final int wholesaleQuantum;
  final double dimensionsLength;
  final double dimensionsWidth;
  final double dimensionsHeight;
  final double dimensionsWeightBrutto;
  final bool dimensionsIsValid;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<dynamic> photos;            // можно потом тоже типизировать
  final List<ProductSize> sizes;         // ← теперь типизированный список
  final List<dynamic> characteristics;
  final List<dynamic> tags;

  Product({
    required this.nmID,
    required this.imtID,
    required this.nmUUID,
    required this.subjectID,
    required this.subjectName,
    required this.vendorCode,
    required this.brand,
    required this.title,
    required this.description,
    required this.needKiz,
    this.video,
    required this.wholesaleEnabled,
    required this.wholesaleQuantum,
    required this.dimensionsLength,
    required this.dimensionsWidth,
    required this.dimensionsHeight,
    required this.dimensionsWeightBrutto,
    required this.dimensionsIsValid,
    required this.createdAt,
    required this.updatedAt,
    required this.photos,
    required this.sizes,
    required this.characteristics,
    required this.tags,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    // Парсим sizes
    List<ProductSize> parsedSizes = [];
    if (json['sizes'] != null) {
      final sizesData = json['sizes'] is String
          ? jsonDecode(json['sizes'] as String) as List<dynamic>
          : json['sizes'] as List<dynamic>;
      parsedSizes = sizesData
          .map((sizeJson) => ProductSize.fromJson(sizeJson as Map<String, dynamic>))
          .toList();
    }

    return Product(
      nmID: json['nmID'] as int? ?? 0,
      imtID: json['imtID'] as int? ?? 0,
      nmUUID: json['nmUUID'] as String? ?? '',
      subjectID: json['subjectID'] as int? ?? 0,
      subjectName: json['subjectName'] as String? ?? '',
      vendorCode: json['vendorCode'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      needKiz: json['needKiz'] as bool? ?? false,
      video: json['video'] as String?,
      wholesaleEnabled: json['wholesale_enabled'] as bool? ?? false,
      wholesaleQuantum: json['wholesale_quantum'] as int? ?? 0,
      dimensionsLength: (json['dimensions_length'] as num?)?.toDouble() ?? 0.0,
      dimensionsWidth: (json['dimensions_width'] as num?)?.toDouble() ?? 0.0,
      dimensionsHeight: (json['dimensions_height'] as num?)?.toDouble() ?? 0.0,
      dimensionsWeightBrutto: (json['dimensions_weightBrutto'] as num?)?.toDouble() ?? 0.0,
      dimensionsIsValid: json['dimensions_isValid'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      photos: json['photos'] != null
          ? (json['photos'] is String
              ? jsonDecode(json['photos'] as String)
              : json['photos'] as List<dynamic>)
          : [],
      sizes: parsedSizes,
      characteristics: json['characteristics'] != null
          ? (json['characteristics'] is String
              ? jsonDecode(json['characteristics'] as String)
              : json['characteristics'] as List<dynamic>)
          : [],
      tags: json['tags'] != null
          ? (json['tags'] is String
              ? jsonDecode(json['tags'] as String)
              : json['tags'] as List<dynamic>)
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nmID': nmID,
      'imtID': imtID,
      'nmUUID': nmUUID,
      'subjectID': subjectID,
      'subjectName': subjectName,
      'vendorCode': vendorCode,
      'brand': brand,
      'title': title,
      'description': description,
      'needKiz': needKiz,
      'video': video,
      'wholesale_enabled': wholesaleEnabled,
      'wholesale_quantum': wholesaleQuantum,
      'dimensions_length': dimensionsLength,
      'dimensions_width': dimensionsWidth,
      'dimensions_height': dimensionsHeight,
      'dimensions_weightBrutto': dimensionsWeightBrutto,
      'dimensions_isValid': dimensionsIsValid,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'photos': photos,
      'sizes': sizes.map((s) => s.toJson()).toList(),
      'characteristics': characteristics,
      'tags': tags,
    };
  }

  // Вспомогательные методы для работы с размерами и chrtID
  List<int> get allChrtIDs => sizes.map((s) => s.chrtID).toList();
  
  int? get firstChrtID => sizes.isNotEmpty ? sizes.first.chrtID : null;
  
  ProductSize? getSizeByChrtID(int chrtID) {
    try {
      return sizes.firstWhere((size) => size.chrtID == chrtID);
    } catch (_) {
      return null;
    }
  }

  List<String> getPhotoUrls() {
    if (photos.isEmpty) return [];
    final List<String> urls = [];
    for (var photo in photos) {
      if (photo is Map<String, dynamic>) {
        final bigUrl = photo['big'] as String?;
        if (bigUrl != null && bigUrl.isNotEmpty) {
          urls.add(bigUrl);
        }
      }
    }
    return urls;
  }

  bool hasPhotos() => getPhotoUrls().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Product &&
          runtimeType == other.runtimeType &&
          nmID == other.nmID;

  @override
  int get hashCode => nmID.hashCode;

  Product copyWith({
    int? nmID,
    int? imtID,
    String? nmUUID,
    int? subjectID,
    String? subjectName,
    String? vendorCode,
    String? brand,
    String? title,
    String? description,
    bool? needKiz,
    String? video,
    bool? wholesaleEnabled,
    int? wholesaleQuantum,
    double? dimensionsLength,
    double? dimensionsWidth,
    double? dimensionsHeight,
    double? dimensionsWeightBrutto,
    bool? dimensionsIsValid,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<dynamic>? photos,
    List<ProductSize>? sizes,
    List<dynamic>? characteristics,
    List<dynamic>? tags,
  }) {
    return Product(
      nmID: nmID ?? this.nmID,
      imtID: imtID ?? this.imtID,
      nmUUID: nmUUID ?? this.nmUUID,
      subjectID: subjectID ?? this.subjectID,
      subjectName: subjectName ?? this.subjectName,
      vendorCode: vendorCode ?? this.vendorCode,
      brand: brand ?? this.brand,
      title: title ?? this.title,
      description: description ?? this.description,
      needKiz: needKiz ?? this.needKiz,
      video: video ?? this.video,
      wholesaleEnabled: wholesaleEnabled ?? this.wholesaleEnabled,
      wholesaleQuantum: wholesaleQuantum ?? this.wholesaleQuantum,
      dimensionsLength: dimensionsLength ?? this.dimensionsLength,
      dimensionsWidth: dimensionsWidth ?? this.dimensionsWidth,
      dimensionsHeight: dimensionsHeight ?? this.dimensionsHeight,
      dimensionsWeightBrutto: dimensionsWeightBrutto ?? this.dimensionsWeightBrutto,
      dimensionsIsValid: dimensionsIsValid ?? this.dimensionsIsValid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      photos: photos ?? this.photos,
      sizes: sizes ?? this.sizes,
      characteristics: characteristics ?? this.characteristics,
      tags: tags ?? this.tags,
    );
  }
}