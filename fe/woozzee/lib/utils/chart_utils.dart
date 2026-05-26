import 'package:flutter/material.dart';

String formatChartDateLabel(DateTime date, {bool withTime = true}) {
  const months = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
  final dateStr = '${date.day} ${months[date.month - 1]}';
  if (!withTime) return dateStr;
  final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  return '$dateStr\n$timeStr';
}