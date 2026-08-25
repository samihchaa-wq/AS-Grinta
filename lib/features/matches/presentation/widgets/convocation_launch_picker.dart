import 'package:as_grinta/features/matches/domain/convocation_launch.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_option_button.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_wheel_picker.dart';
import 'package:flutter/material.dart';

class ConvocationLaunchPicker extends StatelessWidget {
  const ConvocationLaunchPicker({
    super.key,
    required this.kickoffAt,
    required this.mode,
    required this.customAt,
    required this.onModeChanged,
    required this.onCustomAtChanged,
    this.enabled = true,
  });

  final DateTime kickoffAt;
  final ConvocationLaunchMode mode;
  final DateTime? customAt;
  final ValueChanged<ConvocationLaunchMode> onModeChanged;
  final ValueChanged<DateTime> onCustomAtChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final automaticAt = defaultConvocationLaunchAt(kickoffAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Lancement des convocations',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: MatchOptionButton(
                label: 'J-6',
                selected: mode == ConvocationLaunchMode.automatic,
                onPressed: enabled
                    ? () => onModeChanged(ConvocationLaunchMode.automatic)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MatchOptionButton(
                label: 'Maintenant',
                selected: mode == ConvocationLaunchMode.now,
                onPressed: enabled
                    ? () => onModeChanged(ConvocationLaunchMode.now)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MatchOptionButton(
                label: 'Choisir',
                selected: mode == ConvocationLaunchMode.custom,
                onPressed: enabled ? () => _pickCustom(context) : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
            switch (mode) {
              ConvocationLaunchMode.automatic =>
                'J-6 à 12h · ${_formatDateTime(automaticAt)}',
              ConvocationLaunchMode.now => 'Dès l’enregistrement du match',
              ConvocationLaunchMode.custom => customAt == null
                  ? 'Choisis une date et une heure'
                  : _formatDateTime(customAt!),
            },
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final minimum = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final maximumRaw = kickoffAt.subtract(const Duration(minutes: 1));
    final maximum = DateTime(
      maximumRaw.year,
      maximumRaw.month,
      maximumRaw.day,
      maximumRaw.hour,
      maximumRaw.minute,
    );
    if (maximum.isBefore(minimum)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le match est trop proche pour programmer un lancement.',
          ),
        ),
      );
      return;
    }

    final suggested = customAt ??
        suggestedCustomConvocationLaunchAt(kickoffAt: kickoffAt, now: minimum);
    final picked = await showMatchDateTimeWheelPicker(
      context: context,
      title: 'Lancement des convocations',
      initialValue: suggested,
      minimumDate: minimum,
      maximumDate: maximum,
    );
    if (picked == null || !context.mounted) return;

    final error = validateConvocationLaunch(
      mode: ConvocationLaunchMode.custom,
      kickoffAt: kickoffAt,
      customAt: picked,
    );
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    onCustomAtChanged(picked);
    onModeChanged(ConvocationLaunchMode.custom);
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
