import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/match_form_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchesPage extends ConsumerStatefulWidget {
  const MatchesPage({super.key});

  @override
  ConsumerState<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends ConsumerState<MatchesPage> {
  String? _selectedSeasonId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(matchesControllerProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final matchesState = ref.watch(matchesControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final canDelete = authState.profile?.role == AuthRole.admin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matchs'),
        actions: [
          if (authState.profile?.role == AuthRole.admin)
            IconButton(
              tooltip: 'Créer un match',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MatchFormPage()),
                );
                if (!mounted) return;
                await ref
                    .read(matchesControllerProvider.notifier)
                    .load(seasonId: _selectedSeasonId);
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref
            .read(matchesControllerProvider.notifier)
            .load(seasonId: _selectedSeasonId),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (matchesState.seasons.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _selectedSeasonId,
                decoration: const InputDecoration(labelText: 'Saison'),
                items: [
                  const DropdownMenuItem<String>(
                      value: '', child: Text('Toutes les saisons')),
                  ...matchesState.seasons.map((season) {
                    return DropdownMenuItem<String>(
                      value: season['id'].toString(),
                      child: Text(season['name'].toString()),
                    );
                  }),
                ],
                onChanged: (value) async {
                  setState(
                      () => _selectedSeasonId = value == '' ? null : value);
                  await ref
                      .read(matchesControllerProvider.notifier)
                      .load(seasonId: value == '' ? null : value);
                },
              ),
            const SizedBox(height: 16),
            if (matchesState.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (matchesState.error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(matchesState.error!),
                ),
              )
            else if (matchesState.matches.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Aucun match pour le moment.'),
                ),
              )
            else
              ...matchesState.matches.map(
                  (match) => _MatchCard(match: match, canDelete: canDelete)),
          ],
        ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.canDelete});

  final MatchModel match;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${match.seasonName ?? 'Saison'} • ${match.opponentName ?? 'Adversaire'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(match.statusLabel)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                'Date : ${match.kickoffAt.toLocal().toString().split('.')[0]}'),
            Text('Lieu : ${match.locationLabel}'),
            Text('Durée : ${match.plannedDurationMinutes} min'),
            Text(
                'Score : ${match.grintaScore ?? '?'} - ${match.opponentScore ?? '?'}'),
            const SizedBox(height: 12),
            Row(
              children: [
                if (canDelete)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final notifier = ProviderScope.containerOf(context)
                          .read(matchesControllerProvider.notifier);
                      await notifier.deleteMatch(match.id);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Supprimer'),
                  ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => MatchFormPage(match: match)),
                    );
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed('/live/${match.id}');
                  },
                  icon: const Icon(Icons.sensors),
                  label: const Text('Live'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed('/matches/${match.id}/finalize');
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Finir'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
