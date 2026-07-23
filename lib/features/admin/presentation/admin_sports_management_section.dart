import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/feature_flags/domain/feature_flags.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdminSportsManagementSection extends ConsumerWidget {
  const AdminSportsManagementSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flagsAsync = ref.watch(featureFlagsControllerProvider);
    final snapshot =
        flagsAsync.valueOrNull ?? const FeatureFlagsSnapshot.unavailable();
    final feature = snapshot.sportsManagement;
    final busy = flagsAsync.isLoading;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.sports_soccer_outlined),
              title: const Text(
                'Module de gestion sportive',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(feature.enabled ? 'Activé' : 'Désactivé'),
              value: feature.enabled,
              onChanged: snapshot.sourceAvailable && !busy
                  ? (enabled) => _changeValue(context, ref, enabled: enabled)
                  : null,
            ),
            if (busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            if (!snapshot.sourceAvailable && !busy) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.cloud_off_outlined),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Le réglage serveur est indisponible. Par sécurité, '
                          'le module reste considéré comme désactivé.',
                        ),
                      ),
                      IconButton(
                        tooltip: 'Réessayer',
                        onPressed: () => ref
                            .read(featureFlagsControllerProvider.notifier)
                            .refresh(),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Désactivé, ce module ne change rien aux pronostics, aux '
              'statistiques, aux badges ni à la finalisation historique.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Paramètres serveur : ouverture J−${feature.availabilityOpenHoursBefore ~/ 24}, '
              'relances ${_reminderLabel(feature.reminderHoursBefore)}, '
              'limite proposée ${feature.usualSquadSize} et modifiable par '
              'match, vote ${feature.voteDurationHours} h.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (feature.updatedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'Dernière modification : ${_formatDate(feature.updatedAt!)}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _changeValue(
    BuildContext context,
    WidgetRef ref, {
    required bool enabled,
  }) async {
    if (!enabled) {
      final confirmed = await _confirmDisable(context);
      if (!confirmed) return;
    }

    try {
      await ref
          .read(featureFlagsControllerProvider.notifier)
          .setSportsManagementEnabled(
            enabled: enabled,
            justification: null,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Le module de gestion sportive est activé.'
                : 'Le module est désactivé. Les données sont conservées.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
    }
  }

  Future<bool> _confirmDisable(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Désactiver le module ?'),
            content: const Text(
              'Les disponibilités, compositions, notifications et votes '
              'seront masqués et bloqués. Toutes les données historiques '
              'seront conservées.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Désactiver'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

String _reminderLabel(List<int> reminderHoursBefore) {
  return reminderHoursBefore.map((hours) => 'J−${hours ~/ 24}').join(' et ');
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      'à ${two(local.hour)}:${two(local.minute)}';
}
