import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/core/widgets/match_detail_header_card.dart';
import 'package:as_grinta/features/matches/data/calendar_history_repository.dart';
import 'package:as_grinta/features/matches/data/historical_match_detail_repository.dart';
import 'package:as_grinta/features/matches/presentation/widgets/completed_match_composition_card.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fiche en lecture seule d'un match de l'historique importé : même gabarit
/// que [MatchDetailsPage] pour un match terminé (en-tête, composition,
/// homme du match), rempli avec ce que l'archive du club sait réellement
/// dire. Contrairement à [MatchDetailsPage], il n'y a ici ni pronostics, ni
/// vote, ni action d'administration : tout est figé, importé depuis les
/// archives du club — les sections sans donnée disponible sont simplement
/// masquées plutôt que de simuler une fonctionnalité qui n'existe pas pour
/// un match archivé.
///
/// [initialMatch] évite un aller-retour réseau quand on arrive depuis une
/// carte du calendrier qui l'a déjà chargé ; sans lui (arrivée directe sur
/// l'URL, ex. rechargement de page), l'en-tête est retrouvé via [matchId]
/// dans la liste complète de l'historique.
class HistoricalMatchDetailPage extends ConsumerWidget {
  const HistoricalMatchDetailPage({
    required this.matchId,
    this.initialMatch,
    super.key,
  });

  final String matchId;
  final HistoricalMatchResult? initialMatch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(historicalMatchDetailProvider(matchId));

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Match archivé')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(historicalMatchDetailProvider(matchId));
          await ref.read(historicalMatchDetailProvider(matchId).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _HistoricalMatchHeaderSection(
              matchId: matchId,
              initialMatch: initialMatch,
            ),
            const SizedBox(height: 16),
            detailAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: GrintaProgressIndicator()),
              ),
              error: (error, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(humanizeError(error)),
                ),
              ),
              data: (detail) {
                if (detail == null || detail.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        "Aucun détail n'a été retrouvé pour ce match dans "
                        'les archives du club.',
                      ),
                    ),
                  );
                }
                return _HistoricalMatchDetailBody(
                  matchId: matchId,
                  detail: detail,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoricalMatchHeaderSection extends ConsumerWidget {
  const _HistoricalMatchHeaderSection({
    required this.matchId,
    required this.initialMatch,
  });

  final String matchId;
  final HistoricalMatchResult? initialMatch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = initialMatch;
    if (match != null) return _historicalHeader(match);

    final allAsync = ref.watch(allHistoricalMatchesProvider);
    return allAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: GrintaProgressIndicator()),
      ),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(humanizeError(error)),
        ),
      ),
      data: (all) {
        final found = all.where((m) => m.id == matchId).firstOrNull;
        if (found == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Match introuvable dans les archives.'),
            ),
          );
        }
        return _historicalHeader(found);
      },
    );
  }

  Widget _historicalHeader(HistoricalMatchResult match) {
    return MatchDetailHeaderCard(
      homeName: match.isHome ? 'AS Grinta' : match.opponentName,
      awayName: match.isHome ? match.opponentName : 'AS Grinta',
      grintaIsHome: match.isHome,
      homeScore: match.isHome ? match.grintaScore : match.opponentScore,
      awayScore: match.isHome ? match.opponentScore : match.grintaScore,
      dateLabel: AppFormats.date(match.date),
    );
  }
}

class _HistoricalMatchDetailBody extends StatelessWidget {
  const _HistoricalMatchDetailBody({
    required this.matchId,
    required this.detail,
  });

  final String matchId;
  final HistoricalMatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final composition = _compositionFromHistorical(matchId, detail);
    final fallbackPlayers = _fallbackPlayersFromHistorical(detail);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CompletedCompositionCard(
          composition: composition,
          fallbackPlayers: fallbackPlayers,
        ),
        if (detail.motmNames.isNotEmpty) ...[
          const SizedBox(height: 16),
          _HistoricalMotmCard(names: detail.motmNames),
        ],
      ],
    );
  }
}

