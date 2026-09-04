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
/// modulaire qu'un match courant terminé. Une section n'apparaît que lorsque
/// la source historique contient réellement les données nécessaires.
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
    final loadedDetail = detailAsync.valueOrNull;

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
              detail: loadedDetail,
            ),
            detailAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: GrintaProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(humanizeError(error)),
                  ),
                ),
              ),
              data: (detail) {
                if (detail == null || detail.isEmpty) {
                  return const SizedBox.shrink();
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
    required this.detail,
  });

  final String matchId;
  final HistoricalMatchResult? initialMatch;
  final HistoricalMatchDetail? detail;

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
    final scorerLabels = [
      for (final scorer in detail?.scorers ?? const <HistoricalScorer>[])
        scorer.goals > 1 ? '${scorer.name} ×${scorer.goals}' : scorer.name,
    ];
    return MatchDetailHeaderCard(
      homeName: match.isHome ? 'AS Grinta' : match.opponentName,
      awayName: match.isHome ? match.opponentName : 'AS Grinta',
      grintaIsHome: match.isHome,
      homeScore: match.isHome ? match.grintaScore : match.opponentScore,
      awayScore: match.isHome ? match.opponentScore : match.grintaScore,
      dateLabel: AppFormats.date(match.date),
      kickoffTimeLabel: match.hasTime ? AppFormats.time(match.date) : null,
      matchTypeLabel: match.matchTypeLabel,
      address: match.address,
      manOfMatchNames: detail?.motmNames ?? const <String>[],
      scorerLabels: scorerLabels,
      teamScoredZero: match.grintaScore == 0,
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
    final fallbackPlayers = historicalFallbackPlayers(detail);

    // Certaines feuilles d'archives ne contiennent aucune composition mais
    // connaissent quand même l'effectif présent. Dans ce cas, on affiche la
    // liste simple « Joueurs (n) » au lieu de masquer toute la section.
    if (composition == null && fallbackPlayers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        CompletedCompositionCard(
          composition: composition,
          fallbackPlayers: fallbackPlayers,
        ),
      ],
    );
  }
}

/// Reconstruit une [MatchComposition] à partir de l'archive historique, afin
/// que le terrain partagé ([CompletedCompositionCard]) affiche une fiche
/// archivée exactement comme une fiche de match courant. `null` quand
/// l'archive ne connaît pas les positions des titulaires.
MatchComposition? _compositionFromHistorical(
  String matchId,
  HistoricalMatchDetail detail,
) {
  if (!detail.hasComposition) return null;

  int goalsFor(String name) => name.isEmpty
      ? 0
      : detail.scorers
          .where((scorer) => scorer.name == name)
          .fold<int>(0, (total, scorer) => total + scorer.goals);

  final entries = <MatchCompositionEntry>[
    for (var i = 0; i < detail.fieldPlayers.length; i += 1)
      _entryFromHistorical(
        detail.fieldPlayers[i],
        zone: MatchCompositionZone.field,
        sortOrder: i,
        goals: goalsFor(detail.fieldPlayers[i].name),
        isMotm: !detail.fieldPlayers[i].isVacant &&
            detail.motmNames.contains(detail.fieldPlayers[i].name),
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
    lastInitial: player.lastInitial,
    isGoalkeeper: player.isGoalkeeper && !player.isVacant,
    zone: zone,
    sortOrder: sortOrder,
    availabilityStatus: 'available',
    convocationStatus: player.isVacant ? 'not_applicable' : 'convoked',
    selectionStatus: isField ? 'starter' : 'substitute',
    x: isField ? player.xPct / 100 : null,
    y: isField ? player.yPct / 100 : null,
    photoUrl: player.photoUrl,
    goals: goals,
    isMotm: isMotm,
    isVacant: player.isVacant,
  );
}

/// Construit l'effectif de secours d'une archive sans composition exploitable.
/// Philippe est le coach et ne doit jamais être présenté comme joueur.
@visibleForTesting
List<CompletedPlayerSummary> historicalFallbackPlayers(
  HistoricalMatchDetail detail,
) {
  final playersByName = <String, CompletedPlayerSummary>{};

  void addPlayer(String rawName, int goals) {
    final name = rawName.trim();
    // Le coach est reconnu sur son appellation actuelle comme sur le nom écrit
    // à l'époque : lui donner un surnom ne doit pas le faire réapparaître dans
    // l'effectif de secours.
    final archiveName = detail.archiveNameByLabel[name] ?? '';
    if (name.isEmpty ||
        _isHistoricalCoachName(name) ||
        _isHistoricalCoachName(archiveName)) {
      return;
    }
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

bool _isHistoricalCoachName(String name) {
  final normalized = name.trim().toLowerCase();
  return normalized == 'philippe' || normalized.startsWith('philippe ');
}
