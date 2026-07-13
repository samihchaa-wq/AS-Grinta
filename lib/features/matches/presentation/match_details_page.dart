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
    final role = ref.watch(authControllerProvider).profile?.role;
    final isAdmin = role == AuthRole.admin;

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
              ] else if (details.playerStats.isEmpty &&
                  details.predictions.isEmpty) ...[
                const SizedBox(height: 16),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Pas d’informations sur ce match.'),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                _MatchSummary(details: details),
                const SizedBox(height: 16),
                _PredictionsTable(predictions: details.predictions),
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
    // L'ordre d'écriture indique déjà le lieu : AS Grinta en premier = domicile,
    // en second = extérieur. On n'affiche donc pas « Domicile / Extérieur ».
    final home = details.location == 'domicile';
    final grinta = details.scoreGrinta ?? 0;
    final adverse = details.scoreOpponent ?? 0;
    final String title;
    if (details.isValidated) {
      title = home
          ? 'AS Grinta $grinta – $adverse ${details.opponentName}'
          : '${details.opponentName} $adverse – $grinta AS Grinta';
    } else {
      title = home
          ? 'AS Grinta – ${details.opponentName}'
          : '${details.opponentName} – AS Grinta';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(AppFormats.dateTime(details.kickoffAt)),
            Text(
              details.status == 'archive'
                  ? 'Archivé'
                  : details.isValidated
                      ? 'Terminé'
                      : DateTime.now().isAfter(details.kickoffAt)
                          ? 'En attente du résultat'
                          : 'À venir',
            ),
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
                Expanded(child: _InfoTile(label: 'Cote 1', value: _format(details.oddsWin))),
                const SizedBox(width: 8),
                Expanded(child: _InfoTile(label: 'Cote N', value: _format(details.oddsDraw))),
                const SizedBox(width: 8),
                Expanded(child: _InfoTile(label: 'Cote 2', value: _format(details.oddsLoss))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _format(double? value) =>
      value == null
      ? '—'
      : value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+\$'), '')
          .replaceFirst(RegExp(r'\.\$'), '')
          .replaceAll('.', ',');
}

class _MatchSummary extends StatelessWidget {
  const _MatchSummary({required this.details});

  final MatchDetailsData details;

  @override
  Widget build(BuildContext context) {
    final cleanSheets =
        details.playerStats.where((line) => line.cleanSheet).toList();
    final scorers =
        details.playerStats.where((line) => line.goals > 0).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Résumé du match', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _Section(
              title: 'Buteurs',
              children: scorers
                  .map((line) => Text(
                      '${line.name} — ${line.goals} but${line.goals > 1 ? 's' : ''}'))
                  .toList(),
            ),
            const SizedBox(height: 14),
            _Section(
              title: 'Clean sheet',
              children: cleanSheets.map((line) => Text(line.name)).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        if (children.isEmpty) const Text('Aucun') else ...children,
      ],
    );
  }
}

class _PredictionsTable extends StatelessWidget {
  const _PredictionsTable({required this.predictions});

  final List<MatchPredictionResult> predictions;

  String _points(double value) {
    if ((value - value.round()).abs() < 0.000001) return '${value.round()}';
    return value.toStringAsFixed(1).replaceAll('.', ',');
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
            if (predictions.isEmpty)
              const Text('Aucun pronostic enregistré.')
            else ...[
              const Row(
                children: [
                  Expanded(flex: 2, child: Text('Joueur')),
                  Expanded(child: Text('Prono', textAlign: TextAlign.center)),
                  Expanded(child: Text('Points', textAlign: TextAlign.end)),
                ],
              ),
              const Divider(),
              ...predictions.map(
                (prediction) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text(prediction.name)),
                      Expanded(
                        child: Text(
                          '${prediction.scoreGrinta}–${prediction.scoreOpponent}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _points(prediction.points),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
