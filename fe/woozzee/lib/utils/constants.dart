// constants.dart - исправленная версия

import 'package:flutter/material.dart';

class NavItem {
  final String title;
  final IconData icon;

  const NavItem(this.title, this.icon);
}

const List<NavItem> navItems = [
  NavItem('Остатки', Icons.inventory_2_outlined),
  NavItem('Цены', Icons.price_change),          // ← теперь ведёт на новый экран
  NavItem('Поставки', Icons.local_shipping_outlined),
  NavItem('Аналитика', Icons.analytics_outlined),
  NavItem('Отчеты', Icons.insights_outlined),
  NavItem('Реклама', Icons.campaign_outlined),
  NavItem('Браузер', Icons.web_outlined),
  NavItem('Инфо', Icons.info_outline),
  // Конструктор удалён
  // Цены (новая) удалён
];

IconData getSectionIcon(int index) {
  switch (index) {
    case 0: return Icons.inventory_2_outlined;
    case 1: return Icons.price_change;            // новый экран цен
    case 2: return Icons.local_shipping_outlined;
    case 3: return Icons.analytics_outlined;
    case 4: return Icons.insights_outlined;
    case 5: return Icons.campaign_outlined;
    case 6: return Icons.web_outlined;
    case 7: return Icons.info_outline;
    default: return Icons.settings_outlined;
  }
}

String getCurrentPage(int index) {
  switch (index) {
    case 0: return 'Остатки';
    case 1: return 'Цены';                        // новый экран
    case 2: return 'Поставки';
    case 3: return 'Аналитика';
    case 4: return 'Отчеты';
    case 5: return 'Реклама';
    case 6: return 'Браузер';
    case 7: return 'Инфо';
    default: return 'Настройки';
  }
}

const String appVersion = '3.0.1';