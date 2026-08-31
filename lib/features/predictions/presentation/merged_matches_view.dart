import 'package:as_grinta/app/shell/module_navigation.dart';
import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/calendar_card_palette.dart';
import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:as_grinta/core/widgets/match_date_column.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/home/presentation/home_next_match_card.dart';
import 'package:as_grinta/features/matches/data/calendar_history_repository.dart';
import 'package:as_grinta/features/matches/data/club_events_repository.dart';
import 'package:as_grinta/features/matches/domain/club_event.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/matches/presentation/widgets/admin_match_options_button.dart';
import 'package:as_grinta/features/matches/presentation/widgets/calendar_feed_event_card.dart';
import 'package:as_grinta/features/matches/presentation/widgets/historical_match_card.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/match_history_card.dart';
import 'package:as_grinta/features/sports_management/presentation/match_availability_provider.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

double? _persistedMergedMatchesScrollOffset;

class MergedMatchesView extends ConsumerStatefulWidget {
  const MergedMatchesView({super.key});

  @override
  ConsumerState<MergedMatchesView> createState() => _MergedMatchesViewState();
}

class _MergedMatchesViewState extends ConsumerState<MergedMatchesView> {
  final GlobalKey _focusMatchKey = GlobalKey();
  late final ScrollController _scrollController;
  String? _lastFocusSignature;
  bool _userScrollInterrupted = false;

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrollInterrupted = true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: _persistedMergedMatchesScrollOffset ?? 0,
    );
    Future.microtask(
      () => ref.read(matchesControllerProvider.notifier).load(allSeasons: true),
    );
  }

  @override
  void dispose() {
    if (_scrollController.hasClients) {
      _persistedMergedMatchesScrollOffset = _scrollController.offset;
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final state = ref.read(matchesControllerProvider);
    ref.invalidate(clubEventsProvider);
    ref.invalidate(allHistoricalMatchesProvider);
    await ref
        .read(matchesControllerProvider.notifier)
        .load(seasonId: state.selectedSeasonId, allSeasons: true);
  }

  void _focusRelevantMatch({
    required String? focusKey,
    required int? focusIndex,
    required int totalEntries,
    required bool cardIsReady,
    required String requestToken,
  }) {
    if (focusKey == null || focusIndex == null || !cardIsReady) return;

    final signature = '$focusKey:$requestToken';
    if (_lastFocusSignature == signature) return;
    _lastFocusSignature = signature;
    _userScrollInterrupted = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _positionRelevantMatch(
        signature,
        focusIndex: focusIndex,
        totalEntries: totalEntries,
      );
    });
  }

  Future<void> _positionRelevantMatch(
    String signature, {
    required int focusIndex,
    required int totalEntries,
    int attempt = 0,
  }) async {
    if (!mounted ||
        _lastFocusSignature != signature ||
        _userScrollInterrupted) {
      return;
    }

    if (_scrollController.hasClients && totalEntries > 0) {
      final position = _scrollController.position;
      final estimated = position.maxScrollExtent * (focusIndex / totalEntries);
      if ((position.pixels - estimated).abs() > 200) {
        position.jumpTo(estimated.clamp(0.0, position.maxScrollExtent));
      }
    }

    final targetContext = _focusMatchKey.currentContext;
    if (targetContext == null) {
      if (attempt >= 20) {
        _lastFocusSignature = null;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (!mounted ||
          _lastFocusSignature != signature ||
          _userScrollInterrupted) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _positionRelevantMatch(
          signature,
          focusIndex: focusIndex,
          totalEntries: totalEntries,
          attempt: attempt + 1,
        );
      });
      return;
    }

    for (var i = 0; i < 6; i += 1) {
      if (!mounted ||
          _lastFocusSignature != signature ||
          _userScrollInterrupted) {
        return;
      }
      final ctx = _focusMatchKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        duration: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final isAdmin = ref.watch(isAdminViewProvider);
    final events =
        ref.watch(clubEventsProvider).valueOrNull ?? const <ClubEvent>[];
    final historicalMatches =
        ref.watch(allHistoricalMatchesProvider).valueOrNull ??
            const <HistoricalMatchResult>[];
    final now = DateTime.now();

    final entries = <_FeedEntry>[];
    for (final match in state.matches) {
      switch (match.phase(now: now)) {
        case MatchDisplayPhase.upcoming:
          entries.add(_FeedEntry.match(match, _FeedKind.upcomingMatch));
        case MatchDisplayPhase.next:
          entries.add(_FeedEntry.match(match, _FeedKind.nextMatch));
        case MatchDisplayPhase.live:
          entries.add(_FeedEntry.match(match, _FeedKind.liveMatch));
        case MatchDisplayPhase.awaitingValidation:
          entries.add(
            _FeedEntry.match(match, _FeedKind.awaitingValidationMatch),
          );
        case MatchDisplayPhase.past:
          entries.add(_FeedEntry.match(match, _FeedKind.pastMatch));
        case MatchDisplayPhase.cancelled:
          entries.add(
            _FeedEntry.match(
              match,
              match.kickoffAt.isAfter(now)
                  ? _FeedKind.upcomingMatch
                  : _FeedKind.pastMatch,
            ),
          );
      }
    }
    entries.addAll(events.map((event) => _FeedEntry.event(event, now: now)));
    entries.addAll(historicalMatches.map(_FeedEntry.historical));

    entries.sort((a, b) => a.date.compareTo(b.date));
    final feedSections = _buildFeedSections(entries);

    int? focusIndex;
    for (var i = 0; i < entries.length; i += 1) {
      if (entries[i].date.isAfter(now)) break;
      focusIndex = i;
    }
    if (focusIndex == null && entries.isNotEmpty) {
      focusIndex = 0;
    }

    final focusKey = focusIndex == null ? null : _entryKey(entries[focusIndex]);
    final focusRequest = ref.watch(matchesFocusRequestProvider);
    final focusCardIsReady = focusKey != null && !state.isLoading;

    _focusRelevantMatch(
      focusKey: focusKey,
      focusIndex: focusIndex,
      totalEntries: entries.length,
      cardIsReady: focusCardIsReady,
      requestToken: '$focusRequest',
    );

    const cacheExtent = 1800.0;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: CustomScrollView(
          controller: _scrollController,
          scrollCacheExtent: const ScrollCacheExtent.pixels(cacheExtent),
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
            else if (entries.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenGutter,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MessageCard(
                        title: 'Aucun match',
                        message:
                            'Le premier match apparaîtra ici dès qu’il sera créé.',
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._buildFeedSlivers(
                sections: feedSections,
                focusKey: focusKey,
                focusMatchKey: _focusMatchKey,
                isAdmin: isAdmin,
                now: now,
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}

String _entryKey(_FeedEntry entry) {
  if (entry.match != null) return 'match:${entry.match!.id}';
  if (entry.event != null) return 'event:${entry.event!.id}';
  if (entry.historical != null) return 'historical:${entry.historical!.id}';
  return 'unknown';
}

/// Regroupe les sections d'une même phase (« Terminés », « À venir ») dans un
/// bloc de défilement.
///
/// Un en-tête collant reste épinglé au bloc qui le contient : celui de la
/// phase précédente se fait pousser hors de l'écran par le suivant au lieu de
/// s'empiler avec lui et de rogner le haut des cartes.
List<Widget> _buildFeedSlivers({
  required List<_FeedSection> sections,
  required String? focusKey,
  required GlobalKey focusMatchKey,
  required bool isAdmin,
  required DateTime now,
}) {
  final slivers = <Widget>[];
  var group = <Widget>[];

  void closeGroup() {
    if (group.isEmpty) return;
    slivers.add(SliverMainAxisGroup(slivers: group));
    group = <Widget>[];
  }

  for (final section in sections) {
    if (section.showPhaseTitle) closeGroup();
    group.addAll(
      _buildFeedSectionSlivers(
        section: section,
        isLastSection: section == sections.last,
        focusKey: focusKey,
        focusMatchKey: focusMatchKey,
        isAdmin: isAdmin,
        now: now,
      ),
    );
  }
  closeGroup();

  return slivers;
}

List<Widget> _buildFeedSectionSlivers({
  required _FeedSection section,
  required bool isLastSection,
  required String? focusKey,
  required GlobalKey focusMatchKey,
  required bool isAdmin,
  required DateTime now,
}) {
  final title = section.showPhaseTitle ? section.title : null;

  return [
    // La clé de focus ne doit jamais être posée sur cet en-tête épinglé :
    // `Scrollable.ensureVisible` ne sait pas viser un en-tête collé et part
    // alors jusqu'en bas de la liste, ce qui laisse la carte visée coupée sous
    // les en-têtes. Elle reste donc toujours sur la carte elle-même.
    if (title != null)
      SliverPersistentHeader(
        pinned: true,
        delegate: _FeedSectionHeaderDelegate(title: title),
      ),
    if (title != null)
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.microGap)),
    if (section.showSeasonTitle)
      SliverToBoxAdapter(
        child: _SeasonDivider(seasonName: section.seasonName),
      ),
    SliverPadding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final entry = section.entries[index];
          final isFocusCard = focusKey != null && _entryKey(entry) == focusKey;
          final isLastCard =
              isLastSection && index == section.entries.length - 1;

          return Padding(
            key: isFocusCard ? focusMatchKey : null,
            padding: EdgeInsets.only(
              bottom: isLastCard ? 0 : AppSpacing.contentGap,
            ),
            child: _buildEntryCard(entry, isAdmin, now),
          );
        }, childCount: section.entries.length),
      ),
    ),
  ];
}

