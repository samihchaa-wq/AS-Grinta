import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<DateTime?> showMatchDateWheelPicker({
  required BuildContext context,
  required DateTime initialValue,
  required DateTime minimumDate,
  required DateTime maximumDate,
  String title = 'Date',
}) {
  final initial = _clampDateTime(initialValue, minimumDate, maximumDate);
  return showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _DateTimeWheelSheet(
      title: title,
      mode: CupertinoDatePickerMode.date,
      initialValue: initial,
      minimumDate: minimumDate,
      maximumDate: maximumDate,
      use24hFormat: true,
    ),
  );
}

Future<TimeOfDay?> showMatchTimeWheelPicker({
  required BuildContext context,
  required DateTime initialValue,
  String title = 'Heure',
}) async {
  final picked = await showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _DateTimeWheelSheet(
      title: title,
      mode: CupertinoDatePickerMode.time,
      initialValue: initialValue,
      use24hFormat: true,
    ),
  );
  return picked == null ? null : TimeOfDay.fromDateTime(picked);
}

Future<DateTime?> showMatchDateTimeWheelPicker({
  required BuildContext context,
  required DateTime initialValue,
  DateTime? minimumDate,
  DateTime? maximumDate,
  required String title,
}) {
  var initial = initialValue;
  if (minimumDate != null && initial.isBefore(minimumDate)) {
    initial = minimumDate;
  }
  if (maximumDate != null && initial.isAfter(maximumDate)) {
    initial = maximumDate;
  }

  return showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _DateTimeWheelSheet(
      title: title,
      mode: CupertinoDatePickerMode.dateAndTime,
      initialValue: initial,
      minimumDate: minimumDate,
      maximumDate: maximumDate,
      use24hFormat: true,
    ),
  );
}

Future<int?> showMatchNumberWheelPicker({
  required BuildContext context,
  required int initialValue,
  required int minimumValue,
  required int maximumValue,
  required String title,
}) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _NumberWheelSheet(
      title: title,
      initialValue: initialValue,
      minimumValue: minimumValue,
      maximumValue: maximumValue,
    ),
  );
}

DateTime _clampDateTime(
  DateTime value,
  DateTime minimumDate,
  DateTime maximumDate,
) {
  if (value.isBefore(minimumDate)) return minimumDate;
  if (value.isAfter(maximumDate)) return maximumDate;
  return value;
}

class _DateTimeWheelSheet extends StatefulWidget {
  const _DateTimeWheelSheet({
    required this.title,
    required this.mode,
    required this.initialValue,
    this.minimumDate,
    this.maximumDate,
    required this.use24hFormat,
  });

  final String title;
  final CupertinoDatePickerMode mode;
  final DateTime initialValue;
  final DateTime? minimumDate;
  final DateTime? maximumDate;
  final bool use24hFormat;

  @override
  State<_DateTimeWheelSheet> createState() => _DateTimeWheelSheetState();
}

class _DateTimeWheelSheetState extends State<_DateTimeWheelSheet> {
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('Valider'),
                ),
              ],
            ),
            SizedBox(
              height: 220,
              child: CupertinoDatePicker(
                key: const Key('match-wheel-date-time-picker'),
                mode: widget.mode,
                initialDateTime: widget.initialValue,
                minimumDate: widget.minimumDate,
                maximumDate: widget.maximumDate,
                use24hFormat: widget.use24hFormat,
                minuteInterval: 1,
                onDateTimeChanged: (value) => _selected = value,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberWheelSheet extends StatefulWidget {
  const _NumberWheelSheet({
    required this.title,
    required this.initialValue,
    required this.minimumValue,
    required this.maximumValue,
  });

  final String title;
  final int initialValue;
  final int minimumValue;
  final int maximumValue;

  @override
  State<_NumberWheelSheet> createState() => _NumberWheelSheetState();
}

class _NumberWheelSheetState extends State<_NumberWheelSheet> {
  late int _selected;
  late FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue
        .clamp(widget.minimumValue, widget.maximumValue)
        .toInt();
    _controller = FixedExtentScrollController(
      initialItem: _selected - widget.minimumValue,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('Valider'),
                ),
              ],
            ),
            SizedBox(
              height: 200,
              child: CupertinoPicker(
                key: const Key('match-wheel-number-picker'),
                scrollController: _controller,
                itemExtent: 42,
                useMagnifier: true,
                magnification: 1.08,
                onSelectedItemChanged: (index) {
                  _selected = widget.minimumValue + index;
                },
                children: [
                  for (
                    var value = widget.minimumValue;
                    value <= widget.maximumValue;
                    value++
                  )
                    Center(child: Text('$value')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
