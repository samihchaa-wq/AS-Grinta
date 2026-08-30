import 'package:as_grinta/features/matches/domain/match_meeting.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_wheel_picker.dart';
import 'package:flutter/material.dart';

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
        Row(
          children: [
            Expanded(
              child: _ChoiceButton(
                label: '-30min',
                selected: customMeetingAt == null,
                enabled: enabled,
                onPressed: () => onChanged(null),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ChoiceButton(
                label: 'Choisir',
                selected: customMeetingAt != null,
                enabled: enabled,
                onPressed: () => _pickCustom(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          customMeetingAt == null
              ? 'Rendez-vous à ${_formatTime(effective)}'
              : _formatDateTime(effective),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _pickCustom(BuildContext context) async {
    final latest = kickoffAt.subtract(const Duration(minutes: 1));
    final earliest = DateTime(
      kickoffAt.year - 1,
      kickoffAt.month,
      kickoffAt.day,
      kickoffAt.hour,
      kickoffAt.minute,
    );
    final initial =
        customMeetingAt ?? kickoffAt.subtract(const Duration(minutes: 30));

    final candidate = await MatchWheelPicker.pickDateTime(
      context: context,
      title: 'Heure de rendez-vous',
      initialDateTime: initial,
      minimumDate: earliest,
      maximumDate: latest,
    );
    if (candidate == null || !context.mounted) return;

    final error = validateCustomMeetingAt(
      kickoffAt: kickoffAt,
      customMeetingAt: candidate,
    );
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    onChanged(candidate);
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

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return FilledButton(
        style: FilledButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.secondary,
        ),
        onPressed: enabled ? onPressed : null,
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      child: Text(label),
    );
  }
}
