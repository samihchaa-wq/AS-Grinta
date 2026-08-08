import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';

/// Un joueur et son nombre de buts, pour l'affichage « Joueurs (n) » de
/// repli quand aucune composition avec positions n'existe.
class CompletedPlayerSummary {
  const CompletedPlayerSummary({required this.name, required this.goals});

  final String name;
  final int goals;
}

const List<(Offset source, Offset target)> _legacyFlat442DisplayMap = [
  (Offset(.50, .95), Offset(.50, .86)),
  (Offset(.15, .75), Offset(.14, .68)),
  (Offset(.38, .80), Offset(.38, .70)),
  (Offset(.62, .80), Offset(.62, .70)),
  (Offset(.85, .75), Offset(.86, .68)),
  (Offset(.15, .50), Offset(.14, .42)),
  (Offset(.38, .55), Offset(.38, .42)),
  (Offset(.62, .55), Offset(.62, .42)),
  (Offset(.85, .50), Offset(.86, .42)),
  (Offset(.35, .25), Offset(.36, .17)),
  (Offset(.65, .25), Offset(.64, .17)),
];

bool _usesLegacyFlat442Layout(List<MatchCompositionEntry> entries) {
  if (entries.length != _legacyFlat442DisplayMap.length) return false;
  final positions = entries
      .where((entry) => entry.x != null && entry.y != null)
      .map((entry) => Offset(entry.x!, entry.y!))
      .toList();
  if (positions.length != _legacyFlat442DisplayMap.length) return false;
  return _legacyFlat442DisplayMap.every(
    (mapping) => positions.any(
      (position) => (position - mapping.source).distance <= .025,
    ),
  );
}

List<MatchCompositionEntry> _displayFieldEntries(
  List<MatchCompositionEntry> entries,
) {
  if (!_usesLegacyFlat442Layout(entries)) return entries;
  return [
    for (final entry in entries)
      entry.moveTo(
        MatchCompositionZone.field,
        x: _legacyFlat442DisplayMap
            .firstWhere(
              (mapping) =>
                  (Offset(entry.x!, entry.y!) - mapping.source).distance <=
                  .025,
            )
            .target
            .dx,
        y: _legacyFlat442DisplayMap
            .firstWhere(
              (mapping) =>
                  (Offset(entry.x!, entry.y!) - mapping.source).distance <=
                  .025,
            )
            .target
            .dy,
        sortOrder: entry.sortOrder,
      ),
  ];
}

/// Rendu unifié de la composition d'un match terminé, que la donnée vienne
/// du système Live ou de l'archive historique importée : même terrain
/// ([CompositionPitch], photos, buts ⚽, couronne 👑) quand une composition
/// avec positions existe, même liste simple « Joueurs (n) » en repli sinon —
/// pour qu'une fiche de match archivé et une fiche de match courant se
/// ressemblent trait pour trait.
class CompletedCompositionCard extends StatelessWidget {
  const CompletedCompositionCard({
    super.key,
    required this.composition,
    required this.fallbackPlayers,
  });

  final MatchComposition? composition;
  final List<CompletedPlayerSummary> fallbackPlayers;

  @override
  Widget build(BuildContext context) {
    final fieldEntries =
        composition?.entriesFor(MatchCompositionZone.field) ?? const [];
    if (fieldEntries.isNotEmpty) {
      return _MpgCompletedCard(composition: composition!);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              fallbackPlayers.isEmpty
                  ? 'Joueurs'
                  : 'Joueurs (${fallbackPlayers.length})',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            if (fallbackPlayers.isEmpty)
              const Text('Aucun joueur renseigné.')
            else
              CompletedPlayersList(players: fallbackPlayers),
          ],
        ),
      ),
    );
  }
}

/// Rendu MPG d'une composition publiée (photos, couronne 👑, ballons) pour un
/// match terminé — identique à l'affichage d'avant-match.
class _MpgCompletedCard extends StatelessWidget {
  const _MpgCompletedCard({required this.composition});

  final MatchComposition composition;

  @override
  Widget build(BuildContext context) {
    final bench = composition.entriesFor(MatchCompositionZone.bench);
    final field = _displayFieldEntries(
      composition.entriesFor(MatchCompositionZone.field),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Composition et résumé',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Les buts ⚽ et l’homme du match 👑 sont affichés directement '
              'sur les joueurs.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: CompositionPitch(entries: field),
              ),
            ),
            if (bench.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Remplaçants (${bench.length})',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final entry in bench)
                    CompositionPlayerTile(entry: entry),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CompletedPlayersList extends StatelessWidget {
  const CompletedPlayersList({super.key, required this.players});

  final List<CompletedPlayerSummary> players;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < players.length; index += 1) ...[
          Semantics(
            label: players[index].goals == 0
                ? players[index].name
                : '${players[index].name}, ${players[index].goals} '
                    '${players[index].goals == 1 ? 'but' : 'buts'}',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      players[index].name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (players[index].goals > 0) ...[
                    const SizedBox(width: 12),
                    Text(
                      players[index].goals == 1
                          ? '⚽'
                          : '⚽ ×${players[index].goals}',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (index < players.length - 1) const Divider(height: 1),
        ],
      ],
    );
  }
}