class _SeasonDivider extends StatelessWidget {
  const _SeasonDivider({required this.seasonName});

  final String seasonName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.microGap,
        AppSpacing.screenGutter,
        AppSpacing.contentGap,
      ),
      child: Row(
        children: [
          Expanded(
            child: Divider(color: AppTheme.outline.withValues(alpha: .45)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Saison $seasonName',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
            ),
          ),
          Expanded(
            child: Divider(color: AppTheme.outline.withValues(alpha: .45)),
          ),
        ],
      ),
    );
  }
}

class _FeedSectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _FeedSectionHeaderDelegate({required this.title});

  static const double _height = 38;

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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.outline.withValues(
              alpha: overlapsContent ? .5 : .25,
            ),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w400),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _FeedSectionHeaderDelegate oldDelegate) =>
      oldDelegate.title != title;
}

Widget _buildEntryCard(_FeedEntry entry, bool isAdmin, DateTime now) {
  switch (entry.kind) {
    case _FeedKind.upcomingMatch:
      return _UpcomingMatchCard(match: entry.match!, isAdmin: isAdmin);
    case _FeedKind.nextMatch:
      return _UpcomingMatchCard(match: entry.match!, isAdmin: isAdmin);
    case _FeedKind.liveMatch:
      final match = entry.match!;
      return HomeNextMatchCard(
        match: match,
        isAdmin: isAdmin,
        initialSection: match.isInternal ? 'composition' : 'live',
        showAvailability: now.isBefore(match.kickoffAt),
      );
    case _FeedKind.awaitingValidationMatch:
      final match = entry.match!;
      return HomeNextMatchCard(
        match: match,
        isAdmin: isAdmin,
        initialSection: match.liveState == null
            ? 'info'
            : match.isInternal
                ? 'composition'
                : 'live',
        showAvailability: false,
      );
    case _FeedKind.pastMatch:
      final match = entry.match!;
      return MatchHistoryCard(
        match: match,
        adminActions: isAdmin ? AdminMatchOptionsButton(match: match) : null,
      );
    case _FeedKind.historicalMatch:
      return HistoricalMatchCard(match: entry.historical!);
    case _FeedKind.pastEvent:
    case _FeedKind.event:
      return CalendarFeedEventCard(event: entry.event!, isAdmin: isAdmin);
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
    final now = DateTime.now();
    final availability = ref.watch(myMatchAvailabilityProvider(match.id));
    final serverAvailability = availability.valueOrNull;
    final fallbackOpensAt = matchFeaturesOpenAt(match.kickoffAt);
    final availabilityIsOpen = !match.isCancelled &&
        now.isBefore(match.kickoffAt) &&
        (serverAvailability?.canRespond == true ||
            (serverAvailability == null && !now.isBefore(fallbackOpensAt)));
    final detailsRoute = availabilityIsOpen
        ? '/matches/${match.id}/lineup?section=info'
        : '/matches/${match.id}/lineup?section=info&infoOnly=true';
    final cardSurface = match.isCancelled
        ? CalendarCardPalette.cancelledSurface
        : CalendarCardPalette.matchSurface(match.matchType);
    final cardBorder = match.isCancelled
        ? CalendarCardPalette.cancelledBorder
        : CalendarCardPalette.matchBorder(match.matchType);

    final fixtureRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: match.isInternal
              ? Text(
                  'Match entre nous',
                  textAlign: TextAlign.start,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
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
                        fontWeight: FontWeight.w400,
                      ),
                  foreground: AppTheme.textPrimary,
                  textAlign: TextAlign.start,
                ),
        ),
        if (isAdmin) ...[
          const SizedBox(width: AppSpacing.microGap),
          SizedBox(
            width: 48,
            child: IconTheme(
              data: IconThemeData(color: cardBorder),
              child: AdminMatchOptionsButton(match: match),
            ),
          ),
        ],
        if (match.isCancelled)
          Text(
            'Annulé',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: CalendarCardPalette.cancelledBorder,
                  fontWeight: FontWeight.w400,
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
            foreground: AppTheme.textPrimary,
            secondary: AppTheme.textPrimary,
            dividerColor: cardBorder,
            child: fixtureRow,
          ),
          const SizedBox(height: 7),
          Text(
            match.calendarTypeLabel,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cardBorder,
                  fontWeight: FontWeight.w400,
                ),
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
                    Icon(Icons.place_outlined, size: 16, color: cardBorder),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w400,
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
      color: cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(color: cardBorder, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: match.isCancelled
          ? content
          : InkWell(onTap: () => context.push(detailsRoute), child: content),
    );
  }
}

