import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';

/// Un joueur et son nombre de buts, pour l'affichage « Joueurs (n) » de
/// repli quand aucune composition avec positions n'existe.
class CompletedPlayerSummary {
  const CompletedPlayerSummary({
    required this.name,
    required this.goals,
    this.photoUrl,
    this.lastInitial,
    this.isMotm = false,
  });

  final String name;
  final int goals;

  /// Homme du match : une couronne 👑 suit son prénom dans la liste.
  final bool isMotm;

  /// Photo du joueur, quand l'archive la connaît. Sans elle, la pastille
  /// retombe sur les initiales, comme sur le terrain d'une composition.
  final String? photoUrl;

  /// Initiale du nom de famille, pour distinguer deux joueurs au même prénom
  /// sur la pastille sans photo.
  final String? lastInitial;
}

const List<({Offset source, Offset target})> _legacyFlat442DisplayMap = [
  (source: Offset(.50, .95), target: Offset(.50, .86)),
  (source: Offset(.15, .75), target: Offset(.14, .68)),
  (source: Offset(.38, .80), target: Offset(.38, .70)),
  (source: Offset(.62, .80), target: Offset(.62, .70)),
  (source: Offset(.85, .75), target: Offset(.86, .68)),
  (source: Offset(.15, .50), target: Offset(.14, .42)),
  (source: Offset(.38, .55), target: Offset(.38, .42)),
  (source: Offset(.62, .55), target: Offset(.62, .42)),
  (source: Offset(.85, .50), target: Offset(.86, .42)),
  (source: Offset(.35, .25), target: Offset(.36, .17)),
  (source: Offset(.65, .25), target: Offset(.64, .17)),
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

Offset _legacyFlat442Position(MatchCompositionEntry entry) {
  final raw = Offset(entry.x!, entry.y!);
  for (final mapping in _legacyFlat442DisplayMap) {
    if ((raw - mapping.source).distance <= .025) return mapping.target;
  }
  return raw;
}

List<MatchCompositionEntry> _displayFieldEntries(
  List<MatchCompositionEntry> entries,
) {
  if (!_usesLegacyFlat442Layout(entries)) return entries;
  return [
    for (final entry in entries)
      entry.moveTo(
        MatchCompositionZone.field,
        x: _legacyFlat442Position(entry).dx,
        y: _legacyFlat442Position(entry).dy,
        sortOrder: entry.sortOrder,
      ),
  ];
}

/// Rendu unifié de la composition d'un match terminé, que la donnée vienne
/// du système Live ou de l'archive historique importée : même terrain
/// ([CompositionPitch], photos, buts ⚽, passes 👟, couronne 👑) quand une
/// composition avec positions existe, même liste simple « Joueurs (n) » en
/// repli sinon — pour qu'une fiche de match archivé et une fiche de match
/// courant se ressemblent trait pour trait.
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
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w400),
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

/// Rendu MPG d'une composition publiée (photos, couronne 👑, ballons et
/// crampons 👟) pour un match terminé — identique à l'affichage d'avant-match.
class _MpgCompletedCard extends StatelessWidget {
  const _MpgCompletedCard({required this.composition});

  final MatchComposition composition;

  @override
  Widget build(BuildContext context) {
    final bench = composition.entriesFor(MatchCompositionZone.bench);
    final field = _displayFieldEntries(
      composition.entriesFor(MatchCompositionZone.field),
    );
    final hasVacantSlots = field.any((entry) => entry.isVacant);
    return Card(
      // Marges latérales réduites : l'espace gagné agrandit le terrain.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasVacantSlots) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'Les emplacements grisés — sont des postes dont la feuille '
                  'de match n’a pas gardé le nom du joueur.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (bench.isEmpty)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: CompositionPitch(entries: field),
                ),
              )
            else
              _PitchWithBench(field: field, bench: bench),
          ],
        ),
      ),
    );
  }
}

/// Remplaçants en colonne à gauche d'un terrain réduit. L'ensemble est
/// dessiné à une taille de référence puis réduit d'un bloc à la largeur
/// disponible : photos du banc et du terrain gardent ainsi la même taille,
/// et les positions sur le terrain ne se chevauchent pas davantage.
class _PitchWithBench extends StatelessWidget {
  const _PitchWithBench({required this.field, required this.bench});

  final List<MatchCompositionEntry> field;
  final List<MatchCompositionEntry> bench;

  static const _pitchWidth = 340.0;
  static const _pitchHeight = _pitchWidth / 0.68;
  static const _benchWidth = 62.0;
  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: _benchWidth + _gap + _pitchWidth,
          height: _pitchHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _benchWidth,
                height: _pitchHeight,
                // Banc très fourni : la colonne rétrécit pour tenir à la
                // hauteur du terrain au lieu de déborder.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < bench.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        CompositionPlayerTile(entry: bench[i]),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: _gap),
              SizedBox(
                width: _pitchWidth,
                child: CompositionPitch(entries: field),
              ),
            ],
          ),
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
            label: [
              players[index].name,
              if (players[index].isMotm) 'Homme du match',
              if (players[index].goals > 0)
                '${players[index].goals} '
                    '${players[index].goals == 1 ? 'but' : 'buts'}',
            ].join(', '),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: PlayerAvatar(
                      photoUrl: players[index].photoUrl,
                      name: players[index].name,
                      lastName: players[index].lastInitial,
                      size: 40,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // La couronne colle au prénom, à gauche du ballon qui
                  // reste aligné à droite.
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            players[index].name,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w400,
                                    ),
                          ),
                        ),
                        if (players[index].isMotm) ...[
                          const SizedBox(width: 6),
                          const ExcludeSemantics(
                            child: Text('👑', style: TextStyle(fontSize: 18)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (players[index].goals > 0) ...[
                    const SizedBox(width: 12),
                    Text(
                      players[index].goals == 1
                          ? '⚽'
                          : '⚽ ×${players[index].goals}',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w400,
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
