import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MatchDetailsPage extends ConsumerWidget {
  const MatchDetailsPage({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(matchDetailsProvider(matchId));
    final isAdmin = ref.watch(authControllerProvider).profile?.role == AuthRole.admin;

    return Scaffold(
      appBar: AppBar(title: const Text('Détails du match')),
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
          data: (details) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _MatchHeader(details: details),
              if (!details.isValidated) ...[
                const SizedBox(height: 16),
                _UpcomingInformation(details: details),
              ] else ...[
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
              ],
              if (isAdmin && details.status == 'a_venir') ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => context.push('/matches/$matchId/finalize'),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('👑  Saisir les statistiques'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _report(context, ref, details),
                      icon: const Icon(Icons.event_repeat_outlined),
                      label: const Text('👑  Reporter'),
                    ),
                  ],
                ),
              ],
              if (isAdmin && details.isValidated) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.push('/matches/$matchId/finalize'),
                  icon: const Icon(Icons.history_edu_outlined),
                  label: const Text('👑  Modifier les statistiques'),
                ),
              ],
              if (!details.isValidated) ...[
                const SizedBox(height: 22),
                Text(
                  '5 dernières confrontations',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                if (details.headToHead.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Aucune confrontation précédente.'),
                    ),
                  )
                else
                  ...details.headToHead.map(
                    (match) => Card(
                      child: ListTile(
                        title: Text(
                          '${match.scoreGrinta ?? '?'} – ${match.scoreOpponent ?? '?'}',
                        ),
                        subtitle: Text(AppFormats.date(match.date)),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _report(
    BuildContext context,
    WidgetRef ref,
    MatchDetailsData details,
  ) async {
    final date = await showDatePicker(
      context: context,
      initialDate: details.kickoffAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(details.kickoffAt),
    );
    if (time == null || !context.mounted) return;
    await ref.read(matchDetailsRepositoryProvider).reportMatch(
          matchId: details.matchId,
          kickoffAt: DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          ),
        );
    ref.invalidate(matchDetailsProvider(matchId));
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
    final title = details.isValidated
        ? home
            ? 'AS Grinta $grinta – $opponent ${details.opponentName}'
            : '${details.opponentName} $opponent – $grinta AS Grinta'
        : home
            ? 'AS Grinta – ${details.opponentName}'
            : '${details.opponentName} – AS Grinta';

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

class _UpcomingInformation extends StatelessWidget {
  const _UpcomingInformation({required this.details});

  final MatchDetailsData details;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${details.predictionParticipantCount} participant${details.predictionParticipantCount > 1 ? 's' : ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _InfoTile(label: 'Cote 1', value: AppFormats.odds(details.oddsWin))),
                const SizedBox(width: 8),
                Expanded(child: _InfoTile(label: 'Cote N', value: AppFormats.odds(details.oddsDraw))),
                const SizedBox(width: 8),
                Expanded(child: _InfoTile(label: 'Cote 2', value: AppFormats.odds(details.oddsLoss))),
              ],
            ),
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
    final scorers = details.playerStats.where((line) => line.goals > 0).toList();
    final cleanSheets = details.playerStats.where((line) => line.cleanSheet).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Résumé du match', style: Theme.of(context).textTheme.titleLarge),
            if (scorers.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Buteurs', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              ...scorers.map(
                (line) => Text(
                  '${line.name} — ${line.goals} but${line.goals > 1 ? 's' : ''}',
                ),
              ),
            ],
            if (cleanSheets.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Clean sheet', style: Theme.of(context).textTheme.titleMedium),
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

  Color? _colorFor(MatchPredictionResult prediction) {
    if (prediction.points <= 0) return null;
    if (prediction.scoreGrinta == actualGrinta &&
        prediction.scoreOpponent == actualOpponent) {
      return const Color(0xFF39E784);
    }
    final predictedDifference = prediction.scoreGrinta - prediction.scoreOpponent;
    final actualDifference = actualGrinta - actualOpponent;
    if (predictedDifference == actualDifference) {
      return const Color(0xFF1DCBFF);
    }
    if (prediction.scoreGrinta == actualGrinta ||
        prediction.scoreOpponent == actualOpponent) {
      return const Color(0xFFFFBE3D);
    }
    return const Color(0xFF7C3CFF);
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
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: color == null ? null : Border.all(color: color, width: 1.7),
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
                    Expanded(
                      child: Text(
                        isHome
                            ? '${prediction.scoreGrinta}–${prediction.scoreOpponent}'
                            : '${prediction.scoreOpponent}–${prediction.scoreGrinta}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        prediction.points.round().toString(),
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: color,
                          fontWeight: color == null ? FontWeight.normal : FontWeight.w900,
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

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