/// Reconstruit une [MatchComposition] à partir de l'archive historique, afin
/// que le terrain partagé ([CompletedCompositionCard]) affiche une fiche
/// archivée exactement comme une fiche de match courant. `null` quand
/// l'archive ne connaît pas les positions des titulaires : la carte bascule
/// alors elle-même sur son repli « Joueurs (n) ».
MatchComposition? _compositionFromHistorical(
  String matchId,
  HistoricalMatchDetail detail,
) {
  if (!detail.hasComposition) return null;

  int goalsFor(String name) => detail.scorers
      .where((scorer) => scorer.name == name)
      .fold<int>(0, (total, scorer) => total + scorer.goals);

  final entries = <MatchCompositionEntry>[
    for (var i = 0; i < detail.fieldPlayers.length; i += 1)
      _entryFromHistorical(
        detail.fieldPlayers[i],
        zone: MatchCompositionZone.field,
        sortOrder: i,
        goals: goalsFor(detail.fieldPlayers[i].name),
        isMotm: detail.motmNames.contains(detail.fieldPlayers[i].name),
      ),
    for (var i = 0; i < detail.benchPlayers.length; i += 1)
      _entryFromHistorical(
        detail.benchPlayers[i],
        zone: MatchCompositionZone.bench,
        sortOrder: i,
        goals: goalsFor(detail.benchPlayers[i].name),
        isMotm: detail.motmNames.contains(detail.benchPlayers[i].name),
      ),
  ];

  return MatchComposition(
    matchId: matchId,
    formationCode: detail.formation,
    status: 'published',
    version: 1,
    hasUnpublishedChanges: false,
    squadSizeExceptionApproved: false,
    entries: entries,
  );
}

MatchCompositionEntry _entryFromHistorical(
  HistoricalFieldPlayer player, {
  required MatchCompositionZone zone,
  required int sortOrder,
  required int goals,
  required bool isMotm,
}) {
  final isField = zone == MatchCompositionZone.field;
  return MatchCompositionEntry(
    participantId: 'historical-${zone.wireValue}-$sortOrder-${player.name}',
    seasonPlayerId: player.name,
    displayName: player.name,
    isGoalkeeper: player.isGoalkeeper,
    zone: zone,
    sortOrder: sortOrder,
    availabilityStatus: 'available',
    convocationStatus: 'convoked',
    selectionStatus: isField ? 'starter' : 'substitute',
    x: isField ? player.xPct / 100 : null,
    y: isField ? player.yPct / 100 : null,
    photoUrl: player.photoUrl,
    goals: goals,
    isMotm: isMotm,
  );
}

/// Repli « Joueurs (n) » quand l'archive ne connaît pas les positions :
/// fusionne présents et buteurs, comme le fait la fiche d'un match courant
/// pour un match sans données Live détaillées.
List<CompletedPlayerSummary> _fallbackPlayersFromHistorical(
  HistoricalMatchDetail detail,
) {
  final playersByName = <String, CompletedPlayerSummary>{};

  void addPlayer(String rawName, int goals) {
    final name = rawName.trim();
    if (name.isEmpty) return;
    final key = name.toLowerCase();
    final existing = playersByName[key];
    if (existing == null || goals > existing.goals) {
      playersByName[key] = CompletedPlayerSummary(name: name, goals: goals);
    }
  }

  for (final name in detail.presentNames) {
    addPlayer(name, 0);
  }
  for (final scorer in detail.scorers) {
    addPlayer(scorer.name, scorer.goals);
  }

  return playersByName.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// Même habillage que [MatchMotmVoteCard] une fois le vote clos (icône,
/// titre, sous-titre), mais statique : une archive n'a pas de scrutin à
/// rouvrir, donc pas de flèche ni d'action au tap.
class _HistoricalMotmCard extends StatelessWidget {
  const _HistoricalMotmCard({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.emoji_events_outlined),
        title: Text(
          names.length > 1 ? 'Co-Hommes du match' : 'Homme du match',
        ),
        subtitle: Text(names.join(' · ')),
      ),
    );
  }
}
