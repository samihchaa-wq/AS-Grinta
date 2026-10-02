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

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.sports_soccer_outlined),
              title: Text(
                'Module de gestion sportive',
                style: TextStyle(fontWeight: FontWeight.w400),
              ),
              subtitle: Text('Activé en permanence'),
            ),
            Text(
              'Ce module gère la vie sportive du club : disponibilités des '
              'joueurs, convocations, composition d’équipe, feuille de match et '
              'vote de l’Homme du match, avec les notifications associées.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Calendrier automatique : disponibilités, effectif, composition '
              'et pronostics ouverts à J−6 à 12 h (heure de Paris), Live ouvert '
              '15 minutes avant le match, effectif proposé à '
              '${feature.usualSquadSize} (modifiable match par match), vote '
              'Homme du match ouvert après la validation du compte rendu et '
              'fermé 24 h après le coup d’envoi.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
