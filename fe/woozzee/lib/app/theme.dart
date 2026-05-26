import 'package:flutter/material.dart';

ThemeData buildLightTheme() {
  return ThemeData.light().copyWith(
    colorScheme: ColorScheme.light(
      primary: Colors.blue.shade700,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: Colors.black87,
      background: Colors.grey.shade100,
      outline: Colors.grey.shade300,
    ),
    useMaterial3: true,
  );
}