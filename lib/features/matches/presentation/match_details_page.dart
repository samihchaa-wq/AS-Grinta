import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_faits_du_match_card.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/data/match_finalization_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_motm_vote_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/sport_motm_vote_page.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';

class MatchDetailsPage extends ConsumerWidget {
  const MatchDetailsPage({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(matchDetailsProvider(matchId));
    final isAdmin = ref.watch(isAdminViewProvider);
    final sportsEnabled = ref.watch(sportsManagementEnabledProvider);
    final currentProfileId = ref.watch(
      authControllerProvider.select((state) => state.profile?.id),
    );

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Match')),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(featureFlagsControllerProvider.notifier).refresh();
          ref
            ..invalidate(matchDetailsProvider(matchId))
            ..invalidate(matchFinalizationContextProvider(matchId))
            ..invalidate(sportMotmVoteProvider(matchId));
          await ref.read(matchDetailsProvider(matchId).future);
        },
        child: detailsAsync.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: 220),
              Center(child: GrintaProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(humanizeError(error)),
                ),
              ),
            ],
          ),
          data: (details) {
            if (!details.isValidated) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _UpcomingHeader(details: details),
                  const SizedBox(height: 16),
                  if (sportsEnabled)
                    _UpcomingModules(matchId: matchId, isAdmin: isAdmin)
                  else
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('Gestion sportive indisponible.'),
                      ),
                    ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _MatchHeader(details: details),
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
                  if (sportsEnabled) ...[
                    OutlinedButton.icon(
                      onPressed: () => context.push(
                        '/matches/$matchId/composition?step=composition',
                      ),
                      icon: const Icon(Icons.dashboard_customize_outlined),
                      label: const Text('Gérer la composition'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  FilledButton.icon(
                    onPressed: () => context.push('/matches/$matchId/finalize'),
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text('Modifier les statistiques'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _UpcomingHeader extends StatelessWidget {
  const _UpcomingHeader({required this.details});

  final MatchDetailsData details;

  @override
  Widget build(BuildContext context) {
    final home = details.location == 'domicile';
    final homeName = home ? 'AS Grinta' : details.opponentName;
    final awayName = home ? details.opponentName : 'AS Grinta';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MatchFixture(
              homeName: homeName,
              awayName: awayName,
              grintaIsHome: home,
              nameStyle: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(AppFormats.dateTime(details.kickoffAt)),
          ],
        ),
      ),
    );
  }
}

class _UpcomingModules extends StatelessWidget {
  const _UpcomingModules({required this.matchId, required this.isAdmin});

  final String matchId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final effectif = _MatchModule(
          icon: Icons.groups_2_outlined,
          title: 'Effectif',
          subtitle: isAdmin
              ? 'Sélectionner puis enregistrer l’effectif.'
              : 'Consulter les joueurs convoqués.',
          onTap: () => context.push(
            isAdmin
                ? '/matches/$matchId/composition?step=effectif'
                : '/matches/$matchId/lineup?section=effectif',
          ),
        );
        final composition = _MatchModule(
          icon: Icons.dashboard_customize_outlined,
          title: 'Composition',
          subtitle: isAdmin
              ? 'Créer, enregistrer et publier la composition.'
              : 'Consulter la composition publiée.',
          onTap: () => context.push(
            isAdmin
                ? '/matches/$matchId/composition?step=composition'
                : '/matches/$matchId/lineup?section=composition',
          ),
        );
        if (compact) {
          return Column(
            children: [effectif, const SizedBox(height: 12), composition],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: effectif),
            const SizedBox(width: 12),
            Expanded(child: composition),
          ],
        );
      },
    );
  }
}

class _MatchModule extends StatelessWidget {
  const _MatchModule({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 24, child: Icon(icon)),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerRight,
                child: Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchHeader extends StatelessWidget {
  const _MatchHeader({required this.details});

  final MatchDetailsData details;

  @override
  Widget build(BuildContext context) {
    final home = details.location == 'domicile';
    final grinta = details.scoreGrinta ?? 0;
    final opponent = details.scoreOpponent ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MatchFixture(
              homeName: home ? 'AS Grinta' : details.opponentName,
              awayName: home ? details.opponentName : 'AS Grinta',
              grintaIsHome: home,
              homeScore: home ? grinta : opponent,
              awayScore: home ? opponent : grinta,
              finished: true,
              nameStyle: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(AppFormats.dateTime(details.kickoffAt)),
          ],
        ),
      ),
    );
  }
}

class _CompletedPlayerSummary {
  const _CompletedPlayerSummary({required this.name, required this.goals});

  final String name;
  final int goals;
}

