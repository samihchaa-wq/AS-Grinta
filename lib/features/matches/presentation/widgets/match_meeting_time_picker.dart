import 'package:as_grinta/features/matches/domain/match_meeting.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_wheel_picker.dart';
import 'package:flutter/material.dart';

enum _MeetingTimeChoice { automatic, custom }

class MatchMeetingTimePicker extends StatelessWidget {
  const MatchMeetingTimePicker({
    super.key,
    required this.kickoffAt,
    required this.customMeetingAt,
    required this.enabled,
    required this.onChanged,
  });

  final DateTime kickoffAt;
  final DateTime? customMeetingAt;
  final bool enabled;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final choice = customMeetingAt == null
        ? _MeetingTimeChoice.automatic
        : _MeetingTimeChoice.custom;
    final effective = resolvedMatchMeetingAt(
      kickoffAt: kickoffAt,
      customMeetingAt: customMeetingAt,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Heure de rendez-vous',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        SegmentedButton<_MeetingTimeChoice>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment<_MeetingTimeChoice>(
              value: _MeetingTimeChoice.automatic,
              label: Text('-30min'),
            ),
            ButtonSegment<_MeetingTimeChoice>(
              value: _MeetingTimeChoice.custom,
              label: Text('Choisir'),
            ),
          ],
          selected: {choice},
          onSelectionChanged: enabled
              ? (selection) {
                  final selected = selection.first;
                  if (selected == _MeetingTimeChoice.automatic) {
                    onChanged(null);
                  } else {
                    _pickCustomDateTime(context);
                  }
                }
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          customMeetingAt == null
              ? '${_formatTime(effective)} · 30 min avant le coup d’envoi'
              : _formatDateTime(effective),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _pickCustomDateTime(BuildContext context) async {
    final maximum = kickoffAt.subtract(const Duration(minutes: 1));
    final initial = customMeetingAt ??
        kickoffAt.subtract(const Duration(minutes: 30));
    final picked = await showMatchDateTimeWheelPicker(
      context: context,
      title: 'Heure de rendez-vous',
      initialValue: initial.isAfter(maximum) ? maximum : initial,
      maximumDate: maximum,
    );
    if (picked == null || !context.mounted) return;

    final error = validateCustomMeetingAt(
      kickoffAt: kickoffAt,
      customMeetingAt: picked,
    );
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    onChanged(picked);
  }

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  String _formatDateTime(DateTime value) =>
      '${_formatDate(value)} · ${_formatTime(value)}';
}
