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
    final isStaff = isAdmin || isModerator;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matchs'),
        actions: [
          if (isStaff)
            IconButton(
              tooltip: 'Créer un match',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MatchFormPage()),
                );
                if (mounted) {
                  await ref.read(matchesControllerProvider.notifier).load(
                        seasonId: _selectedSeasonId,
                      );
                }
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(matchesControllerProvider.notifier).load(
              seasonId: _selectedSeasonId,
            ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (state.seasons.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _selectedSeasonId ?? '',
                decoration: const InputDecoration(labelText: 'Saison'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Toutes les saisons')),
                  ...state.seasons.map((season) => DropdownMenuItem(
                        value: season['id'].toString(),
                        child: Text(season['name'].toString()),
                      )),
                ],
                onChanged: (value) async {
                  final seasonId = value == null || value.isEmpty ? null : value;
                  setState(() => _selectedSeasonId = seasonId);
                  await ref.read(matchesControllerProvider.notifier).load(
                        seasonId: seasonId,
                      );
                },
              ),
            const SizedBox(height: 16),
            if (state.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (state.error != null)
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(state.error!)))
            else if (state.matches.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Aucun match pour le moment.')))
            else
              ...state.matches.map((match) => _MatchCard(
                    match: match,
                    isAdmin: isAdmin,
                    isModerator: isModerator,
                  )),
          ],
        ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.isAdmin, required this.isModerator});
  final MatchModel match;
  final bool isAdmin;
  final bool isModerator;

  @override
  Widget build(BuildContext context) {
    final isStaff = isAdmin || isModerator;
    final canEnterStats = isStaff && !match.isArchived;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(_scoreLine(), style: Theme.of(context).textTheme.titleMedium)),
            const SizedBox(width: 8),
            Chip(label: Text(match.statusLabel)),
          ]),
          const SizedBox(height: 8),
          Text(_formatKickoff(match.kickoffAt)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => context.push('/matches/${match.id}'),
              icon: const Icon(Icons.history),
              label: const Text('Détails'),
            ),
            if (isStaff && !match.isArchived)
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => MatchFormPage(match: match)),
                  );
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Modifier'),
              ),
            if (canEnterStats)
              FilledButton.icon(
                onPressed: () => context.push('/matches/${match.id}/finalize'),
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(
                  match.status == 'termine' ? 'Modifier les stats' : 'Saisir le résultat',
                ),
              ),
            if (isAdmin && !match.isArchived && match.status == 'termine')
              OutlinedButton.icon(
                onPressed: () => ProviderScope.containerOf(context)
                    .read(matchesControllerProvider.notifier)
                    .archiveMatch(match.id),
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archiver'),
              ),
            if (isModerator)
              OutlinedButton.icon(
                onPressed: () => ProviderScope.containerOf(context)
                    .read(matchesControllerProvider.notifier)
                    .deleteMatch(match.id),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer'),
              ),
          ]),
        ]),
      ),
    );
  }

  String _scoreLine() {
    final opponent = match.opponentName ?? 'Adversaire';
    final grinta = match.grintaScore?.toString() ?? 'X';
    final adverse = match.opponentScore?.toString() ?? 'X';
    return match.isHome
        ? 'AS Grinta $grinta - $adverse $opponent'
        : '$opponent $adverse - $grinta AS Grinta';
  }

  String _formatKickoff(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} • ${two(local.hour)}h${two(local.minute)}';
  }
}
