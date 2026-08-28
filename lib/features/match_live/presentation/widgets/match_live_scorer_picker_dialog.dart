import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter/material.dart';

/// Valeur renvoyée quand le choix supplémentaire est retenu (« CSC adverse »).
/// Ce n'est jamais un participantId : il ne peut donc pas y avoir de collision.
const String kMatchLiveExtraChoiceId = '__extra__';

/// Valeur renvoyée quand le coach efface l'attribution déjà enregistrée
/// (« Remettre à attribuer »). Distincte de `null`, qui veut dire « feuille
/// fermée, ne touche à rien ».
const String kMatchLiveClearChoiceId = '__clear__';

/// Liste de joueurs à choisir : buteur, ou remplaçant qui entre.
/// Retourne le participantId choisi, [kMatchLiveExtraChoiceId] si le choix
/// supplémentaire est retenu, [kMatchLiveClearChoiceId] si l'attribution
/// existante est effacée, ou `null` si annulé.
Future<String?> pickMatchLiveScorer(
  BuildContext context, {
  required List<MatchCompositionEntry> candidates,
  String title = 'Qui a marqué ?',
  IconData icon = Icons.sports_soccer,
  String? extraChoiceLabel,
  IconData extraChoiceIcon = Icons.help_outline,
  String? clearChoiceLabel,
  IconData clearChoiceIcon = Icons.undo_rounded,
}) {
  final sorted = [...candidates]
    ..sort((a, b) => a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        ));
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // La liste des joueurs remplit l'écran : sans poignée ni bouton d'annulation
    // visibles, il n'y avait plus aucun moyen de refermer la feuille sans
    // désigner quelqu'un.
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Annuler'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (extraChoiceLabel != null)
                ListTile(
                  leading: Icon(extraChoiceIcon),
                  title: Text(extraChoiceLabel),
                  onTap: () =>
                      Navigator.of(context).pop(kMatchLiveExtraChoiceId),
                ),
              if (clearChoiceLabel != null)
                ListTile(
                  leading: Icon(clearChoiceIcon),
                  title: Text(clearChoiceLabel),
                  onTap: () =>
                      Navigator.of(context).pop(kMatchLiveClearChoiceId),
                ),
              if (extraChoiceLabel != null || clearChoiceLabel != null)
                const Divider(height: 1),
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
