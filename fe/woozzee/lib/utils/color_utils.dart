import 'package:flutter/material.dart';

Color hexToColor(String hex) {
  try {
    String colorHex = hex.replaceFirst('#', '');
    if (colorHex.length == 6) colorHex = 'FF$colorHex';
    return Color(int.parse(colorHex, radix: 16));
  } catch (e) {
    return Colors.white;
  }
}

Color getContrastTextColor(Color backgroundColor) {
  final luminance = backgroundColor.computeLuminance();
  return luminance > 0.5 ? Colors.black : Colors.white;
}