enum _FeedKind {
  upcomingMatch,
  nextMatch,
  liveMatch,
  awaitingValidationMatch,
  pastMatch,
  historicalMatch,
  pastEvent,
  event,
}

class _FeedEntry {
  const _FeedEntry._({
    required this.kind,
    required this.date,
    this.match,
    this.event,
    this.historical,
  });

  final _FeedKind kind;
  final DateTime date;
  final MatchModel? match;
  final ClubEvent? event;
  final HistoricalMatchResult? historical;

  factory _FeedEntry.match(MatchModel match, _FeedKind kind) =>
      _FeedEntry._(kind: kind, date: match.kickoffAt, match: match);

  factory _FeedEntry.event(ClubEvent event, {required DateTime now}) =>
      _FeedEntry._(
        kind:
            event.startsAt.isAfter(now) ? _FeedKind.event : _FeedKind.pastEvent,
        date: event.startsAt,
        event: event,
      );

  factory _FeedEntry.historical(HistoricalMatchResult historical) =>
      _FeedEntry._(
        kind: _FeedKind.historicalMatch,
        date: historical.date,
        historical: historical,
      );
}

enum _FeedSectionKind { finished, upcoming }

class _FeedSection {
  _FeedSection({
    required this.kind,
    required this.seasonName,
    required this.showPhaseTitle,
    required this.showSeasonTitle,
    required this.entries,
  });

