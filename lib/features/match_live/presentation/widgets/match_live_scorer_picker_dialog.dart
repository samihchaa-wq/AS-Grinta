import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter/material.dart';

/// Valeur renvoyée quand le choix supplémentaire est retenu (« CSC adverse »).
/// Ce n'est jamais un participantId : il ne peut donc pas y avoir de collision.
const String kMatchLiveExtraChoiceId = '__extra__';

/// Liste de joueurs à choisir : buteur, ou remplaçant qui entre.
/// Retourne le participantId choisi, [kMatchLiveExtraChoiceId] si le choix
/// supplémentaire est retenu, ou `null` si annulé.
Future<String?> pickMatchLiveScorer(
  BuildContext context, {
  required List<MatchCompositionEntry> candidates,
  String title = 'Qui a marqué ?',
  IconData icon = Icons.sports_soccer,
  String? extraChoiceLabel,
  IconData extraChoiceIcon = Icons.help_outline,
}) {
  final sorted = [...candidates]
    ..sort((a, b) => a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        ));
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (extraChoiceLabel != null) ...[
                ListTile(
                  leading: Icon(extraChoiceIcon),
                  title: Text(extraChoiceLabel),
                  onTap: () =>
                      Navigator.of(context).pop(kMatchLiveExtraChoiceId),
                ),
                const Divider(height: 1),
              ],
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final entry = sorted[index];
                    return ListTile(
                      leading: Icon(icon),
                      title: Text(entry.displayName),
                      onTap: () =>
                          Navigator.of(context).pop(entry.participantId),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
