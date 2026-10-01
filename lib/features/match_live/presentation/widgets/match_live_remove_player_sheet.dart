import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter/material.dart';

/// Choix du joueur à retirer de la feuille de match, puis confirmation.
///
/// Le joueur retiré n'est plus ni sur le terrain ni sur le banc ; il reste
/// proposé dans « Ajouter un joueur » si l'on change d'avis. Renvoie `null`
/// si le coach annule.
Future<MatchCompositionEntry?> showMatchLiveRemovePlayerPicker(
  BuildContext context, {
  required List<MatchCompositionEntry> candidates,
  String? note,
}) async {
  // Par ordre alphabétique : on retrouve un prénom sans chercher.
  final sorted = [...candidates]..sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
  final chosen = await showModalBottomSheet<MatchCompositionEntry>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Retirer un joueur',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  note,
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
              ),
            Flexible(
              child: sorted.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Aucun joueur à retirer.'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final entry in sorted)
                          ListTile(
                            leading: const Icon(Icons.person_remove_rounded),
                            title: Text(entry.displayName),
                            subtitle: Text(
                              entry.zone == MatchCompositionZone.field
                                  ? 'Terrain'
                                  : 'Banc',
                            ),
                            onTap: () => Navigator.pop(sheetContext, entry),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
  );
  if (chosen == null || !context.mounted) return null;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Retirer ${chosen.displayName} ?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Retirer'),
        ),
      ],
    ),
  );
  return confirmed == true ? chosen : null;
}

/// Composition où [removed] passe hors de la feuille de match.
List<Map<String, dynamic>> lineupWithoutPlayer(
  MatchComposition lineup,
  MatchCompositionEntry removed,
) =>
    [
      for (final entry in lineup.entries)
        (entry.participantId == removed.participantId
                ? entry.moveTo(MatchCompositionZone.notSelected)
                : entry)
            .toRpcJson(),
    ];
