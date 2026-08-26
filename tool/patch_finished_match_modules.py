from pathlib import Path

path = Path('lib/features/matches/presentation/match_details_page.dart')
text = path.read_text()


def replace_once(old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'Expected exactly one match, found {count}: {old[:120]!r}')
    text = text.replace(old, new, 1)

replace_once(
    "import 'package:as_grinta/core/widgets/match_scorers_card.dart';\n",
    "",
)
replace_once(
    "import 'package:as_grinta/features/match_live/presentation/widgets/match_faits_du_match_card.dart';\n",
    "import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';\n"
    "import 'package:as_grinta/features/match_live/presentation/widgets/match_faits_du_match_card.dart';\n",
)
replace_once(
    "import 'package:as_grinta/features/matches/data/match_details_repository.dart';\n"
    "import 'package:as_grinta/features/matches/data/match_finalization_repository.dart';\n",
    "import 'package:as_grinta/features/matches/data/completed_match_effectif_repository.dart';\n"
    "import 'package:as_grinta/features/matches/data/match_details_repository.dart';\n",
)
replace_once(
    "import 'package:as_grinta/features/matches/presentation/widgets/completed_match_composition_card.dart';\n",
    "import 'package:as_grinta/features/matches/presentation/widgets/completed_match_composition_card.dart';\n"
    "import 'package:as_grinta/features/matches/presentation/widgets/completed_match_effectif_card.dart';\n",
)
replace_once(
    "import 'package:as_grinta/features/sports_management/presentation/sport_motm_vote_page.dart';\n",
    "",
)

replace_once(
    "          ref\n"
    "            ..invalidate(matchDetailsProvider(matchId))\n"
    "            ..invalidate(matchFinalizationContextProvider(matchId))\n"
    "            ..invalidate(sportMotmVoteProvider(matchId));\n",
    "          ref\n"
    "            ..invalidate(matchDetailsProvider(matchId))\n"
    "            ..invalidate(completedMatchEffectifProvider(matchId))\n"
    "            ..invalidate(publishedMatchCompositionProvider(matchId))\n"
    "            ..invalidate(matchLiveTimelineProvider(matchId))\n"
    "            ..invalidate(sportMotmVoteProvider(matchId));\n",
)

old_block = """            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                MatchDetailHeaderCard(
                  homeName: details.location == 'domicile'
                      ? 'AS Grinta'
                      : details.opponentName,
                  awayName: details.location == 'domicile'
                      ? details.opponentName
                      : 'AS Grinta',
                  grintaIsHome: details.location == 'domicile',
                  homeScore: details.location == 'domicile'
                      ? details.scoreGrinta ?? 0
                      : details.scoreOpponent ?? 0,
                  awayScore: details.location == 'domicile'
                      ? details.scoreOpponent ?? 0
                      : details.scoreGrinta ?? 0,
                  dateLabel: AppFormats.dateTime(details.kickoffAt),
                  matchTypeLabel: details.matchTypeLabel,
                  address: details.address,
                ),
                const SizedBox(height: 16),
                MatchScorersCard(
                  teamGoals: details.scoreGrinta ?? 0,
                  scorers: [
                    for (final stat in details.playerStats)
                      if (stat.goals > 0)
                        MatchScorerEntry(name: stat.name, goals: stat.goals),
                  ],
                ),
                if (sportsEnabled) ...[
                  const SizedBox(height: 16),
                  MatchMotmVoteCard(matchId: matchId),
                ],
                const SizedBox(height: 16),
                _CompletedCompositionCard(
                  details: details,
                  matchId: matchId,
                  sportsEnabled: sportsEnabled,
                ),
                if (sportsEnabled) ...[
                  const SizedBox(height: 16),
                  MatchFaitsDuMatchCard(matchId: matchId),
                ],
                if (details.predictions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _PredictionsTable(
                    predictions: details.predictions,
                    actualGrinta: details.scoreGrinta ?? 0,
                    actualOpponent: details.scoreOpponent ?? 0,
                    isHome: details.location == 'domicile',
                    currentProfileId: currentProfileId,
                  ),
                ],
                if (isAdmin) ...[
                  const SizedBox(height: 16),
                  _PostgameAdminActions(
                    details: details,
                    matchId: matchId,
                    sportsEnabled: sportsEnabled,
                  ),
                ],
              ],
            );
"""
new_block = """            final vote = sportsEnabled
                ? ref.watch(sportMotmVoteProvider(matchId)).valueOrNull
                : null;
            final fallbackMotmNames = details.startingLineup
                .where((player) => player.isManOfTheMatch)
                .map((player) => player.name)
                .toList(growable: false);
            final motmNames = vote != null &&
                    vote.isClosed &&
                    vote.winners.isNotEmpty
                ? vote.winners
                    .map((winner) => winner.displayName)
                    .toList(growable: false)
                : fallbackMotmNames;
            final motmActionLabel = vote != null &&
                    vote.isOpen &&
                    vote.isEligibleVoter
                ? (vote.hasVoted
                    ? 'Vote HDM enregistré'
                    : 'Voter pour l’Homme du match')
                : null;
            final scorerLabels = [
              for (final stat in details.playerStats)
                if (stat.goals > 0)
                  stat.goals > 1 ? '${stat.name} ×${stat.goals}' : stat.name,
            ];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                MatchDetailHeaderCard(
                  homeName: details.location == 'domicile'
                      ? 'AS Grinta'
                      : details.opponentName,
                  awayName: details.location == 'domicile'
                      ? details.opponentName
                      : 'AS Grinta',
                  grintaIsHome: details.location == 'domicile',
                  homeScore: details.location == 'domicile'
                      ? details.scoreGrinta ?? 0
                      : details.scoreOpponent ?? 0,
                  awayScore: details.location == 'domicile'
                      ? details.scoreOpponent ?? 0
                      : details.scoreGrinta ?? 0,
                  dateLabel: AppFormats.date(details.kickoffAt),
                  kickoffTimeLabel: AppFormats.time(details.kickoffAt),
                  matchTypeLabel: details.matchTypeLabel,
                  address: details.address,
                  manOfMatchNames: motmNames,
                  motmActionLabel: motmActionLabel,
                  onMotmTap: motmActionLabel == null
                      ? null
                      : () => context.push('/matches/$matchId/vote'),
                  scorerLabels: scorerLabels,
                  teamScoredZero: details.scoreGrinta == 0,
                ),
                _CompletedEffectifSection(
                  matchId: matchId,
                  sportsEnabled: sportsEnabled,
                ),
                _CompletedCompositionCard(
                  details: details,
                  matchId: matchId,
                  sportsEnabled: sportsEnabled,
                ),
                _CompletedFactsSection(
                  matchId: matchId,
                  sportsEnabled: sportsEnabled,
                ),
                if (details.predictions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _PredictionsTable(
                    predictions: details.predictions,
                    actualGrinta: details.scoreGrinta ?? 0,
                    actualOpponent: details.scoreOpponent ?? 0,
                    isHome: details.location == 'domicile',
                    currentProfileId: currentProfileId,
                  ),
                ],
                if (isAdmin) ...[
                  const SizedBox(height: 16),
                  _PostgameAdminActions(
                    details: details,
                    matchId: matchId,
                    sportsEnabled: sportsEnabled,
                  ),
                ],
              ],
            );
"""
replace_once(old_block, new_block)