  final _FeedSectionKind kind;
  final String seasonName;
  final bool showPhaseTitle;
  final bool showSeasonTitle;
  final List<_FeedEntry> entries;

  String get title {
    switch (kind) {
      case _FeedSectionKind.finished:
        return 'Terminés';
      case _FeedSectionKind.upcoming:
        return 'À venir';
    }
  }
}

List<_FeedSection> _buildFeedSections(List<_FeedEntry> entries) {
  final sections = <_FeedSection>[];

  for (final entry in entries) {
    final kind = _feedSectionKind(entry.kind);
    final seasonName = _seasonNameFor(entry.date);
    final previous = sections.lastOrNull;
    if (previous == null ||
        previous.kind != kind ||
        previous.seasonName != seasonName) {
      sections.add(
        _FeedSection(
          kind: kind,
          seasonName: seasonName,
          showPhaseTitle: previous == null || previous.kind != kind,
          showSeasonTitle:
              previous == null || previous.seasonName != seasonName,
          entries: [entry],
        ),
      );
      continue;
    }
    previous.entries.add(entry);
  }

  return sections;
}

String _seasonNameFor(DateTime date) {
  final startYear = date.month >= DateTime.july ? date.year : date.year - 1;
  return '$startYear-${startYear + 1}';
}

_FeedSectionKind _feedSectionKind(_FeedKind kind) {
  switch (kind) {
    case _FeedKind.pastMatch:
    case _FeedKind.historicalMatch:
    case _FeedKind.pastEvent:
      return _FeedSectionKind.finished;
    case _FeedKind.upcomingMatch:
    case _FeedKind.nextMatch:
    case _FeedKind.liveMatch:
    case _FeedKind.awaitingValidationMatch:
    case _FeedKind.event:
      return _FeedSectionKind.upcoming;
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: AppSpacing.contentGap),
      child: Center(child: GrintaProgressIndicator()),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.title,
    required this.message,
    this.icon = Icons.sports_soccer_rounded,
    this.tone = GrintaEmptyTone.neutral,
  });

  final String title;
  final String message;
  final IconData icon;
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
