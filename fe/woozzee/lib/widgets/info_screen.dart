// info_screen.dart (полный обновлённый файл)

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../utils/product_manager.dart';
import '../../../utils/news_manager.dart';
import '../../../utils/rbc_news_manager.dart';
import '../../../services/stocks_dynamics_service.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import '../../../services/counts_service.dart';
import '../../../services/campaign_service.dart';        // ← импорт сервиса кампаний
import '../../../utils/token_manager.dart';             // для получения токена


// ========== Модель данных для линий графика ==========
class LineChartDataModel {
  final List<FlSpot> spots;
  final Color color;
  final String title;
  LineChartDataModel({required this.spots, required this.color, required this.title});
}

class InfoScreen extends StatefulWidget {
  const InfoScreen({super.key});

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  final ProductManager _productManager = ProductManager();
  final NewsManager _newsManager = NewsManager();
  final RbcNewsManager _rbcNewsManager = RbcNewsManager();
  final StocksDynamicsService _stocksDynamicsService = StocksDynamicsService();

  late final ScrollController _newsScrollController;
  late final ScrollController _rbcNewsScrollController;

  final CountsService _countsService = CountsService();
  Map<String, dynamic>? _countsData;
  bool _isCountsLoading = false;

  // ---- Данные кампаний для карточки "Реклама" ----
  Map<String, dynamic>? _campaignStats;
  bool _isCampaignLoading = false;

  List<String>? _currentXLabels;
  final Map<int, List<String>?> _cachedXLabels = {};

  int _selectedNewsTab = 0;

  bool _canScrollPortalLeft = false;
  bool _canScrollPortalRight = false;
  bool _canScrollRbcLeft = false;
  bool _canScrollRbcRight = false;

  // Обновлённая карточка "Реклама" с нужными метриками
  final Map<String, List<String>> _categories = {
    "Товары": [
      "Всего",
      "С остатками",
      "С остатками FBO",
      "С остатками FBS",
      "Без остатков",
    ],
    "Остатки": [
      "Всего",
      "FBO",
      "FBS",
    ],
    "Цены": ["В акциях", "Без скидки"],
    "Поставки": ["На сборке", "Готов к отгрузке", "Идёт приёмка", "Отгружено на воротах"],
    "Финансы": ["Выручка", "Прибыль", "Маржа"],
    "Реклама": [
      "Всего кампаний",
      "Активных",
      "На паузе",
      "Товаров в кампаниях",
      "Товаров в Активных",
      "Товаров на Паузе",
    ],
  };

  int? _pinnedCardIndex;
  int? _hoveredCardIndex;
  int _chartDataKey = 0;
  List<LineChartDataModel> _currentLinesData = [];
  bool _isChartLoading = false;
  final Map<int, List<LineChartDataModel>> _cachedLinesData = {};

  int _pieChartKey = 0;
  List<_PieSectionData> _pieSections = [];

