import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/unavailability/data/player_unavailability_repository.dart';
import 'package:as_grinta/features/unavailability/domain/player_unavailability.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _reasonMaxLength = 200;

/// Ouvre la saisie d'une indisponibilité et renvoie `true` si elle a été
/// enregistrée.
Future<bool?> showUnavailabilityFormSheet(
  BuildContext context, {
  PlayerUnavailability? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => UnavailabilityFormSheet(existing: existing),
  );
}

class UnavailabilityFormSheet extends ConsumerStatefulWidget {
  const UnavailabilityFormSheet({super.key, this.existing});

  final PlayerUnavailability? existing;

  @override
  ConsumerState<UnavailabilityFormSheet> createState() =>
      _UnavailabilityFormSheetState();
}

class _UnavailabilityFormSheetState
    extends ConsumerState<UnavailabilityFormSheet> {
  late final TextEditingController _reason =
      TextEditingController(text: widget.existing?.reason ?? '');
  late DateTime _startsOn = widget.existing?.startsOn ?? _today;
  late DateTime _endsOn = widget.existing?.endsOn ?? _today;
  bool _saving = false;
  String? _error;

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startsOn : _endsOn;
    final first = isStart ? _today : _startsOn;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: _today.add(const Duration(days: 366)),
      helpText: isStart ? 'Premier jour d’absence' : 'Dernier jour d’absence',
      cancelText: 'Annuler',
      confirmText: 'Choisir',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startsOn = picked;
        if (_endsOn.isBefore(_startsOn)) _endsOn = _startsOn;
      } else {
        _endsOn = picked;
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Indique la raison de ton absence.');
      return;
    }
    if (_endsOn.isBefore(_startsOn)) {
      setState(() => _error = 'La fin ne peut pas précéder le début.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final navigator = Navigator.of(context);
    try {
      await ref.read(playerUnavailabilityRepositoryProvider).save(
            id: widget.existing?.id,
            startsOn: _startsOn,
            endsOn: _endsOn,
            reason: reason,
          );
      navigator.pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = humanizeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEditing
                  ? 'Modifier mon indisponibilité'
                  : 'Déclarer une indisponibilité',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: AppSpacing.microGap),
            Text(
              'Pendant cette période tu ne fais plus partie de l’effectif '
              'convocable et tu ne reçois plus les notifications des matchs '
              'concernés.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            TextField(
              controller: _reason,
              enabled: !_saving,
              maxLength: _reasonMaxLength,
              maxLines: 2,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [
                LengthLimitingTextInputFormatter(_reasonMaxLength),
              ],
              decoration: const InputDecoration(
                labelText: 'Raison',
                hintText: 'Vacances, blessure, déplacement…',
              ),
            ),
            const SizedBox(height: AppSpacing.contentGap),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Du',
                    value: _startsOn,
                    onTap: _saving ? null : () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: AppSpacing.contentGap),
                Expanded(
                  child: _DateField(
                    label: 'Au',
                    value: _endsOn,
                    onTap: _saving ? null : () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            if (_error case final message?) ...[
              const SizedBox(height: AppSpacing.contentGap),
              Text(
                message,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.sectionGap),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Fermer'),
                ),
                const SizedBox(width: AppSpacing.microGap),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(formatUnavailabilityDay(value)),
      ),
    );
  }
}
