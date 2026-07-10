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
    final isStaff = role?.isStaff == true;

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
                  child: Text(error.toString()),
                ),
              ),
            ],
          ),
          data: (details) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        details.status == 'a_venir'
                            ? 'AS Grinta – ${details.opponentName}'
                            : 'AS Grinta ${details.scoreGrinta ?? 0} – ${details.scoreOpponent ?? 0} ${details.opponentName}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(details.competition),
                      Text(AppFormats.dateTime(details.kickoffAt)),
                      Text(
                        details.location == 'domicile'
                            ? 'Domicile'
                            : 'Extérieur',
                      ),
                      Text('Statut : ${_statusLabel(details.status)}'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _InfoTile(
                              label: 'Pronostics',
                              value: '${details.predictionParticipantCount}',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _InfoTile(
                              label: 'Cote 1',
                              value: _formatOdds(details.oddsWin),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _InfoTile(
                              label: 'Cote N',
                              value: _formatOdds(details.oddsDraw),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _InfoTile(
                              label: 'Cote 2',
                              value: _formatOdds(details.oddsLoss),
                            ),
                          ),
                        ],
                      ),
                      if (isAdmin && details.status == 'a_venir') ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () =>
                                  context.push('/matches/$matchId/finalize'),
                              icon: const Icon(Icons.fact_check_outlined),
                              label: const Text('Saisir les statistiques'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _report(context, ref, details),
                              icon: const Icon(Icons.event_repeat_outlined),
                              label: const Text('Reporter'),
                            ),
                          ],
                        ),
                      ],
                      if (isStaff &&
                          (details.status == 'termine' ||
                              details.status == 'archive')) ...[
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: () =>
                              context.push('/matches/$matchId/correction'),
                          icon: const Icon(Icons.history_edu_outlined),
                          label: const Text('Corriger le match'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
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
                      subtitle: Text(
                        '${AppFormats.date(match.date)} • '
                        '${match.location == 'domicile' ? 'Domicile' : 'Extérieur'}',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'termine' => 'Terminé',
      'archive' => 'Archivé',
      _ => 'À venir',
    };
  }

  String _formatOdds(double? value) {
    if (value == null) return '—';
    return value.toStringAsFixed(2).replaceAll('.', ',');
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

    final kickoffAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    await ref.read(matchDetailsRepositoryProvider).reportMatch(
          matchId: details.matchId,
          kickoffAt: kickoffAt,
        );
    ref.invalidate(matchDetailsProvider(matchId));
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
