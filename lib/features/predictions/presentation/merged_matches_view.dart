import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/admin_badge.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/match_date_column.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/home/presentation/home_next_match_card.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/match_form_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/match_history_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Contenu du nouvel onglet Matchs : le prochain match reprend toutes les
/// fonctions de l'ancien accueil et chaque match passé reprend la carte
/// détaillée « Dernier match ».
class MergedMatchesView extends ConsumerStatefulWidget {
  const MergedMatchesView({super.key});

  @override
  ConsumerState<MergedMatchesView> createState() => _MergedMatchesViewState();
}

class _MergedMatchesViewState extends ConsumerState<MergedMatchesView> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(matchesControllerProvider.notifier).load(allSeasons: true),
    );
  }

  Future<void> _refresh() async {
    final state = ref.read(matchesControllerProvider);
    ref
      ..invalidate(homeDashboardProvider)
      ..invalidate(myLastPronoProvider)
      ..invalidate(historyMatchPredictionProvider);
    await Future.wait([
      ref
          .read(matchesControllerProvider.notifier)
          .load(seasonId: state.selectedSeasonId, allSeasons: true),
      ref.read(homeDashboardProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final dashboard = ref.watch(homeDashboardProvider);
    final isAdmin = ref.watch(isAdminViewProvider);

    final upcoming = state.matches.where((match) => !match.isFinished).toList()
      ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
    final finished = state.matches.where((match) => match.isFinished).toList()
      ..sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));
    final nextMatchId = upcoming.isEmpty ? null : upcoming.first.id;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (isAdmin) ...[
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '👑 Ajouter un match',
                    iconSize: 46,
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MatchFormPage(),
                        ),
                      );
                      if (!context.mounted) return;
                      await _refresh();
                    },
                    icon: const Icon(Icons.add_circle),
                  ),
                  Text(
                    '👑 Ajouter un match',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (state.isLoading)
            const _LoadingCard()
          else if (state.error != null)
            _MessageCard(
              title: 'Matchs indisponibles',
              icon: Icons.wifi_off_rounded,
              message: state.error!,
              tone: GrintaEmptyTone.alert,
            )
          else if (state.matches.isEmpty)
            const _MessageCard(
              title: 'Aucun match',
              message: 'Le premier match apparaîtra ici dès qu’il sera créé.',
            )
          else ...[
            const _SectionHeader(
              icon: Icons.event_rounded,
              title: 'Prochain match',
            ),
            dashboard.when(
              loading: () => const _LoadingCard(),
              error: (_, __) => const _MessageCard(
                title: 'Prochain match indisponible',
                icon: Icons.wifi_off_rounded,
                message: 'Tire pour rafraîchir.',
                tone: GrintaEmptyTone.alert,
              ),
              data: (data) {
                final next = data.nextMatch;
                if (next == null || next.id != nextMatchId) {
                  return const _MessageCard(
                    title: 'Pas de match programmé',
                    message:
                        'Le prochain match apparaîtra ici dès qu’il sera créé.',
                  );
                }
                return HomeNextMatchCard(
                  match: next,
                  predicted: data.nextMatchPredicted,
                  prediction: data.nextMatchPrediction,
                  isAdmin: isAdmin,
                );
              },
            ),
            if (upcoming.length > 1) ...[
              const SizedBox(height: 22),
              const _SectionHeader(
                icon: Icons.calendar_month_outlined,
                title: 'Matchs à venir',
              ),
              for (final match in upcoming.skip(1)) ...[
                _UpcomingMatchCard(match: match, isAdmin: isAdmin),
                const SizedBox(height: 12),
              ],
            ],
            const SizedBox(height: 22),
            const _SectionHeader(
              icon: Icons.history_rounded,
              title: 'Matchs passés',
            ),
            if (finished.isEmpty)
              const _MessageCard(
                title: 'Aucun match joué',
                message:
                    'Les résultats, buteurs, HDM et points de prono apparaîtront ici.',
              )
            else
              for (final match in finished) ...[
                MatchHistoryCard(match: match),
                const SizedBox(height: 12),
              ],
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _UpcomingMatchCard extends ConsumerWidget {
  const _UpcomingMatchCard({required this.match, required this.isAdmin});

  final MatchModel match;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opponent = match.opponentName ?? 'Adversaire';
    final homeName = match.isHome ? 'AS Grinta' : opponent;
    final awayName = match.isHome ? opponent : 'AS Grinta';

    return Card(
      color: const Color(0xFF102A56),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF4B8DFF), width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/matches/${match.id}/lineup?section=info'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MatchDateHeader(
                kickoffAt: match.kickoffAt,
                secondary: const Color(0xFFA9C8FF),
                child: Row(
                  children: [
                    Expanded(
                      child: MatchFixture(
                        homeName: homeName,
                        awayName: awayName,
                        grintaIsHome: match.isHome,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'À venir',
                      style: TextStyle(
                        color: Color(0xFF7FB0FF),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (isAdmin) ...[
                const SizedBox(height: 12),
                _AdminMatchActions(match: match),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminMatchActions extends ConsumerWidget {
  const _AdminMatchActions({required this.match});

  final MatchModel match;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => MatchFormPage(match: match)));
    if (!context.mounted) return;
    ref
      ..invalidate(homeDashboardProvider)
      ..invalidate(matchDetailsProvider(match.id));
    await ref.read(matchesControllerProvider.notifier).load(allSeasons: true);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Supprimer ce match ?'),
            content: const Text(
              'Le match, ses pronostics, ses buteurs et ses statistiques seront '
              'définitivement supprimés.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    await ref.read(matchesControllerProvider.notifier).deleteMatch(match.id);
    ref
      ..invalidate(homeDashboardProvider)
      ..invalidate(historyMatchPredictionProvider)
      ..invalidate(matchDetailsProvider(match.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const AdminBadge(),
        PopupMenuButton<String>(
          tooltip: 'Options du match',
          icon: const Text('✏️', style: TextStyle(fontSize: 22)),
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _edit(context, ref);
              case 'stats':
                context.push('/matches/${match.id}/finalize');
              case 'delete':
                _delete(context, ref);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('⚙️  Modifier')),
            PopupMenuItem(value: 'stats', child: Text('📈  Stats')),
            PopupMenuItem(value: 'delete', child: Text('🚫  Supprimer')),
          ],
        ),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.title,
    this.icon = Icons.sports_soccer_rounded,
    this.message,
    this.tone = GrintaEmptyTone.neutral,
  });

  final String title;
  final IconData icon;
  final String? message;
  final GrintaEmptyTone tone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: GrintaEmptyState(
        icon: icon,
        title: title,
        message: message,
        tone: tone,
        compact: true,
      ),
    );
  }
}
