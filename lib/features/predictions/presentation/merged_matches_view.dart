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
import 'package:as_grinta/features/matches/data/calendar_history_repository.dart';
import 'package:as_grinta/features/matches/data/club_events_repository.dart';
import 'package:as_grinta/features/matches/domain/club_event.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/calendar_matches_view.dart'
    show ClubEventCard;
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/matches/presentation/widgets/admin_match_options_button.dart';
import 'package:as_grinta/features/matches/presentation/widgets/historical_match_card.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/match_history_card.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Contenu de l'onglet Matchs.
///
/// Règle stricte : un unique flux chronologique, sans regroupement par
/// catégorie. Chaque carte a au-dessus d'elle une carte moins avancée dans
/// le temps et en dessous une carte plus avancée dans le temps — matchs
/// passés, en direct, à venir et événements confondus, du plus ancien (haut)
/// au plus futur (bas). Le statut d'un match (Live, à valider, dans la
/// fenêtre J-6…) continue de piloter ses fonctionnalités et son habillage de
/// carte, seule la section/en-tête dédiée a disparu.
class MergedMatchesView extends ConsumerStatefulWidget {
  const MergedMatchesView({super.key});

  @override
  ConsumerState<MergedMatchesView> createState() => _MergedMatchesViewState();
}

class _MergedMatchesViewState extends ConsumerState<MergedMatchesView> {
  final GlobalKey _focusMatchKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  String? _lastFocusSignature;
  bool _userScrollInterrupted = false;

  bool _handleScrollNotification(ScrollNotification notification) {
    // On abandonne toute campagne d'auto-focus dès que l'utilisateur
    // touche le scroll : ne pas lui arracher la position sous les doigts.
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrollInterrupted = true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(matchesControllerProvider.notifier).load(allSeasons: true),
    );
  }

  @override
  void dispose() {
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
    // Nouvelle campagne de re-focus : la précédente rétention de scroll
    // manuel ne compte plus (l'utilisateur revient sur l'onglet).
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

    // La SliverList construit ses cartes paresseusement. Si la carte cible
    // est très loin dans la liste (index ~340/350), elle n'est jamais dans
    // le cache tant qu'on n'a pas scrollé jusque-là — et sans son
    // BuildContext, Scrollable.ensureVisible ne peut rien faire. On force
    // donc d'abord un jumpTo vers une position estimée (fraction de la
    // hauteur totale de scroll), ce qui déclenche la construction des
    // cartes autour de cette position, puis on affine avec ensureVisible.
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

    // Affinage : jusqu'à ce que la disposition converge (le jumpTo
    // ci-dessus a une précision limitée quand les cartes ont des tailles
    // très variables — carte de composition Live vs simple ligne d'archive).
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

    final upcomingEvents = events
        .where((event) => event.startsAt.isAfter(now))
        .toList(growable: false);

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
    entries.addAll(upcomingEvents.map(_FeedEntry.event));
    entries.addAll(historicalMatches.map(_FeedEntry.historical));

    // Règle stricte : un seul tri chronologique croissant pour tout le flux.
    // Le plus ancien (passé) en haut, le plus futur en bas — aucune carte
    // n'est promue ou reléguée en dehors de sa place chronologique.
    entries.sort((a, b) => a.date.compareTo(b.date));

    // Choix de la carte sur laquelle le calendrier s'aligne à l'ouverture :
    //   1. la carte prioritaire (Live > à valider > J-6) si elle existe ;
    //   2. sinon, le premier élément chronologiquement à venir — le vrai
    //      « prochain match » du point de vue de l'utilisateur, même quand
    //      il est hors fenêtre J-6, pour éviter d'ouvrir sur 2014 ;
    //   3. sinon (tout est passé), la dernière carte.
    int? focusIndex;
    const priorityKinds = [
      _FeedKind.liveMatch,
      _FeedKind.awaitingValidationMatch,
      _FeedKind.nextMatch,
    ];
    for (final kind in priorityKinds) {
      for (var i = 0; i < entries.length; i += 1) {
        if (entries[i].kind == kind) {
          focusIndex = i;
          break;
        }
      }
      if (focusIndex != null) break;
    }
    if (focusIndex == null) {
      for (var i = 0; i < entries.length; i += 1) {
        if (!entries[i].date.isBefore(now)) {
          focusIndex = i;
          break;
        }
      }
    }
    if (focusIndex == null && entries.isNotEmpty) {
      focusIndex = entries.length - 1;
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

    // Cache large : les cartes hors viewport restent construites afin que le
    // GlobalKey de la carte cible soit toujours joignable pour l'auto-focus,
    // même quand on part de scroll = 0 et que la cible est loin en bas.
    final cacheExtent = 1000.0 + (entries.length * 360.0);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: CustomScrollView(
          controller: _scrollController,
          cacheExtent: cacheExtent,
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
                    ],
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
                    final entry = entries[index];
                    final isFocusCard =
                        focusKey != null && _entryKey(entry) == focusKey;
                    return Padding(
                      key: isFocusCard ? _focusMatchKey : null,
                      padding: EdgeInsets.only(
                        bottom: index == entries.length - 1
                            ? 0
                            : AppSpacing.contentGap,
                      ),
                      child: _buildEntryCard(entry, isAdmin, now),
                    );
                  }, childCount: entries.length),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}

/// Identifiant stable d'une entrée du flux, indépendant de sa position dans
/// la liste : sert d'ancre à l'auto-scroll pour rouvrir le calendrier
/// toujours sur la même carte (le prochain match chronologique par défaut),
/// que d'autres entrées soient ajoutées ou retirées entre deux builds.
String _entryKey(_FeedEntry entry) {
  if (entry.match != null) return 'match:${entry.match!.id}';
  if (entry.event != null) return 'event:${entry.event!.id}';
  if (entry.historical != null) return 'historical:${entry.historical!.id}';
  return 'unknown';
}

/// Choisit la carte adaptée au statut de l'entrée, sans plus jamais dépendre
/// d'une section : la fonctionnalité (disponibilité, Live, composition…)
/// reste pilotée par `entry.kind`, seul l'habillage groupé a disparu.
Widget _buildEntryCard(_FeedEntry entry, bool isAdmin, DateTime now) {
  switch (entry.kind) {
    case _FeedKind.upcomingMatch:
      return _UpcomingMatchCard(match: entry.match!, isAdmin: isAdmin);
    case _FeedKind.nextMatch:
      return HomeNextMatchCard(match: entry.match!, isAdmin: isAdmin);
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
    case _FeedKind.event:
      return ClubEventCard(event: entry.event!, isAdmin: isAdmin);
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

/// Le statut affiché d'une entrée du flux — pilote uniquement le choix de
/// carte et ses fonctionnalités, plus jamais son placement (déterminé
/// exclusivement par `_FeedEntry.date`).
enum _FeedKind {
  upcomingMatch,
  nextMatch,
  liveMatch,
  awaitingValidationMatch,
  pastMatch,
  historicalMatch,
  event,
}

/// Une entrée du flux chronologique unique : match (live ou importé de
/// l'historique du club) ou événement, toutes comparables par `date` pour
/// respecter la règle stricte de tri.
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

  factory _FeedEntry.event(ClubEvent event) =>
      _FeedEntry._(kind: _FeedKind.event, date: event.startsAt, event: event);

  factory _FeedEntry.historical(HistoricalMatchResult historical) =>
      _FeedEntry._(
        kind: _FeedKind.historicalMatch,
        date: historical.date,
        historical: historical,
      );
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