marker = "class _CompletedCompositionCard extends ConsumerWidget {\n"
sections = """class _CompletedEffectifSection extends ConsumerWidget {
  const _CompletedEffectifSection({
    required this.matchId,
    required this.sportsEnabled,
  });

  final String matchId;
  final bool sportsEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!sportsEnabled) return const SizedBox.shrink();
    final effectif = ref.watch(completedMatchEffectifProvider(matchId)).valueOrNull;
    if (effectif == null || effectif.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: CompletedMatchEffectifCard(effectif: effectif),
    );
  }
}

class _CompletedFactsSection extends ConsumerWidget {
  const _CompletedFactsSection({
    required this.matchId,
    required this.sportsEnabled,
  });

  final String matchId;
  final bool sportsEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!sportsEnabled) return const SizedBox.shrink();
    final timeline = ref.watch(matchLiveTimelineProvider(matchId)).valueOrNull;
    if (timeline == null || timeline.events.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: MatchFaitsDuMatchCard(matchId: matchId),
    );
  }
}

"""
replace_once(marker, sections + marker)

old_methods = """  List<CompletedPlayerSummary> _fullSquadPlayers(
    MatchFinalizationContext? finalization,
  ) {
    final fallbackPlayers = _playersFromMatchDetails();
    if (finalization == null || finalization.squad.isEmpty) {
      return fallbackPlayers;
    }

    final goalsByPlayerId = <String, int>{};
    for (final scorerId in finalization.scorerGoalLines) {
      goalsByPlayerId.update(
        scorerId,
        (goals) => goals + 1,
        ifAbsent: () => 1,
      );
    }

    final selectedPlayerIds = finalization.presentPlayerIds;
    final players = [
      for (final player in finalization.squad)
        if (selectedPlayerIds.contains(player.id) ||
            goalsByPlayerId.containsKey(player.id))
          CompletedPlayerSummary(
            name: player.name,
            goals: goalsByPlayerId[player.id] ?? 0,
          ),
    ];

    for (final fallback in fallbackPlayers) {
      final index = players.indexWhere(
        (player) => player.name.toLowerCase() == fallback.name.toLowerCase(),
      );
      if (index == -1) {
        players.add(fallback);
      } else if (fallback.goals > players[index].goals) {
        players[index] = fallback;
      }
    }

    players.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return players;
  }

"""
replace_once(old_methods, "")

old_build = """  @override
  Widget build(BuildContext context, WidgetRef ref) {
    MatchComposition? composition;
    if (sportsEnabled) {
      // Priorité au rendu MPG dès qu'une composition publiée existe.
      composition =
          ref.watch(publishedMatchCompositionProvider(matchId)).valueOrNull;
    }

    final finalization = sportsEnabled
        ? null
        : ref.watch(matchFinalizationContextProvider(matchId)).valueOrNull;
    final fallbackPlayers = sportsEnabled
        ? _playersFromMatchDetails()
        : _fullSquadPlayers(finalization);

    return CompletedCompositionCard(
      composition: composition,
      fallbackPlayers: fallbackPlayers,
    );
  }
}
"""
new_build = """  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!sportsEnabled) return const SizedBox.shrink();
    final composition =
        ref.watch(publishedMatchCompositionProvider(matchId)).valueOrNull;
    if (composition == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: CompletedCompositionCard(
        composition: composition,
        fallbackPlayers: _playersFromMatchDetails(),
      ),
    );
  }
}
"""
replace_once(old_build, new_build)

replace_once(
    "            Text('Pronostics', style: Theme.of(context).textTheme.titleLarge),\n",
    "            Text('Prono', style: Theme.of(context).textTheme.titleLarge),\n",
)

path.write_text(text)

# Temporary patch machinery must never survive on the feature branch.
Path('tool/patch_finished_match_modules.py').unlink(missing_ok=True)
Path('.github/workflows/temporary_patch_finished_match_modules.yml').unlink(
    missing_ok=True,
)
