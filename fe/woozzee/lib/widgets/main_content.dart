// main_content.dart - ДОБАВЛЕН ЭКРАН ЦЕН (НОВАЯ)

import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'unified_products_table.dart';
import 'browser_screen.dart';
import 'global_browser_manager.dart';
import 'analytics_screen.dart';
import 'supplies_screen.dart';
import 'reports_screen.dart';
import 'prices_screen_new.dart';
import 'supplies_screen_new.dart';
import 'info_screen.dart';
import 'supplies_screen_new.dart';
import 'promotion_screen.dart';
import 'info_screen.dart';

class MainContent extends StatefulWidget {
  final int currentIndex;
  final GlobalBrowserManager browserManager;

  const MainContent({
    super.key,
    required this.currentIndex,
    required this.browserManager,
  });

  @override
  State<MainContent> createState() => _MainContentState();
}

class _MainContentState extends State<MainContent> with AutomaticKeepAliveClientMixin {
  final Map<int, Widget> _cachedSections = {};

  @override
  bool get wantKeepAlive => true;

  // main_content.dart – изменённый фрагмент

  Widget _buildSection(int index) {
    if (!_cachedSections.containsKey(index)) {
      switch (index) {
        case 0:
          _cachedSections[0] = const UnifiedProductsTable(key: PageStorageKey('unified_products'));
          break;
        case 1:
          _cachedSections[1] = const PricesScreenNew(key: PageStorageKey('prices_screen_new'));
          break;
        case 2:
        // Поставки — новый экран
          _cachedSections[2] = const SuppliesScreenNew(key: PageStorageKey('supplies_screen_new'));
          break;
        case 3:
          _cachedSections[3] = AnalyticsScreen(key: PageStorageKey('analytics_screen'));
          break;
        case 4:
          _cachedSections[4] = const ReportsScreen(key: PageStorageKey('reports_screen'));
          break;
        case 5:
        // Реклама — экран promotion_screen.dart
          _cachedSections[5] = const PromotionScreen(key: PageStorageKey('promotion_screen'));
          break;
        case 6:
          _cachedSections[6] = BrowserScreen(
            browserManager: widget.browserManager,
            key: const PageStorageKey('browser'),
          );
          break;
        case 7:
        // Инфо — сетка 50px
          _cachedSections[7] = const InfoScreen(key: PageStorageKey('info_screen'));
          break;
        default:
          _cachedSections[index] = _buildPlaceholder(index);
      }
    }
    return _cachedSections[index]!;
  }

  String _getPlaceholderDescription(int index) {
    switch (index) {
      case 5:
        return 'Планируется. Автоматическое управление кампаниями.';
      default:
        return 'Раздел в разработке';
    }
  }

  Widget _buildPlaceholder(int index) {
    final description = _getPlaceholderDescription(index);
    final isPlanned = description.startsWith('Планируется');
    final isInDevelopment = description.startsWith('Раздел в разработке');

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              getSectionIcon(index),
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              getCurrentPage(index),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                children: [
                  if (isPlanned || isInDevelopment)
                    Text(
                      isPlanned ? 'Планируется' : 'Раздел в разработке',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    isPlanned
                        ? description.substring('Планируется. '.length)
                        : isInDevelopment
                        ? description.substring('Раздел в разработке. '.length)
                        : description,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Expanded(
      child: _buildSection(widget.currentIndex),
    );
  }
}