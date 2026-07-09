import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/match_form_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    final role = authState.profile?.role;
    final isAdmin = role == AuthRole.admin;
    final isModerator = role == AuthRole.moderateur;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matchs'),
        actions: [
          if (isAdmin)
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
                value: _selectedSeasonId,
                decoration: const InputDecoration(labelText: 'Saison'),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('Toutes les saisons'),
                  ),
                  ...matchesState.seasons.map((season) {
                    return DropdownMenuItem<String>(
                      value: season['id'].toString(),
                      child: Text(season['name'].toString()),
                    );
                  }),
                ],
                onChanged: (value) async {
                  setState(() => _selectedSeasonId = value == '' ? null : value);
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
                (match) => _MatchCard(
                  match: match,
                  canDelete: isModerator,
                  canEdit: isAdmin && !match.isArchived,
                  canManageLive: isAdmin && !match.isArchived,
                  canFinalize: isAdmin && !match.isArchived,
                  canSelectParticipants: isAdmin && !match.isArchived,
                  canArchive: isAdmin && !match.isArchived,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.canDelete,
    required this.canEdit,
    required this.canManageLive,
    required this.canFinalize,
    required this.canSelectParticipants,
    required this.canArchive,
  });

  final MatchModel match;
  final bool canDelete;
  final bool canEdit;
  final bool canManageLive;
  final bool canFinalize;
  final bool canSelectParticipants;
  final bool canArchive;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/matches/${match.id}'),
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
                'Date : ${match.kickoffAt.toLocal().toString().split('.')[0]}',
              ),
              Text('Lieu : ${match.locationLabel}'),
              Text('Durée : ${match.plannedDurationMinutes} min'),
              Text(
                'Score : ${match.grintaScore ?? '?'} - ${match.opponentScore ?? '?'}',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.push('/matches/${match.id}'),
                    icon: const Icon(Icons.history),
                    label: const Text('Détails'),
                  ),
                  if (canDelete)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final notifier = ProviderScope.containerOf(context)
                            .read(matchesControllerProvider.notifier);
                        await notifier.deleteMatch(match.id);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Supprimer définitivement'),
                    ),
                  if (canEdit)
                    FilledButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MatchFormPage(match: match),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Modifier'),
                    ),
                  if (canSelectParticipants)
                    OutlinedButton.icon(
                      onPressed: () => context.push(
                        '/matches/${match.id}/participants',
                      ),
                      icon: const Icon(Icons.groups_outlined),
                      label: const Text('Participants'),
                    ),
                  if (canManageLive)
                    OutlinedButton.icon(
                      onPressed: () => context.push('/live/${match.id}'),
                      icon: const Icon(Icons.sensors),
                      label: const Text('Live'),
                    ),
                  if (canFinalize)
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/matches/${match.id}/finalize'),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Finir'),
                    ),
                  if (canArchive)
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ProviderScope.containerOf(context)
                            .read(matchesControllerProvider.notifier)
                            .archiveMatch(match.id);
                      },
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Archiver'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