  final List<GlobalKey> _cardKeys = List.generate(6, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    _generateRandomChartData();
    _generateRandomPieData();
    _newsScrollController = ScrollController();
    _rbcNewsScrollController = ScrollController();

    _newsScrollController.addListener(_updatePortalScrollState);
    _rbcNewsScrollController.addListener(_updateRbcScrollState);

    _productManager.addListener(_onProductManagerChanged);
    if (!_productManager.isInitialized) {
      _productManager.initialize();
    }
    _loadCounts();
    _loadCampaignStats();                     // ← загрузка статистики кампаний
    _newsManager.addListener(_onNewsChanged);
    _newsManager.initialize();
    _rbcNewsManager.addListener(_onRbcNewsChanged);
    _rbcNewsManager.initialize();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePortalScrollState();
      _updateRbcScrollState();
    });
  }

  @override
  void dispose() {
    _newsScrollController.removeListener(_updatePortalScrollState);
    _rbcNewsScrollController.removeListener(_updateRbcScrollState);
    _newsScrollController.dispose();
    _rbcNewsScrollController.dispose();
    _productManager.removeListener(_onProductManagerChanged);
    _newsManager.removeListener(_onNewsChanged);
    _rbcNewsManager.removeListener(_onRbcNewsChanged);
    super.dispose();
  }

  Future<void> _loadCounts() async {
    if (_isCountsLoading) return;
    setState(() => _isCountsLoading = true);
    try {
      final data = await _countsService.fetchUnifiedProductsCounts();
      if (mounted) {
        setState(() {
          _countsData = data;
          _isCountsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCountsLoading = false);
        debugPrint('Ошибка загрузки counts: $e');
      }
    }
  }

  /// Загрузка статистики кампаний через CampaignService
  Future<void> _loadCampaignStats() async {
    setState(() => _isCampaignLoading = true);
    try {
      final tokenManager = TokenManager();
      await tokenManager.initialize();
      final token = await tokenManager.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('❌ Нет токена для загрузки кампаний');
        setState(() => _isCampaignLoading = false);
        return;
      }

      final service = CampaignService();
      final data = await service.loadFullCampaignData(token);

      // Подсчёт уникальных товаров
      final allUniqueNmIds = <int>{};
      final activeUniqueNmIds = <int>{};
      final pausedUniqueNmIds = <int>{};

      for (final campaign in data.details.values) {
        final ids = campaign.nmIds.toSet();
        allUniqueNmIds.addAll(ids);
        if (campaign.status == 9) {
          activeUniqueNmIds.addAll(ids);
        } else if (campaign.status == 11) {
          pausedUniqueNmIds.addAll(ids);
        }
      }

      final stats = {
        'total_campaigns': data.short.where((c) => c.status == 9 || c.status == 11).length,
        'active_campaigns': data.short.where((c) => c.status == 9).length,
        'paused_campaigns': data.short.where((c) => c.status == 11).length,
        'total_products': allUniqueNmIds.length,
        'active_products': activeUniqueNmIds.length,
        'paused_products': pausedUniqueNmIds.length,
      };

      if (mounted) {
        setState(() {
          _campaignStats = stats;
          _isCampaignLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Ошибка загрузки кампаний: $e');
      if (mounted) setState(() => _isCampaignLoading = false);
    }
  }

  void _onProductManagerChanged() {
    if (mounted) setState(() {});
  }

  void _onNewsChanged() {
    if (mounted) setState(() {});
  }

  void _onRbcNewsChanged() {
    if (mounted) setState(() {});
  }

  void _updatePortalScrollState() {
    if (!_newsScrollController.hasClients) return;
    final offset = _newsScrollController.offset;
    final maxExtent = _newsScrollController.position.maxScrollExtent;
    setState(() {
      _canScrollPortalLeft = offset > 0;
      _canScrollPortalRight = offset < maxExtent - 1;
    });
  }

  void _updateRbcScrollState() {
    if (!_rbcNewsScrollController.hasClients) return;
    final offset = _rbcNewsScrollController.offset;
    final maxExtent = _rbcNewsScrollController.position.maxScrollExtent;
    setState(() {
      _canScrollRbcLeft = offset > 0;
      _canScrollRbcRight = offset < maxExtent - 1;
    });
  }

  void _scrollPortalLeft() {
    if (!_canScrollPortalLeft) return;
    const double cardWidth = 320;
    const double marginRight = 12;
    final double step = -5 * (cardWidth + marginRight);
    final double currentOffset = _newsScrollController.offset;
    final double minOffset = 0;
    double targetOffset = currentOffset + step;
    if (targetOffset < minOffset) targetOffset = minOffset;
    if (targetOffset != currentOffset) {
      _newsScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _scrollPortalRight() {
    if (!_canScrollPortalRight) return;
    const double cardWidth = 320;
    const double marginRight = 12;
    final double step = 5 * (cardWidth + marginRight);
    final double currentOffset = _newsScrollController.offset;
    final double maxOffset = _newsScrollController.position.maxScrollExtent;
    double targetOffset = currentOffset + step;
    if (targetOffset > maxOffset) targetOffset = maxOffset;
    if (targetOffset != currentOffset) {
      _newsScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _scrollRbcLeft() {
    if (!_canScrollRbcLeft) return;
    const double cardWidth = 640;
    const double marginRight = 12;
    final double step = -(cardWidth + marginRight);
    final double currentOffset = _rbcNewsScrollController.offset;
    final double minOffset = 0;
    double targetOffset = currentOffset + step;
    if (targetOffset < minOffset) targetOffset = minOffset;
    if (targetOffset != currentOffset) {
      _rbcNewsScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _scrollRbcRight() {
    if (!_canScrollRbcRight) return;
    const double cardWidth = 640;
    const double marginRight = 12;
    final double step = cardWidth + marginRight;
    final double currentOffset = _rbcNewsScrollController.offset;
    final double maxOffset = _rbcNewsScrollController.position.maxScrollExtent;
    double targetOffset = currentOffset + step;
    if (targetOffset > maxOffset) targetOffset = maxOffset;
    if (targetOffset != currentOffset) {
      _rbcNewsScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _generateRandomChartData() {
    const int pointCount = 31;
    final random = Random();
    final List<Color> lineColors = [
      const Color(0xFF4CAF50),
      const Color(0xFF2196F3),
      const Color(0xFFFF9800),
    ];
    _currentLinesData = List.generate(2, (index) {
      final List<FlSpot> spots = List.generate(pointCount, (i) {
        final double x = i.toDouble();
        final double y = 20 + random.nextDouble() * 60;
        return FlSpot(x, y);
      });
      return LineChartDataModel(
        spots: spots,
        color: lineColors[index % lineColors.length],
        title: 'Линия ${index + 1}',
      );
    });
  }

  void _generateRandomPieData() {
    final random = Random();
    final List<double> values = List.generate(4, (_) => random.nextDouble());
    final double sum = values.reduce((a, b) => a + b);
    final List<double> percentages = values.map((v) => (v / sum) * 100).toList();

    final List<String> titles = ['First', 'Second', 'Third', 'Fourth'];
    final List<Color> colors = [
      const Color(0xFF4CAF50),
      const Color(0xFF2196F3),
      const Color(0xFFFF9800),
      const Color(0xFF9C27B0),
    ];

    _pieSections = List.generate(4, (i) {
      return _PieSectionData(
        value: percentages[i],
        title: titles[i],
        color: colors[i % colors.length],
        percentageText: '${percentages[i].toStringAsFixed(1)}%',
      );
    });
  }

  Future<void> _loadChartDataForCard(int cardIndex) async {
    if (_cachedLinesData.containsKey(cardIndex)) {
      if (_currentLinesData != _cachedLinesData[cardIndex]) {
        setState(() {
          _currentLinesData = _cachedLinesData[cardIndex]!;
          _chartDataKey++;
        });
      }
      return;
    }

    setState(() => _isChartLoading = true);

    try {
      List<LineChartDataModel> lines = [];

      if (cardIndex == 1) {
        final dynamics = await _stocksDynamicsService.getDynamics(days: 31);
        final fboSpots = <FlSpot>[];
        final xLabels = <String>[];
        for (int i = 0; i < dynamics.length; i++) {
          fboSpots.add(FlSpot(i.toDouble(), dynamics[i].fboTotal.toDouble()));
          xLabels.add(DateFormat('dd.MM').format(dynamics[i].date));
        }
        lines = [
          LineChartDataModel(spots: fboSpots, color: const Color(0xFF4CAF50), title: 'FBO'),
        ];
        _cachedXLabels[cardIndex] = xLabels;
      } else {
        const int pointCount = 31;
        final random = Random();
        _cachedXLabels[cardIndex] = null;
        final List<Color> lineColors = [
          const Color(0xFF4CAF50),
          const Color(0xFF2196F3),
          const Color(0xFFFF9800),
        ];
        lines = List.generate(2, (index) {
          final spots = List.generate(pointCount, (i) => FlSpot(i.toDouble(), 20 + random.nextDouble() * 60));
          return LineChartDataModel(spots: spots, color: lineColors[index % lineColors.length], title: 'Линия ${index + 1}');
        });
      }

      _cachedLinesData[cardIndex] = lines;
      if (mounted) {
        setState(() {
          _currentLinesData = lines;
          _currentXLabels = _cachedXLabels[cardIndex];
          _chartDataKey++;
          _isChartLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isChartLoading = false);
        debugPrint('Ошибка загрузки данных для карточки $cardIndex: $e');
      }
    }
  }

  void _onActiveCardChanged(int? cardIndex) {
    if (cardIndex == null) return;
    _loadChartDataForCard(cardIndex);
  }

  void _onCardHoverChanged(int index, bool isHovered) {
    if (_pinnedCardIndex != null) return;
    if (isHovered) {
      if (_hoveredCardIndex != index) {
        setState(() {
          _hoveredCardIndex = index;
        });
        _onActiveCardChanged(index);
        _chartDataKey++;
        _pieChartKey++;
        _generateRandomPieData();
      }
    } else {
      if (_hoveredCardIndex == index) {
        setState(() {
          _hoveredCardIndex = null;
        });
      }
    }
  }

  void _onCardTap(int index) {
    setState(() {
      if (_pinnedCardIndex == index) return;
      _pinnedCardIndex = index;
      _hoveredCardIndex = null;
    });
    _onActiveCardChanged(index);
    setState(() {
      _chartDataKey++;
      _pieChartKey++;
      _generateRandomPieData();
    });
  }

  void _onOutsideTap() {
    setState(() {
      if (_pinnedCardIndex != null) {
        _pinnedCardIndex = null;
        if (_hoveredCardIndex != null) {
          _onActiveCardChanged(_hoveredCardIndex);
          _chartDataKey++;
          _pieChartKey++;
        }
      }
    });
  }

  bool _isTapOnCard(Offset globalPosition) {
    for (int i = 0; i < _cardKeys.length; i++) {
      final key = _cardKeys[i];
      final context = key.currentContext;
      if (context != null) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          final localPosition = box.globalToLocal(globalPosition);
          if (box.paintBounds.contains(localPosition)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  String _getValueForCard(String categoryKey, String label) {
    if (categoryKey == "Товары") {
      switch (label) {
        case "Всего":
          return _productManager.totalProducts.toString();
        case "С остатками":
          return _countsData?['products_with_any_stock']?.toString() ?? '—';
        case "С остатками FBO":
          return _countsData?['products_with_fbo_stock']?.toString() ?? '—';
        case "С остатками FBS":
          return _countsData?['products_with_fbs_stock']?.toString() ?? '—';
        case "Без остатков":
          return _countsData?['products_without_stock']?.toString() ?? '—';
        default:
          return '—';
      }
    } else if (categoryKey == "Остатки") {
      switch (label) {
        case "Всего":
          return _formatNumber(_countsData?['total_stock_sum']);
        case "FBO":
          return _formatNumber(_countsData?['total_fbo_sum']);
        case "FBS":
          return _formatNumber(_countsData?['total_fbs_sum']);
        default:
          return '—';
      }
    } else if (categoryKey == "Реклама") {
      if (_isCampaignLoading || _campaignStats == null) {
        return '—';
      }
      switch (label) {
        case "Всего кампаний":
          return _campaignStats!['total_campaigns'].toString();
        case "Активных":
          return _campaignStats!['active_campaigns'].toString();
        case "На паузе":
          return _campaignStats!['paused_campaigns'].toString();
        case "Товаров в кампаниях":
          return _campaignStats!['total_products'].toString();
        case "Товаров в Активных":
          return _campaignStats!['active_products'].toString();
        case "Товаров на Паузе":
          return _campaignStats!['paused_products'].toString();
        default:
          return '—';
      }
    }
    // Для прочих карточек – заглушка
    return '—';
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '—';
    final num number = value is num ? value : num.tryParse(value.toString()) ?? 0;
    return NumberFormat.decimalPattern('ru').format(number);
  }

  List<({String label, String value})> _buildCardRows(String categoryKey, List<String> labels) {
    return labels.map((label) {
      final value = _getValueForCard(categoryKey, label);
      return (label: label, value: value);
    }).toList();
  }

  // ========== Секция новостей ==========
  Widget _buildNewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _buildTabButton('Новости портала', 0),
              const SizedBox(width: 16),
              _buildTabButton('Новости РБК: Wildberries', 1),
              const Spacer(),
              if (_selectedNewsTab == 0) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios),
                  iconSize: 20,
                  padding: const EdgeInsets.all(8),
                  tooltip: 'Назад на 5 карточек',
                  onPressed: _canScrollPortalLeft ? _scrollPortalLeft : null,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.amber.shade50,
                    foregroundColor: Colors.amber.shade800,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios),
                  iconSize: 20,
                  padding: const EdgeInsets.all(8),
                  tooltip: 'Вперёд на 5 карточек',
                  onPressed: _canScrollPortalRight ? _scrollPortalRight : null,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.amber.shade50,
                    foregroundColor: Colors.amber.shade800,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ] else ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios),
                  iconSize: 20,
                  padding: const EdgeInsets.all(8),
                  tooltip: 'Назад на 1 карточку',
                  onPressed: _canScrollRbcLeft ? _scrollRbcLeft : null,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.amber.shade50,
                    foregroundColor: Colors.amber.shade800,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios),
                  iconSize: 20,
                  padding: const EdgeInsets.all(8),
                  tooltip: 'Вперёд на 1 карточку',
                  onPressed: _canScrollRbcRight ? _scrollRbcRight : null,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.amber.shade50,
                    foregroundColor: Colors.amber.shade800,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _selectedNewsTab == 0
                ? _buildPortalNewsList()
                : _buildRbcNewsList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTabButton(String text, int tabIndex) {
    final isSelected = _selectedNewsTab == tabIndex;
    return GestureDetector(
      onTap: () => setState(() => _selectedNewsTab = tabIndex),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.amber.shade400 : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.amber.shade800 : Colors.black54,
          ),
        ),
      ),
    );
  }

  Widget _buildPortalNewsList() {
    final news = _newsManager.getLatestNews(100)..sort((a, b) => b.date.compareTo(a.date));
    if (news.isEmpty && _newsManager.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (news.isEmpty) {
      return const Center(child: Text('Нет новостей портала'));
    }
    return ListView.builder(
      controller: _newsScrollController,
      scrollDirection: Axis.horizontal,
      itemCount: news.length,
      itemBuilder: (context, index) {
        final item = news[index];
        return _NewsCard(
          newsItem: item,
          onArchive: () => _newsManager.archiveNews(item.id),
        );
      },
    );
  }

  Widget _buildRbcNewsList() {
    final news = _rbcNewsManager.getLatestNews(100);
    if (news.isEmpty && _rbcNewsManager.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (news.isEmpty) {
      return const Center(child: Text('Нет новостей РБК'));
    }
    return ListView.builder(
      controller: _rbcNewsScrollController,
      scrollDirection: Axis.horizontal,
      itemCount: news.length,
      itemBuilder: (context, index) {
        final item = news[index];
        return _RbcNewsCard(
          key: ValueKey(item.id), // 👈 уникальный ключ
          newsItem: item,
          onArchive: () => _rbcNewsManager.archiveNews(item.id),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomContainerHeight = screenHeight / 3;
    final cardWidth = screenWidth / 7;
    final gapWidth = cardWidth / 7;
    final topChartHeight = screenHeight / 3.5;
    final middleContainerHeight = screenHeight - 100 - topChartHeight - bottomContainerHeight;

    final bool isChartActive = _pinnedCardIndex != null || _hoveredCardIndex != null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        onTapDown: (details) {
          if (!_isTapOnCard(details.globalPosition)) {
            _onOutsideTap();
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            if (isChartActive) ...[
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.92, end: 1.0).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  key: const ValueKey('chart_active'),
                  height: topChartHeight,
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: _isChartLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _AnimatedLineChart(
                    key: ValueKey(_chartDataKey),
                    linesData: _currentLinesData,
                    xLabels: _currentXLabels,
                    duration: const Duration(milliseconds: 5000),
                  ),
                ),
              ),
              SizedBox(
                height: middleContainerHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: SizedBox(
                        key: ValueKey(_pieChartKey),
                        width: 400,
                        height: middleContainerHeight - 16,
                        child: _PieChartWidget(sections: _pieSections),
                      ),
                    ),
                    const SizedBox(width: 32),
                  ],
                ),
              ),
              const Spacer(),
            ] else ...[
              Expanded(child: _buildNewsSection()),
            ],
            Container(
              height: bottomContainerHeight,
              width: double.infinity,
              clipBehavior: Clip.none,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _categories.entries.toList().asMap().entries.map((entry) {
                    final index = entry.key;
                    final category = entry.value;
                    final bool isPinnedGlobal = _pinnedCardIndex != null;
                    final bool isActive = (_pinnedCardIndex == index) ||
                        (!isPinnedGlobal && _hoveredCardIndex == index);
                    final bool allowHover = !isPinnedGlobal;

                    final cardRows = _buildCardRows(category.key, category.value);

                    return Row(
                      children: [
                        _HoverableCard(
                          key: _cardKeys[index],
                          title: category.key,
                          rows: cardRows,
                          width: cardWidth,
                          height: bottomContainerHeight,
                          isActive: isActive,
                          allowHover: allowHover,
                          onHoverChanged: (hovered) => _onCardHoverChanged(index, hovered),
                          onTap: () => _onCardTap(index),
                        ),
                        if (index != _categories.length - 1) SizedBox(width: gapWidth),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== Универсальный анимированный линейный график ==========
class _AnimatedLineChart extends StatefulWidget {
  final List<LineChartDataModel> linesData;
  final Duration duration;
  final List<String>? xLabels;

  const _AnimatedLineChart({
    super.key,
    required this.linesData,
    required this.duration,
    this.xLabels,
  });

  @override
  State<_AnimatedLineChart> createState() => _AnimatedLineChartState();
}

class _AnimatedLineChartState extends State<_AnimatedLineChart>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _widthAnimation;

  // For custom tooltip
  Offset? _tooltipOffset;
  List<_TooltipItem>? _tooltipItems;

  // For vertical line
  double? _verticalLineX; // X position in local coordinates (pixels)
  int? _verticalLineIndex;

  GlobalKey _chartKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _widthAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _AnimatedLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.linesData != widget.linesData) {
      _controller.reset();
      _controller.forward();
      setState(() {
        _tooltipOffset = null;
        _tooltipItems = null;
        _verticalLineX = null;
        _verticalLineIndex = null;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.linesData.isEmpty) return const SizedBox.shrink();

    final double minX = 0;
    final double maxX = (widget.linesData.first.spots.length - 1).toDouble();
    final double maxVal = widget.linesData
        .expand((line) => line.spots.map((s) => s.y))
        .reduce((a, b) => a > b ? a : b);
    final double padding = maxVal * 0.05;
    final double minY = 0;
    final double maxY = maxVal + padding;

    final List<LineChartBarData> bars = widget.linesData.map((line) {
      return LineChartBarData(
        spots: line.spots,
        isCurved: true,
        curveSmoothness: 0.3,
        color: line.color,
        barWidth: 3,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      );
    }).toList();

    // Background chart (grid, axes)
    final backgroundChart = LineChart(
      LineChartData(
        lineTouchData: const LineTouchData(enabled: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 5,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) =>
                  Text(value.toInt().toString(), style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: (maxX - minX) / 5,
              getTitlesWidget: (value, meta) {
                if (value % 1 != 0) return const SizedBox.shrink();
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [],
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        backgroundColor: Colors.white,
      ),
      duration: Duration.zero,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Получаем доступную ширину родителя
        final availableWidth = constraints.maxWidth;

        // Функция для вычисления безопасной позиции тултипа
        Offset? getSafeTooltipOffset(Offset rawOffset, double tooltipWidth, double tooltipHeight) {
          if (rawOffset == null) return null;
          double dx = rawOffset.dx;
          double dy = rawOffset.dy;

          // По умолчанию показываем справа от курсора
          double leftPos = dx + 15;
          // Если не помещается справа – показываем слева
          if (leftPos + tooltipWidth > availableWidth) {
            leftPos = dx - tooltipWidth - 5;
          }
          // Не выходим за левый край
          if (leftPos < 0) leftPos = 5;

          // Корректировка по вертикали, чтобы тултип не уходил за верхнюю границу
          double topPos = dy - tooltipHeight - 10;
          if (topPos < 0) topPos = dy + 10;

          return Offset(leftPos, topPos);
        }

        return Stack(
          children: [
            backgroundChart,
            // Вертикальная линия
            if (_verticalLineX != null)
              Positioned(
                left: _verticalLineX,
                top: 0,
                child: CustomPaint(
                  painter: _DashedLinePainter(
                    color: Colors.grey,
                    strokeWidth: 1.0,
                    dashLength: 5,
                    dashSpace: 3,
                    height: MediaQuery.of(context).size.height,
                  ),
                  size: Size(1, MediaQuery.of(context).size.height),
                ),
              ),
            // Анимированные линии графика
            AnimatedBuilder(
              animation: _widthAnimation,
              builder: (context, child) {
                return ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: _widthAnimation.value,
                    child: MouseRegion(
                      onHover: (PointerHoverEvent event) => _handleTouch(event.localPosition),
                      onExit: (_) => _hideTooltip(),
                      child: Container(
                        key: _chartKey,
                        child: LineChart(
                          LineChartData(
                            lineTouchData: LineTouchData(
                              enabled: false,
                              handleBuiltInTouches: false,
                            ),
                            gridData: const FlGridData(show: false),
                            titlesData: const FlTitlesData(show: false),
                            borderData: FlBorderData(show: false),
                            lineBarsData: bars,
                            minX: minX,
                            maxX: maxX,
                            minY: minY,
                            maxY: maxY,
                            backgroundColor: Colors.transparent,
                          ),
                          duration: Duration.zero,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // Кастомный тултип с динамической позицией
            // Кастомный тултип с динамической позицией
            if (_tooltipOffset != null && _tooltipItems != null && _tooltipItems!.isNotEmpty)
              Builder(
                builder: (context) {
                  // Увеличиваем высоту, чтобы учесть дополнительную строку с датой
                  final double estimatedTooltipWidth = 250;
                  final double estimatedTooltipHeight = (_tooltipItems!.length * 28 + 40).toDouble();

                  final safeOffset = getSafeTooltipOffset(_tooltipOffset!, estimatedTooltipWidth, estimatedTooltipHeight);
                  if (safeOffset == null) return const SizedBox.shrink();

                  // Берем дату из первого элемента (она общая для всех)
                  final String commonDate = _tooltipItems!.first.date;

                  return Positioned(
                    left: safeOffset.dx,
                    top: safeOffset.dy,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.black87,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              commonDate,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ..._tooltipItems!.map((item) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      color: item.color,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${item.title}: ${item.value}',
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  void _handleTouch(Offset localPosition) {
    final RenderBox? renderBox = _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Size chartSize = renderBox.size;
    final double chartWidth = chartSize.width;
    final double chartHeight = chartSize.height;

    final double xRatio = localPosition.dx / chartWidth;
    final double xValue = xRatio * (widget.linesData.first.spots.length - 1);
    final int nearestIndex = (xValue).round().clamp(0, widget.linesData.first.spots.length - 1);
    final double pointX = (nearestIndex / (widget.linesData.first.spots.length - 1)) * chartWidth;
    setState(() {
      _verticalLineX = pointX;
      _verticalLineIndex = nearestIndex;
    });

    final tooltipItems = <_TooltipItem>[];
    for (int i = 0; i < widget.linesData.length; i++) {
      final line = widget.linesData[i];
      final spot = line.spots[nearestIndex];
      final String dateString;
      if (widget.xLabels != null && nearestIndex < widget.xLabels!.length) {
        dateString = widget.xLabels![nearestIndex];
      } else {
        dateString = 'День ${nearestIndex + 1}';
      }

      // Целое число с разделением разрядов
      final intValue = spot.y.round();
      final formatter = NumberFormat.decimalPattern('ru');
      final valueString = formatter.format(intValue);

      tooltipItems.add(_TooltipItem(
        title: line.title,
        date: dateString,
        value: valueString,
        color: line.color,
      ));
    }

    setState(() {
      _tooltipItems = tooltipItems;
      _tooltipOffset = localPosition;
    });
  }

  void _hideTooltip() {
    setState(() {
      _tooltipOffset = null;
      _tooltipItems = null;
      _verticalLineX = null;
      _verticalLineIndex = null;
    });
  }
}

// Painter for dashed vertical line
class _DashedLinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double dashSpace;
  final double height;

  _DashedLinePainter({
    required this.color,
    required this.strokeWidth,
    required this.dashLength,
    required this.dashSpace,
    required this.height,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    double startY = 0;
    while (startY < height) {
      final endY = startY + dashLength;
      canvas.drawLine(Offset(0, startY), Offset(0, endY), paint);
      startY += dashLength + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.dashSpace != dashSpace ||
        oldDelegate.height != height;
  }
}

// Вспомогательный класс для элементов подсказки
class _TooltipItem {
  final String title;
  final String date;
  final String value;
  final Color color;

  _TooltipItem({
    required this.title,
    required this.date,
    required this.value,
    required this.color,
  });
}

// ========== Круговая диаграмма (без изменений) ==========
class _PieSectionData {
  final double value;
  final String title;
  final Color color;
  final String percentageText;
  _PieSectionData({
    required this.value,
    required this.title,
    required this.color,
    required this.percentageText,
  });
}

class _PieChartWidget extends StatefulWidget {
  final List<_PieSectionData> sections;
  const _PieChartWidget({super.key, required this.sections});

  @override
  State<_PieChartWidget> createState() => _PieChartWidgetState();
}

class _PieChartWidgetState extends State<_PieChartWidget> {
  int touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.3,
      child: Row(
        children: [
          const SizedBox(height: 18),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: PieChart(
                PieChartData(
                  pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent event, pieTouchResponse) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            pieTouchResponse == null ||
                            pieTouchResponse.touchedSection == null) {
                          touchedIndex = -1;
                          return;
                        }
                        touchedIndex = pieTouchResponse
                            .touchedSection!.touchedSectionIndex;
                      });
                    },
                  ),
                  borderData: FlBorderData(show: false),
                  sectionsSpace: 0,
                  centerSpaceRadius: 40,
                  sections: _buildSections(),
                ),
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widget.sections.map((section) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _Indicator(
                  color: section.color,
                  text: section.title,
                  isSquare: true,
                ),
              );
            }).toList(),
          ),
          const SizedBox(width: 28),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildSections() {
    return List.generate(widget.sections.length, (i) {
      final section = widget.sections[i];
      final isTouched = i == touchedIndex;
      final fontSize = isTouched ? 25.0 : 16.0;
      final radius = isTouched ? 60.0 : 50.0;
      const shadows = [Shadow(color: Colors.black, blurRadius: 2)];

      return PieChartSectionData(
        color: section.color,
        value: section.value,
        title: section.percentageText,
        radius: radius,
        titleStyle: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          shadows: shadows,
        ),
      );
    });
  }
}

class _Indicator extends StatelessWidget {
  final Color color;
  final String text;
  final bool isSquare;

  const _Indicator({
    required this.color,
    required this.text,
    this.isSquare = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: isSquare ? BoxShape.rectangle : BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// ========== Интерактивная карточка (без изменений) ==========
class _HoverableCard extends StatefulWidget {
  final String title;
  final List<({String label, String value})> rows;
  final double width;
  final double height;
  final bool isActive;
  final bool allowHover;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;

  const _HoverableCard({
    super.key,
    required this.title,
    required this.rows,
    required this.width,
    required this.height,
    required this.isActive,
    required this.allowHover,
    required this.onHoverChanged,
    required this.onTap,
  });

  @override
  State<_HoverableCard> createState() => _HoverableCardState();
}

class _HoverableCardState extends State<_HoverableCard> {
  static const Duration _animationDuration = Duration(milliseconds: 250);
  static const Curve _animationCurve = Curves.easeOutCubic;
  static const double _hoverRaise = -14.0;
  static const double _hoverScale = 1.05;
  static const double _hoverBlur = 20.0;
  static const double _hoverSpread = 4.0;
  static const double _hoverShadowOpacity = 0.35;

  void _handleMouseEnter(_) {
    if (widget.allowHover) {
      widget.onHoverChanged(true);
    }
  }

  void _handleMouseExit(_) {
    if (widget.allowHover) {
      widget.onHoverChanged(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: _handleMouseEnter,
        onExit: _handleMouseExit,
        child: Transform.translate(
          offset: Offset(0, widget.isActive ? _hoverRaise : 0),
          child: AnimatedScale(
            duration: _animationDuration,
            curve: _animationCurve,
            scale: widget.isActive ? _hoverScale : 1.0,
            child: _buildCardContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildCardContent() {
    final normalColor = Colors.grey.shade50;
    final activeColor = const Color(0xFFFFF9E6);
    final backgroundColor = widget.isActive ? activeColor : normalColor;

    final borderColor = widget.isActive
        ? Colors.amber.shade300.withOpacity(0.8)
        : Colors.grey.shade200;

    final titleColor = widget.isActive ? const Color(0xFFB8860B) : Colors.black54;

    final List<BoxShadow>? boxShadows = widget.isActive
        ? [
      BoxShadow(
        color: Colors.black.withOpacity(_hoverShadowOpacity),
        blurRadius: _hoverBlur,
        spreadRadius: _hoverSpread,
        offset: const Offset(0, -3),
      ),
      BoxShadow(
        color: Colors.black.withOpacity(0.2),
        blurRadius: 12,
        offset: const Offset(0, 8),
      ),
    ]
        : null;

    return AnimatedContainer(
      duration: _animationDuration,
      curve: _animationCurve,
      width: widget.width,
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: boxShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedDefaultTextStyle(
            duration: _animationDuration,
            curve: _animationCurve,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: titleColor,
            ),
            child: Text(widget.title),
          ),
          const SizedBox(height: 12),
          ...widget.rows.map((row) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(row.label, style: const TextStyle(fontSize: 13)),
                Text(
                  row.value,
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.isActive ? Colors.grey.shade600 : Colors.grey,
                  ),
                ),
              ],
            ),
          )),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.settings),
                iconSize: 28,
                color: widget.isActive ? Colors.amber.shade700 : Colors.grey.shade600,
                onPressed: () {},
                tooltip: 'Настройки',
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.cloud),
                iconSize: 28,
                color: widget.isActive ? Colors.amber.shade700 : Colors.grey.shade600,
                onPressed: () {},
                tooltip: 'Процессы',
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ========== Карточка новости портала (без изменений) ==========
class _NewsCard extends StatelessWidget {
  final NewsItem newsItem;
  final VoidCallback onArchive;

  const _NewsCard({required this.newsItem, required this.onArchive});

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Сегодня ${_twoDigits(date.hour)}:${_twoDigits(date.minute)}';
    }
    return '${_twoDigits(date.day)}.${_twoDigits(date.month)}.${date.year}';
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  String _formatContent(String content) {
    String cleaned = content.replaceAll('\n', ' ');
    final buffer = StringBuffer();
    int i = 0;

    while (i < cleaned.length) {
      final ch = cleaned[i];
      if (ch == '.') {
        bool isSentenceEnd = false;
        if (i > 0 && _isLetter(cleaned[i - 1])) {
          int nextNonSpace = i + 1;
          while (nextNonSpace < cleaned.length && cleaned[nextNonSpace] == ' ') {
            nextNonSpace++;
          }
          if (nextNonSpace < cleaned.length && _isLetter(cleaned[nextNonSpace])) {
            final isAbbreviation = i >= 2 && ['т.', 'Т.', 'д.', 'Д.', 'пр'].contains(cleaned.substring(i - 2, i));
            if (!isAbbreviation) {
              isSentenceEnd = true;
            }
          }
        }
        if (isSentenceEnd) {
          buffer.write('.\n\n');
          while (i + 1 < cleaned.length && cleaned[i + 1] == ' ') {
            i++;
          }
        } else {
          buffer.write(ch);
        }
      } else {
        buffer.write(ch);
      }
      i++;
    }
    return buffer.toString();
  }

  bool _isLetter(String ch) {
    return RegExp(r'^[a-zA-Zа-яА-Я]$').hasMatch(ch);
  }

  @override
  Widget build(BuildContext context) {
    final validTypes = newsItem.types
        .where((t) => t.containsKey('name') && t['name'] != null && t['name'].toString().isNotEmpty)
        .toList();

    return Container(
      width: 320,
      height: 420,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.amber.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (validTypes.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: validTypes.map((t) {
                final typeName = t['name'].toString();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300, width: 0.5),
                  ),
                  child: Text(
                    typeName,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            newsItem.header,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            softWrap: true,
          ),
          const SizedBox(height: 6),
          Text(
            _formatDate(newsItem.date),
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                _formatContent(newsItem.content),
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onArchive,
              icon: const Icon(Icons.remove_red_eye, size: 18),
              label: const Text('Ознакомлен'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.amber.shade800,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ========== Карточка новости РБК (без изменений) ==========
class _RbcNewsCard extends StatefulWidget {
  final RbcNewsItem newsItem;
  final VoidCallback onArchive;

  const _RbcNewsCard({
    super.key,                     // ← добавляем ключ
    required this.newsItem,
    required this.onArchive,
  });

  @override
  State<_RbcNewsCard> createState() => _RbcNewsCardState();
}

class _RbcNewsCardState extends State<_RbcNewsCard> {
  String? _fullContent;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadFullContent();
  }

  Future<void> _loadFullContent() async {
    if (_fullContent != null) return;
    setState(() => _isLoading = true);
    final content = await RbcNewsManager().fetchFullArticleContent(widget.newsItem.url);
    if (mounted) {
      setState(() {
        _fullContent = content;
        _isLoading = false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _RbcNewsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Если ID новости изменился (например, при переиспользовании виджета),
    // сбрасываем загруженный контент и загружаем заново.
    if (oldWidget.newsItem.id != widget.newsItem.id) {
      _fullContent = null;
      _loadFullContent();
    }
  }


  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Сегодня ${_twoDigits(date.hour)}:${_twoDigits(date.minute)}';
    }
    return '${_twoDigits(date.day)}.${_twoDigits(date.month)}.${date.year}';
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final displayText = _fullContent ??
        (widget.newsItem.body.isNotEmpty ? widget.newsItem.body : 'Загрузка текста...');

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: 640,
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.amber.shade200, width: 1),
          ),
          height: constraints.maxHeight,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 60,
                  child: Text(
                    widget.newsItem.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatDate(widget.newsItem.date),
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                if (widget.newsItem.imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      widget.newsItem.imageUrl,
                      width: double.infinity,
                      height: 312,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: double.infinity,
                        height: 312,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (_isLoading && _fullContent == null)
                  const LinearProgressIndicator(),
                Text(
                  displayText,
                  style: const TextStyle(fontSize: 18, height: 1.4),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: widget.onArchive,
                    icon: const Icon(Icons.remove_red_eye, size: 18),
                    label: const Text('Ознакомлен'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.amber.shade800,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}