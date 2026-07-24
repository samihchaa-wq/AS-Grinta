import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/admin_badge.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/match_date_column.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/home/presentation/home_next_match_card.dart';
import 'package:as_grinta/features/internal_matches/data/internal_matches_repository.dart';
import 'package:as_grinta/features/internal_matches/presentation/internal_match_form_page.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/match_form_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/match_history_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Contenu du nouvel onglet Matchs : le prochain match reprend toutes les
/// fonctions de l'ancien accueil, chaque match passé reprend la carte détaillée
/// « Dernier match » et les matchs internes restent totalement séparés des
/// pronostics, votes HDM et statistiques officielles.
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
      ..invalidate(historyMatchPredictionProvider)
      ..invalidate(internalMatchesProvider);
    await Future.wait([
      ref
          .read(matchesControllerProvider.notifier)
          .load(seasonId: state.selectedSeasonId, allSeasons: true),
      ref.read(homeDashboardProvider.future),
      ref.read(internalMatchesProvider.future),
    ]);
  }

  Future<void> _openOfficialForm(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MatchFormPage()),
    );
    if (!context.mounted) return;
    await _refresh();
  }

  Future<void> _openInternalForm(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InternalMatchFormPage()),
    );
    if (!context.mounted) return;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final dashboard = ref.watch(homeDashboardProvider);
    final internalAsync = ref.watch(internalMatchesProvider);
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
            _CreateMatchActions(
              onOfficial: () => _openOfficialForm(context),
              onInternal: () => _openInternalForm(context),
            ),
            const SizedBox(height: 18),
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
          else ...[
            const _SectionHeader(
              icon: Icons.event_rounded,
              title: 'Prochain match',
            ),
            if (state.matches.isEmpty)
              const _MessageCard(
                title: 'Pas de match officiel programmé',
                message:
                    'Le prochain match apparaîtra ici dès qu’il sera créé.',
              )
            else
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
                      title: 'Pas de match officiel programmé',
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
              icon: Icons.groups_2_outlined,
              title: 'Matchs entre nous',
            ),
            internalAsync.when(
              loading: () => const _LoadingCard(),
              error: (error, _) => _MessageCard(
                title: 'Matchs entre nous indisponibles',
                icon: Icons.wifi_off_rounded,
                message: error.toString(),
                tone: GrintaEmptyTone.alert,
              ),
              data: (internalMatches) {
                if (internalMatches.isEmpty) {
                  return const _MessageCard(
                    title: 'Aucun match entre nous',
                    message:
                        'Crée deux équipes libres depuis le bouton administrateur.',
                  );
                }
                final upcomingInternal = internalMatches
                    .where((match) => !match.isFinished)
                    .toList()
                  ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
                final finishedInternal = internalMatches
                    .where((match) => match.isFinished)
                    .toList()
                  ..sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final match in [
                      ...upcomingInternal,
                      ...finishedInternal,
                    ]) ...[
                      _InternalMatchCard(match: match, isAdmin: isAdmin),
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            const _SectionHeader(
              icon: Icons.history_rounded,
              title: 'Matchs officiels passés',
            ),
            if (finished.isEmpty)
              const _MessageCard(
                title: 'Aucun match officiel joué',
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

class _CreateMatchActions extends StatelessWidget {
  const _CreateMatchActions({
    required this.onOfficial,
    required this.onInternal,
  });

  final VoidCallback onOfficial;
  final VoidCallback onInternal;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onOfficial,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Match officiel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onInternal,
                icon: const Icon(Icons.groups_2_outlined),
                label: const Text('Match entre nous'),
              ),
            ),
          ],
        ),
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
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _InternalMatchCard extends StatelessWidget {
  const _InternalMatchCard({required this.match, required this.isAdmin});

  final InternalMatch match;
  final bool isAdmin;

  Future<void> _edit(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InternalMatchFormPage(match: match)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final score = match.isFinished
        ? '${match.scoreA ?? 0} – ${match.scoreB ?? 0}'
        : 'À venir';
    return Card(
      color: const Color(0xFF17251E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF4A9B71), width: 1.3),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isAdmin ? () => _edit(context) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.groups_2_outlined, color: Color(0xFF75D59F)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'MATCH ENTRE NOUS',
                      style: TextStyle(
                        color: Color(0xFF75D59F),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (isAdmin)
                    const Icon(Icons.edit_outlined, color: Color(0xFF75D59F)),
                ],
              ),
              const SizedBox(height: 12),
              MatchDateHeader(
                kickoffAt: match.kickoffAt,
                secondary: const Color(0xFFA8CDB7),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            match.teamAName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${match.teamAPlayers.length} joueur(s)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          Text(
                            score,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          if (!match.isFinished)
                            Text(
                              AppFormats.hourMinute(match.kickoffAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            match.teamBName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${match.teamBPlayers.length} joueur(s)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (match.address != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(match.address!)),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cards = [
                    _InternalTeamList(
                      name: match.teamAName,
                      players: match.teamAPlayers,
                    ),
                    _InternalTeamList(
                      name: match.teamBName,
                      players: match.teamBPlayers,
                    ),
                  ];
                  if (constraints.maxWidth >= 620) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cards.first),
                        const SizedBox(width: 10),
                        Expanded(child: cards.last),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      cards.first,
                      const SizedBox(height: 10),
                      cards.last,
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'Interne pur · aucun prono, HDM, classement ou statistique',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFA8CDB7),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InternalTeamList extends StatelessWidget {
  const _InternalTeamList({required this.name, required this.players});

  final String name;
  final List<InternalMatchPlayer> players;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF102019),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF315B43)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (players.isEmpty)
            const Text('Aucun joueur')
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final player in players)
                  Chip(
                    avatar: player.isGoalkeeper
                        ? const Icon(Icons.sports_handball, size: 16)
                        : null,
                    label: Text(player.name),
                  ),
              ],
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
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MatchFormPage(match: match)),
    );
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
