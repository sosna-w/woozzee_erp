import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';

class CustomColumnMenuDelegate implements PlutoColumnMenuDelegate<PlutoGridColumnMenuItem> {
  final Function(PlutoColumn) onFreezeLeft;
  final Function(PlutoColumn) onFreezeRight;
  final Function(PlutoColumn) onUnfreeze;
  final Function(PlutoColumn) onToggleHide;
  final Function() onShowAllColumns;

  const CustomColumnMenuDelegate({
    required this.onFreezeLeft,
    required this.onFreezeRight,
    required this.onUnfreeze,
    required this.onToggleHide,
    required this.onShowAllColumns,
  });

  @override
  List<PopupMenuEntry<PlutoGridColumnMenuItem>> buildMenuItems({
    required PlutoGridStateManager stateManager,
    required PlutoColumn column,
  }) {
    final bool isFrozenLeft = column.frozen == PlutoColumnFrozen.start;
    final bool isFrozenRight = column.frozen == PlutoColumnFrozen.end;
    final bool isHidden = column.hide;
    final Color textColor = stateManager.style.cellTextStyle.color ?? Colors.black;

    return [
      PopupMenuItem<PlutoGridColumnMenuItem>(
        value: PlutoGridColumnMenuItem.freezeToStart,
        height: 36,
        child: Row(
          children: [
            Icon(Icons.pin_end, size: 20, color: isFrozenLeft ? Colors.blue : textColor),
            const SizedBox(width: 8),
            Text('Закрепить слева', style: TextStyle(color: isFrozenLeft ? Colors.blue : textColor, fontWeight: isFrozenLeft ? FontWeight.bold : null)),
          ],
        ),
      ),
      PopupMenuItem<PlutoGridColumnMenuItem>(
        value: PlutoGridColumnMenuItem.freezeToEnd,
        height: 36,
        child: Row(
          children: [
            Icon(Icons.pin_end, size: 20, color: isFrozenRight ? Colors.blue : textColor),
            const SizedBox(width: 8),
            Text('Закрепить справа', style: TextStyle(color: isFrozenRight ? Colors.blue : textColor, fontWeight: isFrozenRight ? FontWeight.bold : null)),
          ],
        ),
      ),
      PopupMenuItem<PlutoGridColumnMenuItem>(
        value: PlutoGridColumnMenuItem.unfreeze,
        height: 36,
        enabled: isFrozenLeft || isFrozenRight,
        child: Row(
          children: [
            Icon(Icons.unfold_more, size: 20, color: textColor),
            const SizedBox(width: 8),
            const Text('Снять закрепление'),
          ],
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<PlutoGridColumnMenuItem>(
        value: PlutoGridColumnMenuItem.hideColumn,
        height: 36,
        child: Row(
          children: [
            Icon(isHidden ? Icons.visibility : Icons.visibility_off, size: 20, color: textColor),
            const SizedBox(width: 8),
            Text(isHidden ? 'Показать столбец' : 'Скрыть столбец'),
          ],
        ),
      ),
      if (column.field.startsWith('custom_'))
        PopupMenuItem<PlutoGridColumnMenuItem>(
          value: null, // сигнал для удаления
          height: 36,
          child: Row(
            children: [
              Icon(Icons.delete, size: 20, color: Colors.red[700]),
              const SizedBox(width: 8),
              Text('Удалить столбец', style: TextStyle(color: Colors.red[700])),
            ],
          ),
        ),
      if (!column.field.startsWith('custom_'))
        PopupMenuItem<PlutoGridColumnMenuItem>(
          value: null,
          height: 36,
          child: Row(
            children: [
              Icon(Icons.view_column, size: 20, color: textColor),
              const SizedBox(width: 8),
              const Text('Показать все столбцы'),
            ],
          ),
        ),
    ];
  }

  @override
  void onSelected({
    required BuildContext context,
    required PlutoGridStateManager stateManager,
    required PlutoColumn column,
    required bool mounted,
    required PlutoGridColumnMenuItem? selected,
  }) {
    switch (selected) {
      case PlutoGridColumnMenuItem.unfreeze:
        onUnfreeze(column);
        break;
      case PlutoGridColumnMenuItem.freezeToStart:
        onFreezeLeft(column);
        break;
      case PlutoGridColumnMenuItem.freezeToEnd:
        onFreezeRight(column);
        break;
      case PlutoGridColumnMenuItem.hideColumn:
        onToggleHide(column);
        break;
      case null:
        if (column.field.startsWith('custom_')) {
          // Удаление кастомной колонки – обработка в ReportsScreen
          // Здесь ничего не делаем, пусть родитель сам обрабатывает
        } else {
          onShowAllColumns();
        }
        break;
      default:
        const PlutoColumnMenuDelegateDefault().onSelected(
          context: context,
          stateManager: stateManager,
          column: column,
          mounted: mounted,
          selected: selected,
        );
    }
  }
}