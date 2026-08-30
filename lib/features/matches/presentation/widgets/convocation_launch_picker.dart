import 'package:as_grinta/features/matches/domain/convocation_launch.dart';
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
              child: _ChoiceButton(
                label: 'J-6',
                selected: mode == ConvocationLaunchMode.automatic,
                enabled: enabled,
                onPressed: () => onModeChanged(ConvocationLaunchMode.automatic),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ChoiceButton(
                label: 'Maintenant',
                selected: mode == ConvocationLaunchMode.now,
                enabled: enabled,
                onPressed: () => onModeChanged(ConvocationLaunchMode.now),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ChoiceButton(
                label: 'Choisir',
                selected: mode == ConvocationLaunchMode.custom,
                enabled: enabled,
                onPressed: () => _pickCustom(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          switch (mode) {
            ConvocationLaunchMode.automatic =>
              'Ouverture le ${_formatDateTime(automaticAt)}',
            ConvocationLaunchMode.now => 'Ouverture dès l’enregistrement',
            ConvocationLaunchMode.custom => customAt == null
                ? 'Choisis une date et une heure'
                : 'Ouverture le ${_formatDateTime(customAt!)}',
          },
          style: Theme.of(context).textTheme.bodySmall,
        ),
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
    final maximum = kickoffAt.subtract(const Duration(minutes: 1));
    if (maximum.isBefore(minimum)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le match est trop proche. Choisis « Maintenant ».'),
        ),
      );
      return;
    }

    final initial = customAt ??
        suggestedCustomConvocationLaunchAt(
          kickoffAt: kickoffAt,
          now: minimum,
        );
    final picked = await MatchWheelPicker.pickDateTime(
      context: context,
      title: 'Lancement des convocations',
      initialDateTime: initial,
      minimumDate: minimum,
      maximumDate: maximum,
    );
    if (picked == null || !context.mounted) return;

    final error = validateConvocationLaunch(
      mode: ConvocationLaunchMode.custom,
      kickoffAt: kickoffAt,
      customAt: picked,
      now: minimum,
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
      '${_formatDate(value)} à ${_formatTime(value)}';
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
    final style = ButtonStyle(
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      textStyle: WidgetStateProperty.all(
        const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
    if (selected) {
      return FilledButton(
        style: style.copyWith(
          foregroundColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.secondary,
          ),
        ),
        onPressed: enabled ? onPressed : null,
        child: Text(label, maxLines: 1),
      );
    }
    return OutlinedButton(
      style: style,
      onPressed: enabled ? onPressed : null,
      child: Text(label, maxLines: 1),
    );
  }
}
