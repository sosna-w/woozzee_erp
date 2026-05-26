import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/stocks_history_data.dart';
import '../../utils/stocks_history_manager.dart';
import 'simple_bar_chart.dart';

class FBOStocksChart extends StatelessWidget {
  final int nmId;
  final Future<List<StocksHistoryData>> futureHistory;

  const FBOStocksChart({
    Key? key,
    required this.nmId,
    required this.futureHistory,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StocksHistoryData>>(
      future: futureHistory,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (snapshot.hasError) {
          return const SizedBox.shrink();
        }
        final history = snapshot.data ?? [];
        if (history.isEmpty) return const SizedBox.shrink();

        final Map<DateTime, List<StocksHistoryData>> groupedByDay = {};
        for (var record in history) {
          final localDate = record.createdAt.toLocal();
          final date = DateTime(localDate.year, localDate.month, localDate.day);
          groupedByDay.putIfAbsent(date, () => []).add(record);
        }

        final Map<DateTime, int> dailyLastQuantity = {};
        for (var entry in groupedByDay.entries) {
          final dayRecords = entry.value;
          dayRecords.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          dailyLastQuantity[entry.key] = dayRecords.last.totalQuantity;
        }

        final nowLocal = DateTime.now();
        final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
        final List<DateTime> last21Dates = List.generate(21, (index) {
          return today.subtract(Duration(days: 20 - index));
        });

        final List<double> values = [];
        final List<String> labels = [];
        for (var date in last21Dates) {
          final quantity = dailyLastQuantity[date]?.toDouble() ?? 0.0;
          values.add(quantity);
          labels.add(DateFormat('dd.MM').format(date));
        }

        if (values.every((v) => v == 0)) return const SizedBox.shrink();

        return SimpleBarChart(
          values: values,
          labels: labels,
          dates: last21Dates,
          barCount: 21,
          barWidth: 4,
          maxHeight: 40,
          barColor: Colors.blue,
        );
      },
    );
  }
}