import 'package:as_grinta/features/matches/domain/match_meeting.dart';
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
    final effective = resolvedMatchMeetingAt(
      kickoffAt: kickoffAt,
      customMeetingAt: customMeetingAt,
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Heure de rendez-vous'),
      subtitle: Text(
        customMeetingAt == null
            ? '30 min avant le coup d’envoi · ${_formatTime(effective)}'
            : 'Personnalisée · ${_formatTime(effective)}',
      ),
      trailing: const Icon(Icons.groups_rounded),
      onTap: enabled ? () => _showPicker(context) : null,
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final choice = await showModalBottomSheet<_MeetingTimeChoice>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Heure de rendez-vous',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  customMeetingAt == null
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: const Text('30 min avant le coup d’envoi'),
                subtitle: Text(
                  _formatTime(kickoffAt.subtract(defaultMatchMeetingOffset)),
                ),
                onTap: () => Navigator.pop(
                  sheetContext,
                  _MeetingTimeChoice.automatic,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  customMeetingAt != null
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: const Text('Choisir une heure'),
                subtitle: Text(
                  customMeetingAt == null
                      ? 'Heure personnalisée'
                      : _formatTime(customMeetingAt!),
                ),
                onTap: () => Navigator.pop(
                  sheetContext,
                  _MeetingTimeChoice.custom,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !context.mounted) return;
    if (choice == _MeetingTimeChoice.automatic) {
      onChanged(null);
      return;
    }

    final initial = resolvedMatchMeetingAt(
      kickoffAt: kickoffAt,
      customMeetingAt: customMeetingAt,
    );
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (pickerContext, child) => MediaQuery(
        data: MediaQuery.of(pickerContext).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !context.mounted) return;

    final candidate = matchMeetingAtOnKickoffDate(
      kickoffAt: kickoffAt,
      hour: time.hour,
      minute: time.minute,
    );
    final error = validateCustomMeetingAt(
      kickoffAt: kickoffAt,
      customMeetingAt: candidate,
    );
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }
    onChanged(candidate);
  }

  String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
