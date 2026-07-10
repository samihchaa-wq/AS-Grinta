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
    final state = ref.watch(matchesControllerProvider);
    final role = ref.watch(authControllerProvider).profile?.role;
    final isAdmin = role == AuthRole.admin;
    final isModerator = role == AuthRole.moderateur;
    final canManage = isAdmin || isModerator;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matchs'),
        actions: [
          if (canManage)
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
            if (state.seasons.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _selectedSeasonId,
                decoration: const InputDecoration(labelText: 'Saison'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Toutes')),
                  ...state.seasons.map(
                    (season) => DropdownMenuItem(
                      value: season['id'].toString(),
                      child: Text(season['name'].toString()),
                    ),
                  ),
                ],
                onChanged: (value) async {
                  setState(
                    () => _selectedSeasonId = value == '' ? null : value,
                  );
                  await ref
                      .read(matchesControllerProvider.notifier)
                      .load(seasonId: _selectedSeasonId);
                },
              ),
            const SizedBox(height: 16),
            if (state.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (state.error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(state.error!),
                ),
              )
            else if (state.matches.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Aucun match pour le moment.'),
                ),
              )
            else
              ...state.matches.map(
                (match) => _MatchCard(
                  match: match,
                  canDelete: isModerator,
                  canEdit: canManage && !match.isArchived,
                  canFinalize: isAdmin && !match.isFinished,
                  canArchive: isAdmin && match.isFinished && !match.isArchived,
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
    required this.canFinalize,
    required this.canArchive,
  });

  final MatchModel match;
  final bool canDelete;
  final bool canEdit;
  final bool canFinalize;
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
                      _scoreLine(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Chip(label: Text(match.statusLabel)),
                ],
              ),
              const SizedBox(height: 6),
              Text(match.competition),
              Text(_formatKickoff(match.kickoffAt)),
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
                  if (canEdit)
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MatchFormPage(match: match),
                        ),
                      ),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Modifier'),
                    ),
                  if (canFinalize)
                    FilledButton.icon(
                      onPressed: () =>
                          context.push('/matches/${match.id}/finalize'),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Saisir les statistiques'),
                    ),
                  if (canArchive)
                    OutlinedButton.icon(
                      onPressed: () => ProviderScope.containerOf(context)
                          .read(matchesControllerProvider.notifier)
                          .archiveMatch(match.id),
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Archiver'),
                    ),
                  if (canDelete)
                    OutlinedButton.icon(
                      onPressed: () => ProviderScope.containerOf(context)
                          .read(matchesControllerProvider.notifier)
                          .deleteMatch(match.id),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Supprimer'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _scoreLine() {
    final opponent = match.opponentName ?? 'Adversaire';
    if (!match.isFinished) {
      return match.isHome ? 'AS Grinta – $opponent' : '$opponent – AS Grinta';
    }
    final grinta = match.grintaScore ?? 0;
    final adverse = match.opponentScore ?? 0;
    return match.isHome
        ? 'AS Grinta $grinta - $adverse $opponent'
        : '$opponent $adverse - $grinta AS Grinta';
  }

  String _formatKickoff(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} • '
        '${two(value.hour)}h${two(value.minute)} • ${match.locationLabel}';
  }
}
