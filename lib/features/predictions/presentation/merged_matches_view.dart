import 'package:as_grinta/app/shell/module_navigation.dart';
import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/match_window.dart';
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

/// Contenu de l'onglet Matchs.
///
/// Une seule machine temporelle alimente désormais les sections :
/// À venir → Prochain match → Match en direct → À valider → Matchs passés.
class MergedMatchesView extends ConsumerStatefulWidget {
  const MergedMatchesView({super.key});

  @override
  ConsumerState<MergedMatchesView> createState() => _MergedMatchesViewState();
}

class _MergedMatchesViewState extends ConsumerState<MergedMatchesView> {
  final GlobalKey _focusMatchKey = GlobalKey();
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

  void _focusRelevantMatch({
    required String? matchId,
    required bool cardIsReady,
    required String requestToken,
  }) {
    if (matchId == null || !cardIsReady) return;

    final signature = '$matchId:$requestToken';
    if (_lastFocusSignature == signature) return;
    _lastFocusSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _positionRelevantMatch(signature);
    });
  }

  Future<void> _positionRelevantMatch(String signature, {int attempt = 0}) async {
    if (!mounted || _lastFocusSignature != signature) return;

    final targetContext = _focusMatchKey.currentContext;
    if (targetContext == null) {
      if (attempt >= 8) {
        _lastFocusSignature = null;
        return;
      }

      await Future<void>.delayed(Duration(milliseconds: 20 + (attempt * 15)));
      if (!mounted || _lastFocusSignature != signature) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _positionRelevantMatch(signature, attempt: attempt + 1);
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
    final settledContext = _focusMatchKey.currentContext;
    if (settledContext == null || !settledContext.mounted) return;
    await Scrollable.ensureVisible(
      settledContext,
      alignment: 0,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      duration: Duration.zero,
    );
  }

  Future<void> _openMatchForm(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MatchFormPage()));
    if (!context.mounted) return;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final isAdmin = ref.watch(isAdminViewProvider);
    final now = DateTime.now();

    final upcomingMatches = <MatchModel>[];
    final nextMatches = <MatchModel>[];
    final liveMatches = <MatchModel>[];
    final awaitingValidationMatches = <MatchModel>[];
    final pastMatches = <MatchModel>[];

    for (final match in state.matches) {
      switch (match.phase(now: now)) {
        case MatchDisplayPhase.upcoming:
          upcomingMatches.add(match);
        case MatchDisplayPhase.next:
          nextMatches.add(match);
        case MatchDisplayPhase.live:
          liveMatches.add(match);
        case MatchDisplayPhase.awaitingValidation:
          awaitingValidationMatches.add(match);
        case MatchDisplayPhase.past:
          pastMatches.add(match);
        case MatchDisplayPhase.cancelled:
          if (match.kickoffAt.isAfter(now)) {
            upcomingMatches.add(match);
          } else {
            pastMatches.add(match);
          }
      }
    }

    upcomingMatches.sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
    nextMatches.sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
    liveMatches.sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
    awaitingValidationMatches.sort(
      (a, b) => a.kickoffAt.compareTo(b.kickoffAt),
    );
    pastMatches.sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));

    final MatchDisplayPhase? focusPhase;
    final String? focusMatchId;
    if (liveMatches.isNotEmpty) {
      focusPhase = MatchDisplayPhase.live;
      focusMatchId = liveMatches.first.id;
    } else if (awaitingValidationMatches.isNotEmpty) {
      focusPhase = MatchDisplayPhase.awaitingValidation;
      focusMatchId = awaitingValidationMatches.first.id;
    } else if (nextMatches.isNotEmpty) {
      focusPhase = MatchDisplayPhase.next;
      focusMatchId = nextMatches.first.id;
    } else {
      focusPhase = null;
      focusMatchId = null;
    }

    final focusRequest = ref.watch(matchesFocusRequestProvider);
    final focusCardIsReady = focusMatchId != null && !state.isLoading;

    _focusRelevantMatch(
      matchId: focusMatchId,
      cardIsReady: focusCardIsReady,
      requestToken: '$focusRequest',
    );

    final visibleCardCount = upcomingMatches.length +
        nextMatches.length +
        liveMatches.length +
        awaitingValidationMatches.length +
        pastMatches.length;
    final cacheExtent = 1000.0 + (visibleCardCount * 360.0);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        scrollCacheExtent: ScrollCacheExtent.pixels(cacheExtent),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: SizedBox(height: AppSpacing.microGap),
          ),
          if (state.isLoading)
            const SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.screenGutter,
              ),
              sliver: SliverToBoxAdapter(child: _LoadingCard()),
            )
          else if (state.error != null)
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenGutter,
              ),
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
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenGutter,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _MessageCard(
                      title: 'Aucun match',
                      message:
                          'Le premier match apparaîtra ici dès qu’il sera créé.',
                    ),
                    if (isAdmin) ...[
                      const SizedBox(height: AppSpacing.sectionGap),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          onPressed: () => _openMatchForm(context),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Ajouter un match'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 42),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.cardPadding,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else ...[
            if (upcomingMatches.isNotEmpty)
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenGutter,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.contentGap,
                          ),
                          child: _UpcomingMatchCard(
                            match: upcomingMatches[index],
                            isAdmin: isAdmin,
                          ),
                        ),
                        childCount: upcomingMatches.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.contentGap),
                  ),
                ],
              ),
            if (nextMatches.isNotEmpty)
              SliverMainAxisGroup(
                slivers: [
                  SliverPersistentHeader(
                    key: focusPhase == MatchDisplayPhase.next
                        ? _focusMatchKey
                        : null,
                    pinned: true,
                    delegate: const _SectionHeaderDelegate(
                      icon: Icons.bolt_rounded,
                      title: 'Prochain match',
                      emphasized: true,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenGutter,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: EdgeInsets.only(
                            bottom: index == nextMatches.length - 1
                                ? 0
                                : AppSpacing.contentGap,
                          ),
                          child: HomeNextMatchCard(
                            match: nextMatches[index],
                            isAdmin: isAdmin,
                          ),
                        ),
                        childCount: nextMatches.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.sectionGap),
                  ),
                ],
              ),
            if (liveMatches.isNotEmpty)
              SliverMainAxisGroup(
                slivers: [
                  SliverPersistentHeader(
                    key: focusPhase == MatchDisplayPhase.live
                        ? _focusMatchKey
                        : null,
                    pinned: true,
                    delegate: const _SectionHeaderDelegate(
                      icon: Icons.sensors_rounded,
                      title: 'Match en direct',
                      emphasized: true,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenGutter,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: EdgeInsets.only(
                            bottom: index == liveMatches.length - 1
                                ? 0
                                : AppSpacing.contentGap,
                          ),
                          child: HomeNextMatchCard(
                            match: liveMatches[index],
                            isAdmin: isAdmin,
                            initialSection:
                                liveMatches[index].isInternal ? 'composition' : 'live',
                            showAvailability:
                                now.isBefore(liveMatches[index].kickoffAt),
                          ),
                        ),
                        childCount: liveMatches.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.sectionGap),
                  ),
                ],
              ),
            if (awaitingValidationMatches.isNotEmpty)
              SliverMainAxisGroup(
                slivers: [
                  SliverPersistentHeader(
                    key: focusPhase == MatchDisplayPhase.awaitingValidation
                        ? _focusMatchKey
                        : null,
                    pinned: true,
                    delegate: const _SectionHeaderDelegate(
                      icon: Icons.fact_check_outlined,
                      title: 'À valider',
                      emphasized: true,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenGutter,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final match = awaitingValidationMatches[index];
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == awaitingValidationMatches.length - 1
                                  ? 0
                                  : AppSpacing.contentGap,
                            ),
                            child: HomeNextMatchCard(
                              match: match,
                              isAdmin: isAdmin,
                              initialSection: match.liveState == null
                                  ? 'info'
                                  : match.isInternal
                                      ? 'composition'
                                      : 'live',
                              showAvailability: false,
                            ),
                          );
                        },
                        childCount: awaitingValidationMatches.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.sectionGap),
                  ),
                ],
              ),
            if (isAdmin)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  0,
                  AppSpacing.screenGutter,
                  AppSpacing.sectionGap,
                ),
                sliver: SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openMatchForm(context),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Ajouter un match'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.cardPadding,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ),
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
                if (pastMatches.isEmpty)
                  const SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenGutter,
                    ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenGutter,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final match = pastMatches[index];
                        final card = match.isFinished
                            ? MatchHistoryCard(match: match)
                            : _UpcomingMatchCard(
                                match: match,
                                isAdmin: isAdmin,
                              );
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.contentGap,
                          ),
                          child: card,
                        );
                      }, childCount: pastMatches.length),
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
    final background = AppTheme.background;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.outline.withValues(
              alpha: overlapsContent ? .5 : .2,
            ),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
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
    final availabilityOpensAt = matchFeaturesOpenAt(match.kickoffAt);
    final availabilityIsOpen = !match.isCancelled &&
        !now.isBefore(availabilityOpensAt) &&
        now.isBefore(match.kickoffAt);
    final detailsRoute = availabilityIsOpen
        ? '/matches/${match.id}/lineup?section=info'
        : '/matches/${match.id}/lineup?section=info&infoOnly=true';

    final fixtureRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: match.isInternal
              ? Text(
                  '⚽ Match entre nous',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                )
              : MatchFixture(
                  homeName: homeName,
                  awayName: awayName,
                  grintaIsHome: match.isHome,
                  nameStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 16,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                  foreground: match.isCancelled
                      ? AppTheme.textFaint
                      : AppTheme.textPrimary,
                  textAlign: TextAlign.center,
                ),
        ),
        if (isAdmin) ...[
          const SizedBox(width: AppSpacing.microGap),
          SizedBox(width: 36, child: AdminMatchOptionsButton(match: match)),
        ],
        if (match.isCancelled)
          Text(
            'Annulé',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFFE5555A),
                  fontWeight: FontWeight.w800,
                ),
          )
        else
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: AppTheme.textFaint,
          ),
      ],
    );

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.cardPadding,
        12,
        AppSpacing.cardPadding,
        13,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MatchDateHeader(
            kickoffAt: match.kickoffAt,
            foreground:
                match.isCancelled ? AppTheme.textFaint : AppTheme.textPrimary,
            secondary: AppTheme.textSecondary,
            dividerColor: AppTheme.outline.withValues(alpha: .55),
            child: fixtureRow,
          ),
          if (match.address case final address?) ...[
            const SizedBox(height: AppSpacing.contentGap),
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
    );

    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(
          color: match.isCancelled
              ? const Color(0xFF6E4045)
              : AppTheme.outline.withValues(alpha: .34),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: match.isCancelled
          ? content
          : InkWell(onTap: () => context.push(detailsRoute), child: content),
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
