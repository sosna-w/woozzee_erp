// bottom_nav_bar.dart - без подсказки конструктора

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../utils/constants.dart';

class BottomNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final Function(int)? onLongPressStart;
  final Function(int)? onLongPressEnd;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
    this.onLongPressStart,
    this.onLongPressEnd,
  });

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> with WindowListener {
  bool _isFullScreen = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkFullScreenStatus();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkFullScreenStatus() async {
    try {
      final isFullScreen = await windowManager.isFullScreen();
      if (mounted) {
        setState(() {
          _isFullScreen = isFullScreen;
        });
      }
    } catch (e) {
      print('Error checking full screen status: $e');
    }
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) {
      setState(() {
        _isFullScreen = true;
      });
    }
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) {
      setState(() {
        _isFullScreen = false;
      });
    }
  }

  @override
  void onWindowFocus() {
    _checkFullScreenStatus();
  }

  @override
  Widget build(BuildContext context) {
    final showText = _isFullScreen;
    final totalNavItemsWidth = _calculateTotalNavItemsWidth(showText);

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canCenter = totalNavItemsWidth <= constraints.maxWidth;

          final navItemsWidget = List.generate(navItems.length, (index) {
            return _buildNavItem(
              context,
              navItems[index].title,
              navItems[index].icon,
              index,
              showText: showText,
            );
          });

          if (canCenter) {
            return Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: navItemsWidget,
              ),
            );
          } else {
            return Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              thickness: 4,
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: navItemsWidget,
                ),
              ),
            );
          }
        },
      ),
    );
  }

  double _calculateTotalNavItemsWidth(bool showText) {
    final itemWidth = showText ? 140.0 : 80.0;
    final spacing = 4.0;
    return (navItems.length * itemWidth) + ((navItems.length - 1) * spacing);
  }

  Widget _buildNavItem(
    BuildContext context,
    String title,
    IconData icon,
    int index, {
    required bool showText,
  }) {
    final isSelected = widget.currentIndex == index;
    final hasLongPress = widget.onLongPressStart != null && widget.onLongPressEnd != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: hasLongPress ? () {} : null,
      onLongPressStart: hasLongPress ? (details) => widget.onLongPressStart!(index) : null,
      onLongPressEnd: hasLongPress ? (details) => widget.onLongPressEnd!(index) : null,
      child: Container(
        constraints: BoxConstraints(
          minWidth: showText ? 100 : 60,
          maxWidth: showText ? 140 : 80,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => widget.onIndexChanged(index),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: showText
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                  : const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: isSelected
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1,
                      )
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: showText ? 18 : 22,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                  if (showText) ...[
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}