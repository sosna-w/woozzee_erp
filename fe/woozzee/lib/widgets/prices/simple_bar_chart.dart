import 'package:flutter/material.dart';
import 'empty_bar.dart';
import 'bar_with_hover.dart';

class SimpleBarChart extends StatelessWidget {
  final List<double>? values;
  final List<String>? labels;
  final List<DateTime>? dates;
  final int barCount;
  final double barWidth;
  final double maxHeight;
  final Color barColor;
  final void Function(int index)? onBarTap;
  final double minBarHeight;

  const SimpleBarChart({
    Key? key,
    this.values,
    this.labels,
    this.dates,
    this.barCount = 21,
    this.barWidth = 4,
    this.maxHeight = 40,
    this.barColor = Colors.grey,
    this.minBarHeight = 2.0,
    this.onBarTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool hasData = values != null && values!.length == barCount;
    if (!hasData) return const SizedBox.shrink();

    final List<double> chartValues = values!;
    final double maxVal = chartValues.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return const SizedBox.shrink();

    final double minPositive = chartValues
        .where((v) => v > 0)
        .fold<double>(double.infinity, (a, b) => a < b ? a : b);
    final bool allSame = (minPositive == maxVal);

    return Container(
      height: maxHeight,
      alignment: Alignment.bottomCenter,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(barCount, (i) {
          final double value = chartValues[i];
          if (value == 0) return EmptyBar(width: barWidth);

          double height;
          if (allSame) {
            height = maxHeight;
          } else {
            height = minBarHeight +
                (value - minPositive) / (maxVal - minPositive) *
                    (maxHeight - minBarHeight);
          }

          if (height < 0.1) return EmptyBar(width: barWidth);

          final label = labels != null && i < labels!.length ? labels![i] : '';
          final dateTime = dates != null && i < dates!.length ? dates![i] : null;

          return BarWithHover(
            value: value,
            label: label,
            onTap: onBarTap != null ? () => onBarTap!(i) : null,
            dateTime: dateTime,
            width: barWidth,
            height: height,
            baseColor: barColor,
          );
        }),
      ),
    );
  }
}