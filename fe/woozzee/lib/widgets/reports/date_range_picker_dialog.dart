import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../providers/reports_sync_provider.dart';

class DateRangePickerDialog extends StatefulWidget {
  final DateTimeRange? initialDateRange;
  final Map<DateTime, bool> localDateAvailability;
  final Map<DateTime, bool> serverDateAvailability;
  final bool checkingServerDates;
  final ReportsSyncProvider provider;
  final Future<void> Function()? onRefresh;

  const DateRangePickerDialog({
    Key? key,
    this.initialDateRange,
    required this.localDateAvailability,
    required this.serverDateAvailability,
    required this.checkingServerDates,
    required this.provider,
    this.onRefresh,
  }) : super(key: key);

  @override
  _DateRangePickerDialogState createState() => _DateRangePickerDialogState();
}

class _DateRangePickerDialogState extends State<DateRangePickerDialog> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedStart;
  DateTime? _selectedEnd;
  DateTimeRange? _selectedRange;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDateRange != null) {
      _selectedStart = widget.initialDateRange!.start;
      _selectedEnd = widget.initialDateRange!.end;
      _selectedRange = widget.initialDateRange;
      _focusedDay = widget.initialDateRange!.start;
    } else {
      _focusedDay = DateTime.now();
    }
  }

  String _formatDate(DateTime date) => DateFormat('dd.MM.yyyy').format(date);
  DateTime _normalizeDateToUtc(DateTime date) => DateTime.utc(date.year, date.month, date.day);

  String _getDateStats() {
    int totalDates = widget.localDateAvailability.length;
    int loadedDates = widget.localDateAvailability.values.where((v) => v).length;
    int serverDates = widget.serverDateAvailability.values.where((v) => v).length;
    return 'Загружено: $loadedDates/$totalDates • Доступно на сервере: $serverDates';
  }

  Future<void> _refreshDateAvailability() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      if (widget.onRefresh != null) await widget.onRefresh!();
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        height: 525,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Выберите диапазон дат', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                if (widget.onRefresh != null)
                  IconButton(
                    icon: _isRefreshing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
                    onPressed: _isRefreshing ? null : _refreshDateAvailability,
                    tooltip: 'Обновить данные о датах',
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_getDateStats(), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            if (widget.checkingServerDates || _isRefreshing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Загружаем данные о датах...'),
                ]),
              ),
            Container(
              height: 360,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: TableCalendar(
                firstDay: DateTime(2025, 9, 1),
                lastDay: DateTime.now(),
                focusedDay: _focusedDay,
                startingDayOfWeek: StartingDayOfWeek.monday,
                locale: 'ru_RU',
                selectedDayPredicate: (day) => isSameDay(_selectedStart, day) || isSameDay(_selectedEnd, day),
                rangeStartDay: _selectedStart,
                rangeEndDay: _selectedEnd,
                calendarFormat: _calendarFormat,
                rangeSelectionMode: RangeSelectionMode.toggledOn,
                onDaySelected: (selectedDay, focusedDay) {
                  if (_selectedStart == null || _selectedEnd != null) {
                    _selectedStart = selectedDay;
                    _selectedEnd = null;
                    _selectedRange = null;
                  } else {
                    if (selectedDay.isBefore(_selectedStart!)) {
                      _selectedEnd = _selectedStart;
                      _selectedStart = selectedDay;
                    } else {
                      _selectedEnd = selectedDay;
                    }
                    _selectedRange = DateTimeRange(start: _selectedStart!, end: _selectedEnd!);
                  }
                  setState(() {});
                },
                onPageChanged: (focusedDay) => setState(() => _focusedDay = focusedDay),
                onFormatChanged: (format) => setState(() => _calendarFormat = format),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, date, _) {
                    final normalizedDate = _normalizeDateToUtc(date);
                    final hasLocalData = widget.localDateAvailability[normalizedDate] ?? false;
                    final hasServerData = widget.serverDateAvailability[normalizedDate] ?? false;
                    final isToday = isSameDay(date, DateTime.now());
                    final isSelected = isSameDay(_selectedStart, date) || isSameDay(_selectedEnd, date) ||
                        (date.isAfter(_selectedStart ?? DateTime(0)) && date.isBefore((_selectedEnd?.add(const Duration(days: 1)) ?? DateTime(0))));
                    Color backgroundColor, borderColor, textColor;
                    if (isSelected) {
                      backgroundColor = Theme.of(context).primaryColor;
                      borderColor = Theme.of(context).primaryColor;
                      textColor = Colors.white;
                    } else if (isToday) {
                      backgroundColor = Colors.blue[50]!;
                      borderColor = Colors.blue;
                      textColor = Colors.blue[800]!;
                    } else if (hasLocalData) {
                      backgroundColor = Colors.green.withOpacity(0.1);
                      borderColor = hasServerData ? Colors.green : Colors.orange;
                      textColor = Colors.green[800]!;
                    } else if (hasServerData) {
                      backgroundColor = Colors.orange.withOpacity(0.1);
                      borderColor = Colors.orange;
                      textColor = Colors.orange[800]!;
                    } else if (date.isAfter(DateTime.now())) {
                      backgroundColor = Colors.grey[100]!;
                      borderColor = Colors.grey[300]!;
                      textColor = Colors.grey[600]!;
                    } else {
                      backgroundColor = Colors.red.withOpacity(0.05);
                      borderColor = Colors.red.withOpacity(0.3);
                      textColor = Colors.red[800]!;
                    }
                    return Container(
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor, width: 1.5),
                        boxShadow: isSelected ? [BoxShadow(color: Theme.of(context).primaryColor.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))] : null,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('${date.day}', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
                            if (hasLocalData || hasServerData)
                              Container(margin: const EdgeInsets.only(top: 2), width: 6, height: 6, decoration: BoxDecoration(color: hasLocalData ? Colors.green : Colors.orange, shape: BoxShape.circle)),
                          ],
                        ),
                      ),
                    );
                  },
                  todayBuilder: (context, date, _) {
                    final hasLocalData = widget.localDateAvailability[_normalizeDateToUtc(date)] ?? false;
                    return Container(
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue, width: 2)),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('${date.day}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 14)),
                            if (hasLocalData) Container(margin: const EdgeInsets.only(top: 2), width: 6, height: 6, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                          ],
                        ),
                      ),
                    );
                  },
                  selectedBuilder: (context, date, _) => Container(
                    margin: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Theme.of(context).primaryColor, width: 2),
                      boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))],
                    ),
                    child: Center(child: Text('${date.day}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                  ),
                ),
                rowHeight: 45,
                headerStyle: HeaderStyle(
                  titleCentered: true,
                  formatButtonVisible: true,
                  formatButtonShowsNext: false,
                  formatButtonDecoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(6)),
                  formatButtonTextStyle: const TextStyle(color: Colors.black),
                  leftChevronIcon: const Icon(Icons.chevron_left),
                  rightChevronIcon: const Icon(Icons.chevron_right),
                  headerPadding: const EdgeInsets.symmetric(vertical: 8),
                  titleTextStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(weekdayStyle: TextStyle(fontWeight: FontWeight.bold), weekendStyle: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.localDateAvailability.isEmpty && !widget.checkingServerDates)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber)),
                child: Row(children: const [Icon(Icons.info_outline, color: Colors.amber, size: 20), SizedBox(width: 8), Expanded(child: Text('Данные о датах еще загружаются. Некоторые даты могут отображаться некорректно.', style: TextStyle(fontSize: 11, color: Colors.amber)))]),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена'), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12))),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _selectedRange != null ? () => Navigator.pop(context, _selectedRange) : null,
                  child: const Text('Выбрать диапазон'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}