class _CompletedCompositionCard extends ConsumerWidget {
  const _CompletedCompositionCard({
    required this.details,
    required this.matchId,
    required this.sportsEnabled,
  });

  final MatchDetailsData details;
  final String matchId;
  final bool sportsEnabled;

  List<_CompletedPlayerSummary> _playersFromMatchDetails() {
    final playersByName = <String, _CompletedPlayerSummary>{};

    void addPlayer(String rawName, int goals) {
      final name = rawName.trim();
      if (name.isEmpty) return;
      final key = name.toLowerCase();
      final existing = playersByName[key];
      if (existing == null || goals > existing.goals) {
        playersByName[key] = _CompletedPlayerSummary(name: name, goals: goals);
      }
    }

    for (final player in details.playerStats) {
      addPlayer(player.name, player.goals);
    }
    for (final player in details.startingLineup) {
      addPlayer(player.name, player.goals);
    }

    return playersByName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<_CompletedPlayerSummary> _fullSquadPlayers(
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
          _CompletedPlayerSummary(
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sportsEnabled) {
      // Priorité au rendu MPG dès qu'une composition publiée existe.
      final composition =
          ref.watch(publishedMatchCompositionProvider(matchId)).valueOrNull;
      final fieldEntries =
          composition?.entriesFor(MatchCompositionZone.field) ?? const [];
      if (fieldEntries.isNotEmpty) {
        return _MpgCompletedCard(composition: composition!);
      }
    }

    final finalization = sportsEnabled
        ? null
        : ref.watch(matchFinalizationContextProvider(matchId)).valueOrNull;
    final players = sportsEnabled
        ? _playersFromMatchDetails()
        : _fullSquadPlayers(finalization);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              players.isEmpty ? 'Joueurs' : 'Joueurs (${players.length})',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            if (players.isEmpty)
              const Text('Aucun joueur renseigné.')
            else
              _CompletedPlayersList(players: players),
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
                child: CompositionPitch(
                  entries: composition.entriesFor(MatchCompositionZone.field),
                ),
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

class _CompletedPlayersList extends StatelessWidget {
  const _CompletedPlayersList({required this.players});

  final List<_CompletedPlayerSummary> players;

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

class _PredictionsTable extends StatelessWidget {
  const _PredictionsTable({
    required this.predictions,
    required this.actualGrinta,
    required this.actualOpponent,
    required this.isHome,
    required this.currentProfileId,
  });

  final List<MatchPredictionResult> predictions;
  final int actualGrinta;
  final int actualOpponent;
  final bool isHome;
  final String? currentProfileId;

  int _result(int home, int away) => home == away ? 0 : (home > away ? 1 : -1);

  Color? _colorFor(MatchPredictionResult prediction) {
    if (prediction.points <= 0) return null;
    final exact = prediction.scoreGrinta == actualGrinta &&
        prediction.scoreOpponent == actualOpponent;
    if (exact) return const Color(0xFF9B6CFF);
    final correctWinner =
        _result(prediction.scoreGrinta, prediction.scoreOpponent) ==
            _result(actualGrinta, actualOpponent);
    if (!correctWinner) return null;
    return const Color(0xFF39E784);
  }

  Widget _predictionRow(
    BuildContext context,
    MatchPredictionResult prediction,
  ) {
    final resultColor = _colorFor(prediction);
    final isCurrentUser =
        currentProfileId != null && prediction.profileId == currentProfileId;
    final highlightColor = isCurrentUser ? AppTheme.accent : resultColor;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: highlightColor == null
            ? null
            : Border.all(
                color: highlightColor,
                width: isCurrentUser ? 2.2 : 1.7,
              ),
        color: highlightColor?.withValues(alpha: isCurrentUser ? .16 : .08),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: NameWithBadges(
              profileId: prediction.profileId,
              name: prediction.name,
            ),
          ),
          Expanded(
            child: Text(
              isHome
                  ? '${prediction.scoreGrinta}–${prediction.scoreOpponent}'
                  : '${prediction.scoreOpponent}–${prediction.scoreGrinta}',
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 30,
            child: prediction.usedX2
                ? const Align(
                    alignment: Alignment.centerRight,
                    child: _X2Badge(),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              prediction.points.round().toString(),
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pronostics', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final prediction in predictions)
              _predictionRow(context, prediction),
          ],
        ),
      ),
    );
  }
}

/// Pastille « ×2 » indiquant qu'un joueur a utilisé son bonus double sur ce
/// pronostic (ses points sont doublés).
class _X2Badge extends StatelessWidget {
  const _X2Badge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accent.withValues(alpha: .55)),
      ),
      child: const Text(
        '×2',
        style: TextStyle(
          color: AppTheme.accent,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}
