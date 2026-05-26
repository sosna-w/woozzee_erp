import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

class SimpleDateRangePickerDialog extends StatefulWidget {
  final DateTimeRange? initialRange;
  final void Function(DateTimeRange) onConfirm;

  const SimpleDateRangePickerDialog({
    Key? key,
    this.initialRange,
    required this.onConfirm,
  }) : super(key: key);

  @override
  State<SimpleDateRangePickerDialog> createState() =>
      _SimpleDateRangePickerDialogState();
}

class _SimpleDateRangePickerDialogState extends State<SimpleDateRangePickerDialog> {
  late DateTime _focusedDay;
  DateTime? _selectedStart;
  DateTime? _selectedEnd;
  DateTimeRange? _selectedRange;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  late final DateTime _minDate;
  late final DateTime _maxDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _minDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
    _maxDate = DateTime(now.year, now.month, now.day);

    if (widget.initialRange != null) {
      _selectedStart = widget.initialRange!.start;
      _selectedEnd = widget.initialRange!.end;
      _selectedRange = widget.initialRange;
      _focusedDay = widget.initialRange!.start;
    } else {
      _focusedDay = _maxDate;
    }
  }

  String _formatDate(DateTime date) => DateFormat('dd.MM.yyyy').format(date);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Выберите диапазон дат',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              height: 360,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: TableCalendar(
                firstDay: _minDate,
                lastDay: _maxDate,
                focusedDay: _focusedDay,
                startingDayOfWeek: StartingDayOfWeek.monday,
                locale: 'ru_RU',
                calendarFormat: _calendarFormat,
                rangeSelectionMode: RangeSelectionMode.toggledOn,
                rangeStartDay: _selectedStart,
                rangeEndDay: _selectedEnd,
                enabledDayPredicate: (day) =>
                    day.isAfter(_minDate.subtract(const Duration(days: 1))) &&
                    day.isBefore(_maxDate.add(const Duration(days: 1))),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
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
                      _selectedRange = DateTimeRange(
                        start: _selectedStart!,
                        end: _selectedEnd!,
                      );
                    }
                    _focusedDay = focusedDay;
                  });
                },
                onPageChanged: (focusedDay) => setState(() => _focusedDay = focusedDay),
                onFormatChanged: (format) => setState(() => _calendarFormat = format),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, date, _) {
                    final bool isAvailable =
                        date.isAfter(_minDate.subtract(const Duration(days: 1))) &&
                        date.isBefore(_maxDate.add(const Duration(days: 1)));
                    final bool isSelected = date == _selectedStart ||
                        date == _selectedEnd ||
                        (_selectedStart != null &&
                            _selectedEnd != null &&
                            date.isAfter(_selectedStart!) &&
                            date.isBefore(_selectedEnd!));
                    final bool isToday = DateUtils.isSameDay(date, DateTime.now());

                    Color backgroundColor;
                    Color borderColor;
                    Color textColor;

                    if (isSelected) {
                      backgroundColor = Theme.of(context).primaryColor;
                      borderColor = Theme.of(context).primaryColor;
                      textColor = Colors.white;
                    } else if (isToday) {
                      backgroundColor = Colors.blue[50]!;
                      borderColor = Colors.blue;
                      textColor = Colors.blue[800]!;
                    } else if (isAvailable) {
                      backgroundColor = Colors.green.withOpacity(0.1);
                      borderColor = Colors.green;
                      textColor = Colors.green[800]!;
                    } else {
                      backgroundColor = Colors.grey[100]!;
                      borderColor = Colors.grey[300]!;
                      textColor = Colors.grey[600]!;
                    }

                    return Container(
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor, width: 1.5),
                        boxShadow: isSelected
                            ? [
                          BoxShadow(
                            color: Theme.of(context).primaryColor.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                rowHeight: 45,
                headerStyle: HeaderStyle(
                  titleCentered: true,
                  formatButtonVisible: true,
                  formatButtonShowsNext: false,
                  formatButtonDecoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  formatButtonTextStyle: const TextStyle(color: Colors.black),
                  leftChevronIcon: const Icon(Icons.chevron_left),
                  rightChevronIcon: const Icon(Icons.chevron_right),
                  headerPadding: const EdgeInsets.symmetric(vertical: 8),
                  titleTextStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(fontWeight: FontWeight.bold),
                  weekendStyle: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _selectedRange != null
                      ? () {
                    widget.onConfirm(_selectedRange!);
                    Navigator.pop(context);
                  }
                      : null,
                  child: const Text('Выбрать диапазон'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}