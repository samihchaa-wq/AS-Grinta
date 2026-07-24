import 'package:as_grinta/app/shell/module_navigation.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:as_grinta/core/widgets/match_date_column.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/home/presentation/home_next_match_card.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/match_form_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/matches/presentation/widgets/admin_match_options_button.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/match_history_card.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  final GlobalKey _nextMatchKey = GlobalKey();
  String? _lastFocusSignature;

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

  void _focusNextMatch({
    required String? matchId,
    required bool cardIsReady,
    required String requestToken,
  }) {
    if (matchId == null || !cardIsReady) return;

    final signature = '$matchId:$requestToken';
    if (_lastFocusSignature == signature) return;
    _lastFocusSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _positionNextMatch(signature);
    });
  }

  Future<void> _positionNextMatch(String signature, {int attempt = 0}) async {
    if (!mounted || _lastFocusSignature != signature) return;

    final targetContext = _nextMatchKey.currentContext;
    if (targetContext == null) {
      if (attempt >= 8) {
        _lastFocusSignature = null;
        return;
      }

      await Future<void>.delayed(Duration(milliseconds: 20 + (attempt * 15)));
      if (!mounted || _lastFocusSignature != signature) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _positionNextMatch(signature, attempt: attempt + 1);
      });
      return;
    }

    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      duration: Duration.zero,
    );

    // La liste construit ses enfants à la demande. Un second positionnement
    // après stabilisation empêche le premier accès depuis un autre module de
    // rester en haut de la liste lorsque les cartes précédentes apparaissent.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || _lastFocusSignature != signature) return;
    final settledContext = _nextMatchKey.currentContext;
    if (settledContext == null || !settledContext.mounted) return;
    await Scrollable.ensureVisible(
      settledContext,
      alignment: 0,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      duration: Duration.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final dashboard = ref.watch(homeDashboardProvider);
    final isAdmin = ref.watch(isAdminViewProvider);

    final upcoming = state.matches.where((match) => !match.isFinished).toList()
      ..sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));
    final finished = state.matches.where((match) => match.isFinished).toList()
      ..sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));
    final nextMatchId = upcoming.isEmpty ? null : upcoming.last.id;
    final laterUpcoming = upcoming.length > 1
        ? upcoming.sublist(0, upcoming.length - 1)
        : <MatchModel>[];

    final focusRequest = ref.watch(matchesFocusRequestProvider);
    final nextCardIsReady = dashboard.valueOrNull?.nextMatch?.id == nextMatchId;

    _focusNextMatch(
      matchId: nextMatchId,
      cardIsReady: nextCardIsReady,
      requestToken: '$focusRequest',
    );

    // Le prochain match se trouve après toutes les rencontres plus lointaines.
    // Ce cache ciblé force la création de son ancre dès le premier affichage,
    // sans construire inutilement tout l'historique situé en dessous.
    final nextMatchCacheExtent = 1200.0 + (laterUpcoming.length * 520.0);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        scrollCacheExtent: ScrollCacheExtent.pixels(nextMatchCacheExtent),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          if (isAdmin)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Center(
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
                ),
              ),
            ),
          if (state.isLoading)
            const SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(child: _LoadingCard()),
            )
          else if (state.error != null)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: _MessageCard(
                  title: 'Matchs indisponibles',
                  icon: Icons.wifi_off_rounded,
                  message: state.error!,
                  tone: GrintaEmptyTone.alert,
                ),
              ),
            )
          else if (state.matches.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: _MessageCard(
                  title: 'Aucun match',
                  message:
                      'Le premier match apparaîtra ici dès qu’il sera créé.',
                ),
              ),
            )
          else ...[
            if (laterUpcoming.isNotEmpty)
              SliverMainAxisGroup(
                slivers: [
                  const SliverPersistentHeader(
                    pinned: true,
                    delegate: _SectionHeaderDelegate(
                      icon: Icons.calendar_month_outlined,
                      title: 'Matchs à venir',
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _UpcomingMatchCard(
                            match: laterUpcoming[index],
                            isAdmin: isAdmin,
                          ),
                        ),
                        childCount: laterUpcoming.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 10)),
                ],
              ),
            SliverMainAxisGroup(
              slivers: [
                SliverPersistentHeader(
                  key: _nextMatchKey,
                  pinned: true,
                  delegate: const _SectionHeaderDelegate(
                    icon: Icons.event_rounded,
                    title: 'Prochain match',
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: dashboard.when(
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
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
              ],
            ),
            SliverMainAxisGroup(
              slivers: [
                const SliverPersistentHeader(
                  pinned: true,
                  delegate: _SectionHeaderDelegate(
                    icon: Icons.history_rounded,
                    title: 'Matchs passés',
                  ),
                ),
                if (finished.isEmpty)
                  const SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: _MessageCard(
                        title: 'Aucun match joué',
                        message:
                            'Les résultats, buteurs, HDM et points de prono apparaîtront ici.',
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: MatchHistoryCard(match: finished[index]),
                        ),
                        childCount: finished.length,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SectionHeaderDelegate({required this.icon, required this.title});

  static const double _height = 44;

  final IconData icon;
  final String title;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: overlapsContent
          ? const Color(0xF2071738)
          : const Color(0xB3071738),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SectionHeaderDelegate oldDelegate) {
    return oldDelegate.icon != icon || oldDelegate.title != title;
  }
}

class _UpcomingMatchCard extends StatelessWidget {
  const _UpcomingMatchCard({required this.match, required this.isAdmin});

  final MatchModel match;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final opponent = match.opponentName ?? 'Adversaire';
    final homeName = match.isHome ? 'AS Grinta' : opponent;
    final awayName = match.isHome ? opponent : 'AS Grinta';
    final now = DateTime.now();
    final availabilityOpensAt = match.kickoffAt.subtract(
      const Duration(days: 6),
    );
    final availabilityIsOpen =
        !now.isBefore(availabilityOpensAt) && now.isBefore(match.kickoffAt);
    final detailsRoute = availabilityIsOpen
        ? '/matches/${match.id}/lineup?section=info'
        : '/matches/${match.id}/lineup?section=info&infoOnly=true';

    final fixtureRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: MatchFixture(
            homeName: homeName,
            awayName: awayName,
            grintaIsHome: match.isHome,
            nameStyle: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontSize: 18, height: 1.1),
            foreground: Colors.white,
            textAlign: TextAlign.center,
          ),
        ),
        if (isAdmin) ...[
          const SizedBox(width: 2),
          SizedBox(width: 38, child: AdminMatchOptionsButton(match: match)),
        ],
        const Icon(Icons.chevron_right, size: 22, color: Color(0xFFD7C8FF)),
      ],
    );

    return Card(
      color: const Color(0xFF25164F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF9B6CFF), width: 1.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(detailsRoute),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MatchDateHeader(
                kickoffAt: match.kickoffAt,
                foreground: Colors.white,
                secondary: const Color(0xFFD7C8FF),
                dividerColor: const Color(0xFF7A5AB7),
                child: fixtureRow,
              ),
              if (match.address case final address?) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => showMatchAddressSheet(context, address),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          size: 18,
                          color: Color(0xFF9B6CFF),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            address,
                            style: const TextStyle(
                              color: Color(0xFF9B6CFF),
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline,
                              decorationColor: Color(0xFF9B6CFF),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (availabilityIsOpen)
                MatchAvailabilitySelector(
                  matchId: match.id,
                  embeddedOnDark: true,
                  topSpacing: 14,
                ),
            ],
          ),
        ),
      ),
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
