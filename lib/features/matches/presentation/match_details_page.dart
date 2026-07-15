import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_result_score_chip.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MatchDetailsPage extends ConsumerWidget {
  const MatchDetailsPage({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(matchDetailsProvider(matchId));
    final isAdmin =
        ref.watch(authControllerProvider).profile?.role == AuthRole.admin;

    return Scaffold(
      appBar: GrintaAppBar(title: const SizedBox.shrink()),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(matchDetailsProvider(matchId));
          await ref.read(matchDetailsProvider(matchId).future);
        },
        child: detailsAsync.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: 220),
              Center(child: CircularProgressIndicator()),
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
                  _HeadToHeadCard(details: details),
                  if (isAdmin) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () =>
                          context.push('/matches/$matchId/finalize'),
                      icon: const Text('👑'),
                      label: const Text('Entrer les statistiques'),
                    ),
                  ],
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _MatchHeader(details: details),
                if (details.playerStats.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _MatchSummary(details: details),
                ],
                if (details.predictions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _PredictionsTable(
                    predictions: details.predictions,
                    actualGrinta: details.scoreGrinta ?? 0,
                    actualOpponent: details.scoreOpponent ?? 0,
                    isHome: details.location == 'domicile',
                  ),
                ],
                if (isAdmin) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.push('/matches/$matchId/finalize'),
                    icon: const Icon(Icons.history_edu_outlined),
                    label: const Text('👑 Modifier les statistiques'),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Text(
              'AS Grinta vs ${details.opponentName}',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(AppFormats.dateTime(details.kickoffAt)),
          ],
        ),
      ),
    );
  }
}

class _HeadToHeadCard extends StatelessWidget {
  const _HeadToHeadCard({required this.details});

  final MatchDetailsData details;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Les 5 dernières rencontres',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            if (details.headToHead.isEmpty)
              const Text('Aucune confrontation précédente.')
            else
              ...details.headToHead.map(
                (match) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(AppFormats.date(match.date))),
                      MatchResultScoreChip(
                        scoreGrinta: match.scoreGrinta ?? 0,
                        scoreOpponent: match.scoreOpponent ?? 0,
                      ),
                    ],
                  ),
                ),
              ),
          ],
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
    final title = home
        ? 'AS Grinta $grinta – $opponent ${details.opponentName}'
        : '${details.opponentName} $opponent – $grinta AS Grinta';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(AppFormats.dateTime(details.kickoffAt)),
          ],
        ),
      ),
    );
  }
}

class _MatchSummary extends StatelessWidget {
  const _MatchSummary({required this.details});

  final MatchDetailsData details;

  @override
  Widget build(BuildContext context) {
    final scorers = details.playerStats
        .where((line) => line.goals > 0)
        .toList();
    final cleanSheets = details.playerStats
        .where((line) => line.cleanSheet)
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Résumé du match',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (scorers.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                scorers.length == 1 ? 'Buteur' : 'Buteurs',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              ...scorers.map(
                (line) => Text(
                  line.goals == 1 ? line.name : '${line.name} x${line.goals}',
                ),
              ),
            ],
            if (cleanSheets.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Clean sheet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              ...cleanSheets.map((line) => Text(line.name)),
            ],
          ],
        ),
      ),
    );
  }
}

class _PredictionsTable extends StatelessWidget {
  const _PredictionsTable({
    required this.predictions,
    required this.actualGrinta,
    required this.actualOpponent,
    required this.isHome,
  });

  final List<MatchPredictionResult> predictions;
  final int actualGrinta;
  final int actualOpponent;
  final bool isHome;

  int _result(int home, int away) => home == away ? 0 : (home > away ? 1 : -1);

  Color? _colorFor(MatchPredictionResult prediction) {
    if (prediction.points <= 0) return null;
    final exact =
        prediction.scoreGrinta == actualGrinta &&
        prediction.scoreOpponent == actualOpponent;
    if (exact) return const Color(0xFF9B6CFF);

    final correctWinner =
        _result(prediction.scoreGrinta, prediction.scoreOpponent) ==
        _result(actualGrinta, actualOpponent);
    if (!correctWinner) return null;

    final correctDifference =
        prediction.scoreGrinta - prediction.scoreOpponent ==
        actualGrinta - actualOpponent;
    final oneExactTeam =
        prediction.scoreGrinta == actualGrinta ||
        prediction.scoreOpponent == actualOpponent;
    if (correctDifference || oneExactTeam) return const Color(0xFF1DCBFF);
    return const Color(0xFF39E784);
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
            const Row(
              children: [
                Expanded(flex: 2, child: Text('Joueur')),
                Expanded(child: Text('Prono', textAlign: TextAlign.center)),
                Expanded(child: Text('Points', textAlign: TextAlign.end)),
              ],
            ),
            const Divider(),
            ...predictions.map((prediction) {
              final color = _colorFor(prediction);
              final score = isHome
                  ? '${prediction.scoreGrinta}–${prediction.scoreOpponent}'
                  : '${prediction.scoreOpponent}–${prediction.scoreGrinta}';

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: color == null
                      ? null
                      : Border.all(color: color, width: 1.7),
                  color: color?.withValues(alpha: .08),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        prediction.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(child: Text(score, textAlign: TextAlign.center)),
                    Expanded(
                      child: Text(
                        prediction.points.round().toString(),
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: color,
                          fontWeight: color == null
                              ? FontWeight.normal
                              : FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
