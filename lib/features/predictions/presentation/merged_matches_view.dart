import 'package:as_grinta/app/shell/module_navigation.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:as_grinta/core/widgets/match_date_column.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
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
    await ref
        .read(matchesControllerProvider.notifier)
        .load(seasonId: state.selectedSeasonId, allSeasons: true);
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

  Future<void> _openMatchForm(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MatchFormPage()),
    );
    if (!context.mounted) return;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final isAdmin = ref.watch(isAdminViewProvider);

    final upcoming = state.matches.where((match) => !match.isFinished).toList()
      ..sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));
    final finished = state.matches.where((match) => match.isFinished).toList()
      ..sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));
    final nextMatch = upcoming.isEmpty ? null : upcoming.last;
    final nextMatchId = nextMatch?.id;
    final laterUpcoming = upcoming.length > 1
        ? upcoming.sublist(0, upcoming.length - 1)
        : <MatchModel>[];

    final focusRequest = ref.watch(matchesFocusRequestProvider);
    final nextCardIsReady = nextMatch != null && !state.isLoading;

    _focusNextMatch(
      matchId: nextMatchId,
      cardIsReady: nextCardIsReady,
      requestToken: '$focusRequest',
    );

    final nextMatchCacheExtent = 1000.0 + (laterUpcoming.length * 360.0);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        scrollCacheExtent: ScrollCacheExtent.pixels(nextMatchCacheExtent),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 4)),
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
            SliverMainAxisGroup(
              slivers: [
                SliverPersistentHeader(
                  key: _nextMatchKey,
                  pinned: true,
                  delegate: const _SectionHeaderDelegate(
                    icon: Icons.bolt_rounded,
                    title: 'Prochain match',
                    emphasized: true,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: nextMatch == null
                        ? const _MessageCard(
                            title: 'Pas de match programmé',
                            message:
                                'Le prochain match apparaîtra ici dès qu’il sera créé.',
                          )
                        : HomeNextMatchCard(
                            match: nextMatch,
                            isAdmin: isAdmin,
                          ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 14)),
              ],
            ),
            if (isAdmin)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openMatchForm(context),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Ajouter un match'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ),
              ),
            if (laterUpcoming.isNotEmpty)
              SliverMainAxisGroup(
                slivers: [
                  const SliverPersistentHeader(
                    pinned: true,
                    delegate: _SectionHeaderDelegate(
                      icon: Icons.calendar_month_outlined,
                      title: 'À venir',
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _UpcomingMatchCard(
                            match: laterUpcoming[index],
                            isAdmin: isAdmin,
                          ),
                        ),
                        childCount: laterUpcoming.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ],
              ),
            SliverMainAxisGroup(
              slivers: [
                const SliverPersistentHeader(
                  pinned: true,
                  delegate: _SectionHeaderDelegate(
                    icon: Icons.history_rounded,
                    title: 'Résultats',
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
                          padding: const EdgeInsets.only(bottom: 8),
                          child: MatchHistoryCard(match: finished[index]),
                        ),
                        childCount: finished.length,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SectionHeaderDelegate({
    required this.icon,
    required this.title,
    this.emphasized = false,
  });

  static const double _height = 38;

  final IconData icon;
  final String title;
  final bool emphasized;

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
    final background = overlapsContent
        ? AppTheme.background.withValues(alpha: .96)
        : AppTheme.background.withValues(alpha: .78);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.outline.withValues(alpha: overlapsContent ? .5 : .2),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              icon,
              size: emphasized ? 18 : 17,
              color: emphasized ? AppTheme.primaryBright : AppTheme.textFaint,
            ),
            const SizedBox(width: 7),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: emphasized
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    fontWeight: emphasized ? FontWeight.w900 : FontWeight.w800,
                    letterSpacing: emphasized ? -.15 : 0,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SectionHeaderDelegate oldDelegate) {
    return oldDelegate.icon != icon ||
        oldDelegate.title != title ||
        oldDelegate.emphasized != emphasized;
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
            nameStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: 16,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                ),
            foreground: AppTheme.textPrimary,
            textAlign: TextAlign.center,
          ),
        ),
        if (isAdmin) ...[
          const SizedBox(width: 4),
          SizedBox(width: 36, child: AdminMatchOptionsButton(match: match)),
        ],
        const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: AppTheme.textFaint,
        ),
      ],
    );

    return Card(
      color: AppTheme.surface.withValues(alpha: .72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(color: AppTheme.outline.withValues(alpha: .34)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(detailsRoute),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MatchDateHeader(
                kickoffAt: match.kickoffAt,
                foreground: AppTheme.textPrimary,
                secondary: AppTheme.textSecondary,
                dividerColor: AppTheme.outline.withValues(alpha: .55),
                child: fixtureRow,
              ),
              if (match.address case final address?) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => showMatchAddressSheet(context, address),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          size: 16,
                          color: AppTheme.textFaint,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.textFaint,
                                  fontWeight: FontWeight.w600,
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
                  topSpacing: 10,
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
        child: Center(child: GrintaProgressIndicator()),
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
