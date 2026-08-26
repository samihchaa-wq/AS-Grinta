import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Compact modal wheel pickers used by the match/event forms.
///
/// Cupertino pickers are intentionally used on every platform so the gesture
/// stays identical in the PWA and on iPhone: tap once, then scroll the wheels.
class MatchWheelPicker {
  const MatchWheelPicker._();

  static Future<DateTime?> pickDate({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    String title = 'Date',
  }) {
    final initial = _clampDate(initialDate, firstDate, lastDate);
    return _showDateTimeSheet(
      context: context,
      title: title,
      initialDateTime: initial,
      mode: CupertinoDatePickerMode.date,
      minimumDate: firstDate,
      maximumDate: lastDate,
    );
  }

  static Future<DateTime?> pickTime({
    required BuildContext context,
    required DateTime initialDateTime,
    String title = 'Heure',
  }) {
    return _showDateTimeSheet(
      context: context,
      title: title,
      initialDateTime: initialDateTime,
      mode: CupertinoDatePickerMode.time,
    );
  }

  static Future<DateTime?> pickDateTime({
    required BuildContext context,
    required DateTime initialDateTime,
    required DateTime minimumDate,
    required DateTime maximumDate,
    String title = 'Date et heure',
  }) {
    final initial = _clampDateTime(
      initialDateTime,
      minimumDate,
      maximumDate,
    );
    return _showDateTimeSheet(
      context: context,
      title: title,
      initialDateTime: initial,
      mode: CupertinoDatePickerMode.dateAndTime,
      minimumDate: minimumDate,
      maximumDate: maximumDate,
    );
  }

  static Future<int?> pickInt({
    required BuildContext context,
    required int initialValue,
    required int minValue,
    required int maxValue,
    required String title,
    String Function(int value)? labelBuilder,
  }) async {
    assert(minValue <= maxValue);
    final initial = initialValue < minValue
        ? minValue
        : initialValue > maxValue
            ? maxValue
            : initialValue;
    var selected = initial;
    final controller = FixedExtentScrollController(
      initialItem: initial - minValue,
    );

    final result = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 330,
          child: Column(
            children: [
              _SheetHeader(
                title: title,
                onCancel: () => Navigator.pop(sheetContext),
                onDone: () => Navigator.pop(sheetContext, selected),
              ),
              const Divider(height: 1),
              Expanded(
                child: CupertinoPicker(
                  scrollController: controller,
                  itemExtent: 46,
                  useMagnifier: true,
                  magnification: 1.08,
                  onSelectedItemChanged: (index) {
                    selected = minValue + index;
                  },
                  children: [
                    for (var value = minValue; value <= maxValue; value++)
                      Center(
                        child: Text(
                          labelBuilder?.call(value) ?? value.toString(),
                          style: Theme.of(sheetContext).textTheme.titleMedium,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    controller.dispose();
    return result;
  }

  static Future<DateTime?> _showDateTimeSheet({
    required BuildContext context,
    required String title,
    required DateTime initialDateTime,
    required CupertinoDatePickerMode mode,
    DateTime? minimumDate,
    DateTime? maximumDate,
  }) async {
    var selected = initialDateTime;
    return showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 370,
          child: Column(
            children: [
              _SheetHeader(
                title: title,
                onCancel: () => Navigator.pop(sheetContext),
                onDone: () => Navigator.pop(sheetContext, selected),
              ),
              const Divider(height: 1),
              Expanded(
                child: CupertinoDatePicker(
                  mode: mode,
                  initialDateTime: initialDateTime,
                  minimumDate: minimumDate,
                  maximumDate: maximumDate,
                  use24hFormat: true,
                  minuteInterval: 1,
                  onDateTimeChanged: (value) => selected = value,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static DateTime _clampDate(
    DateTime value,
    DateTime minimum,
    DateTime maximum,
  ) {
    final date = DateUtils.dateOnly(value);
    final min = DateUtils.dateOnly(minimum);
    final max = DateUtils.dateOnly(maximum);
    if (date.isBefore(min)) return min;
    if (date.isAfter(max)) return max;
    return date;
  }

  static DateTime _clampDateTime(
    DateTime value,
    DateTime minimum,
    DateTime maximum,
  ) {
    if (value.isBefore(minimum)) return minimum;
    if (value.isAfter(maximum)) return maximum;
    return value;
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    required this.onCancel,
    required this.onDone,
  });

  final String title;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          TextButton(onPressed: onCancel, child: const Text('Annuler')),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          FilledButton(onPressed: onDone, child: const Text('Valider')),
        ],
      ),
    );
  }
}
