import 'package:as_grinta/features/matches/domain/convocation_launch.dart';
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
        const SizedBox(height: 6),
        Text(
          'Choisis quand les joueurs pourront répondre à leur disponibilité.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        RadioListTile<ConvocationLaunchMode>(
          contentPadding: EdgeInsets.zero,
          value: ConvocationLaunchMode.automatic,
          groupValue: mode,
          onChanged: enabled ? _changeMode : null,
          title: const Text('Automatique — J-6 à 12h'),
          subtitle: Text('Prévu le ${_formatDateTime(automaticAt)}'),
        ),
        RadioListTile<ConvocationLaunchMode>(
          contentPadding: EdgeInsets.zero,
          value: ConvocationLaunchMode.custom,
          groupValue: mode,
          onChanged: enabled ? _changeMode : null,
          title: const Text('Choisir une date et une heure'),
          subtitle: Text(
            customAt == null
                ? 'À définir'
                : 'Prévu le ${_formatDateTime(customAt!)}',
          ),
        ),
        if (mode == ConvocationLaunchMode.custom) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled ? () => _pickDate(context) : null,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    customAt == null ? 'Date' : _formatDate(customAt!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled ? () => _pickTime(context) : null,
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text(
                    customAt == null ? 'Heure' : _formatTime(customAt!),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        RadioListTile<ConvocationLaunchMode>(
          contentPadding: EdgeInsets.zero,
          value: ConvocationLaunchMode.now,
          groupValue: mode,
          onChanged: enabled ? _changeMode : null,
          title: const Text('Maintenant'),
          subtitle: const Text('Les disponibilités s’ouvrent dès la création.'),
        ),
      ],
    );
  }

  void _changeMode(ConvocationLaunchMode? value) {
    if (value == null) return;
    if (value == ConvocationLaunchMode.custom && customAt == null) {
      onCustomAtChanged(
        suggestedCustomConvocationLaunchAt(kickoffAt: kickoffAt),
      );
    }
    onModeChanged(value);
  }

  Future<void> _pickDate(BuildContext context) async {
    final initial =
        customAt ?? suggestedCustomConvocationLaunchAt(kickoffAt: kickoffAt);
    final today = DateUtils.dateOnly(DateTime.now());
    final latest = DateUtils.dateOnly(kickoffAt);
    final initialDate = DateUtils.dateOnly(initial).isBefore(today)
        ? today
        : DateUtils.dateOnly(initial).isAfter(latest)
            ? latest
            : DateUtils.dateOnly(initial);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: latest,
    );
    if (picked == null) return;
    onCustomAtChanged(
      DateTime(
        picked.year,
        picked.month,
        picked.day,
        initial.hour,
        initial.minute,
      ),
    );
  }

  Future<void> _pickTime(BuildContext context) async {
    final initial =
        customAt ?? suggestedCustomConvocationLaunchAt(kickoffAt: kickoffAt);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    onCustomAtChanged(
      DateTime(
        initial.year,
        initial.month,
        initial.day,
        picked.hour,
        picked.minute,
      ),
    );
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
