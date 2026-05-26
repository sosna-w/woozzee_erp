import 'package:flutter/material.dart';

class ImageData {
  final Key key;
  final double width;
  final double height;
  final String imageUrl;
  final int productIndex;
  final int imageIndex;
  final int nmId;

  ImageData({
    required this.key,
    required this.width,
    required this.height,
    required this.imageUrl,
    required this.productIndex,
    required this.imageIndex,
    required this.nmId,
  });
}