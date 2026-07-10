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
          error: (_, __) => ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Les détails du match sont indisponibles.'),
                ),
              ),
            ],
          ),
          data: (details) {
            final isFinished =
                details.status == 'termine' || details.status == 'archive';
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AS Grinta - ${details.opponentName}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(details.kickoffAt.toLocal().toString().split('.').first),
                        Text('Statut : ${details.status}'),
                        if (isAdmin && details.status == 'a_venir') ...[
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => _report(context, ref, details),
                            icon: const Icon(Icons.event_repeat_outlined),
                            label: const Text('Reporter le match'),
                          ),
                        ],
                        if (isStaff && details.status != 'archive') ...[
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () =>
                                context.push('/matches/$matchId/finalize'),
                            icon: const Icon(Icons.fact_check_outlined),
                            label: Text(
                              details.status == 'termine'
                                  ? 'Modifier les statistiques'
                                  : 'Saisir le résultat et les statistiques',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (isFinished) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Pronostics révélés',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  if (details.predictions.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucun pronostic enregistré pour ce match.'),
                      ),
                    )
                  else
                    Card(
                      child: Column(
                        children: details.predictions
                            .map(
                              (prediction) => ListTile(
                                leading: const Icon(Icons.bolt_rounded),
                                title: Text(prediction.name),
                                trailing: Text(
                                  '${prediction.scoreGrinta} - ${prediction.scoreOpponent}',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                ],
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
                          '${match.scoreGrinta ?? '?'} - ${match.scoreOpponent ?? '?'}',
                        ),
                        subtitle: Text(
                          '${match.date.toLocal().toString().split(' ').first} • ${match.location}',
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
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
