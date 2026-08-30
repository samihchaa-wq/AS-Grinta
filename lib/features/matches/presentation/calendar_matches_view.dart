import 'dart:math' as math;

import 'package:as_grinta/app/shell/module_navigation.dart';
import 'package:as_grinta/core/config/app_config.dart';
import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/calendar_card_palette.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/core/widgets/match_date_column.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/data/calendar_history_repository.dart';
import 'package:as_grinta/features/matches/data/club_events_repository.dart';
import 'package:as_grinta/features/matches/domain/club_event.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/calendar_entry_form_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/matches/presentation/widgets/admin_match_options_button.dart';
import 'package:as_grinta/features/matches/presentation/widgets/historical_match_card.dart';
import 'package:as_grinta/features/predictions/presentation/merged_matches_view.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/match_history_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

part 'calendar_matches_widgets.dart';

enum _CalendarDisplayMode { scroll, month }

class CalendarMatchesView extends ConsumerStatefulWidget {
  const CalendarMatchesView({super.key});

  @override
  ConsumerState<CalendarMatchesView> createState() =>
      _CalendarMatchesViewState();
}

class _CalendarMatchesViewState extends ConsumerState<CalendarMatchesView> {
  _CalendarDisplayMode _displayMode = _CalendarDisplayMode.scroll;
  DateTime _monthCursor = DateTime(DateTime.now().year, DateTime.now().month);
  final Map<String, Future<List<HistoricalMatchResult>>> _historyLoads = {};

  Future<List<HistoricalMatchResult>> _historyForSeason(String seasonName) {
    return _historyLoads.putIfAbsent(
      seasonName,
      () => ref.read(calendarHistoryRepositoryProvider).fetchSeason(seasonName),
    );
  }

  Future<void> _refreshHistory(String seasonName) async {
    setState(() {
      _historyLoads[seasonName] =
          ref.read(calendarHistoryRepositoryProvider).fetchSeason(seasonName);
    });
    ref.invalidate(clubEventsProvider);
    await _historyLoads[seasonName];
  }

  Future<void> _refreshModernMatches() async {
    final state = ref.read(matchesControllerProvider);
    ref.invalidate(clubEventsProvider);
    await ref
        .read(matchesControllerProvider.notifier)
        .load(seasonId: state.selectedSeasonId, allSeasons: true);
  }

  Future<void> _openCreate() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CalendarEntryFormPage()),
    );
    if (!mounted || changed != true) return;
    await _refreshModernMatches();
  }

  Future<void> _copyCalendarLink(Uri httpsUri) async {
    await Clipboard.setData(ClipboardData(text: httpsUri.toString()));
  }

  Future<void> _openAppleCalendar(Uri httpsUri) async {
    await _copyCalendarLink(httpsUri);
    final webcalUri = httpsUri.replace(scheme: 'webcal');
    try {
      await launchUrl(webcalUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Some iOS/PWA combinations report a handled URL without displaying the
      // subscription screen. The HTTPS feed is already copied as a reliable
      // manual fallback.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 8),
        content: Text(
          'Si Apple Calendrier ne propose pas l’abonnement, le lien est copié : Calendrier > Calendriers > Ajouter > Ajouter un calendrier avec abonnement.',
        ),
      ),
    );
  }

  Future<void> _useGoogleCalendar(Uri httpsUri) async {
    await _copyCalendarLink(httpsUri);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 8),
        content: Text(
          'Lien copié. Google Agenda permet l’abonnement par URL depuis un navigateur sur ordinateur : Autres agendas > + > À partir de l’URL.',
        ),
      ),
    );
  }

  Future<void> _useOutlookCalendar(Uri httpsUri) async {
    await _copyCalendarLink(httpsUri);
    try {
      await launchUrl(
        Uri.parse('https://outlook.live.com/calendar/0/view/month'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // The copied URL is sufficient if Outlook cannot be opened directly.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 8),
        content: Text(
          'Lien copié. Dans Outlook : Ajouter un calendrier > S’abonner à partir du web, puis colle le lien.',
        ),
      ),
    );
  }

  Future<void> _showCalendarSubscriptionChoices(Uri httpsUri) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        Future<void> choose(Future<void> Function() action) async {
          Navigator.of(sheetContext).pop();
          await action();
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'S’abonner au calendrier',
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choisis ton calendrier. Il restera lié à AS Grinta : les ajouts, changements, annulations et suppressions de matchs seront récupérés lors de la prochaine synchronisation du service choisi.',
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.calendar_month_rounded),
                  title: const Text('Apple Calendrier'),
                  subtitle: const Text('iPhone, iPad et Mac'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => choose(() => _openAppleCalendar(httpsUri)),
                ),
                ListTile(
                  leading: const Icon(Icons.event_rounded),
                  title: const Text('Google Agenda'),
                  subtitle: const Text(
                    'Abonnement par URL à faire dans Google Agenda sur ordinateur',
                  ),
                  trailing: const Icon(Icons.content_copy_rounded),
                  onTap: () => choose(() => _useGoogleCalendar(httpsUri)),
                ),
                ListTile(
                  leading: const Icon(Icons.mail_outline_rounded),
                  title: const Text('Outlook'),
                  subtitle: const Text('Outlook.com ou Outlook sur le web'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => choose(() => _useOutlookCalendar(httpsUri)),
                ),
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('Copier le lien du calendrier'),
                  subtitle: const Text(
                    'Pour toute autre application compatible ICS',
                  ),
                  trailing: const Icon(Icons.content_copy_rounded),
                  onTap: () => choose(() async {
                    await _copyCalendarLink(httpsUri);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Lien du calendrier copié.')),
                    );
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _subscribeCurrentSeason() async {
    try {
      final client = ref.read(supabaseClientProvider);
      final rawToken = await client.rpc(
        'get_or_create_calendar_subscription_token',
      );
      final token = rawToken?.toString().trim() ?? '';
      if (token.isEmpty) {
        throw StateError('Le lien d’abonnement n’a pas pu être créé.');
      }

      final httpsUri = Uri.parse(
        '${AppConfig.supabaseUrl}/functions/v1/calendar-feed',
      ).replace(queryParameters: {'token': token});

      if (!mounted) return;
      await _showCalendarSubscriptionChoices(httpsUri);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
    }
  }

  void _selectSeason(String? seasonName, List<Map<String, dynamic>> seasons) {
    if (seasonName == null) return;
    final season = seasons.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['name']?.toString() == seasonName,
          orElse: () => null,
        );
    if (season == null) return;
    setState(() => _monthCursor = _initialMonthForSeason(season));
  }

  void _moveMonth(int delta, List<Map<String, dynamic>> seasons) {
    if (seasons.isEmpty) return;
    final candidate = DateTime(_monthCursor.year, _monthCursor.month + delta);
    final bounds = _monthBounds(seasons);
    if (bounds == null ||
        candidate.isBefore(bounds.$1) ||
        candidate.isAfter(bounds.$2)) {
      return;
    }
    setState(() => _monthCursor = candidate);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(matchesFocusRequestProvider, (previous, next) {
      if (_displayMode != _CalendarDisplayMode.month) return;
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month);
      if (_monthCursor == currentMonth) return;
      setState(() => _monthCursor = currentMonth);
    });

    final state = ref.watch(matchesControllerProvider);
    final isAdmin = ref.watch(isAdminViewProvider);
    final events =
        ref.watch(clubEventsProvider).valueOrNull ?? const <ClubEvent>[];
    final seasons = [...state.seasons]
      ..sort((a, b) => b['name'].toString().compareTo(a['name'].toString()));
    final currentSeason = seasons.cast<Map<String, dynamic>?>().firstWhere(
          (season) => season?['status']?.toString() == 'open',
          orElse: () => null,
        );
    final currentSeasonName = currentSeason?['name']?.toString();
    final selectedSeason =
        _seasonForMonth(seasons, _monthCursor) ?? currentSeason;
    final selectedSeasonName = selectedSeason?['name']?.toString();
    final selectedSeasonId = selectedSeason?['id']?.toString();
    final bounds = _monthBounds(seasons);
    final canGoPrevious = bounds != null && _monthCursor.isAfter(bounds.$1);
    final canGoNext = bounds != null && _monthCursor.isBefore(bounds.$2);

    final exportAction =
        currentSeasonName != null ? _subscribeCurrentSeason : null;

    return Column(
      children: [
        _CalendarToolbar(
          displayMode: _displayMode,
          onDisplayModeChanged: (mode) {
            if (mode == _displayMode) return;
            setState(() => _displayMode = mode);
            if (mode == _CalendarDisplayMode.scroll) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                ref.read(matchesFocusRequestProvider.notifier).state++;
              });
            }
          },
          onExport: exportAction,
          onCreate: isAdmin ? _openCreate : null,
          seasons: seasons,
          selectedSeasonName: selectedSeasonName,
          currentSeasonName: currentSeasonName,
          monthCursor: _monthCursor,
          canGoPrevious: canGoPrevious,
          canGoNext: canGoNext,
          onSeasonChanged: (value) => _selectSeason(value, seasons),
          onPreviousMonth: () => _moveMonth(-1, seasons),
          onNextMonth: () => _moveMonth(1, seasons),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = math.min(constraints.maxWidth, 1120.0);
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: contentWidth,
                  height: constraints.maxHeight,
                  child: IndexedStack(
                    index: _displayMode == _CalendarDisplayMode.scroll ? 0 : 1,
                    children: [
                      const MergedMatchesView(),
                      _buildMonthView(
                        state: state,
                        selectedSeason: selectedSeason,
                        selectedSeasonName: selectedSeasonName,
                        selectedSeasonId: selectedSeasonId,
                        events: events,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMonthView({
    required MatchesState state,
    required Map<String, dynamic>? selectedSeason,
    required String? selectedSeasonName,
    required String? selectedSeasonId,
    required List<ClubEvent> events,
  }) {
    if (state.isLoading && state.seasons.isEmpty) {
      return const Center(child: GrintaProgressIndicator());
    }
    if (state.error != null && state.seasons.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        children: [
          GrintaEmptyState(
            icon: Icons.wifi_off_rounded,
            title: 'Calendrier indisponible',
            message: state.error!,
            tone: GrintaEmptyTone.alert,
          ),
        ],
      );
    }
    if (selectedSeason == null ||
        selectedSeasonName == null ||
        selectedSeasonId == null) {
      return const _MonthEmptyState(
        title: 'Aucune saison disponible',
        message: 'Les saisons apparaîtront ici dès qu’elles seront créées.',
      );
    }

    final modernMatches = state.matches
        .where((match) => match.seasonId == selectedSeasonId)
        .toList(growable: false);
    final seasonEvents = events
        .where((event) => event.seasonId == selectedSeasonId)
        .toList(growable: false);
    final isOpenSeason = selectedSeason['status']?.toString() == 'open';
    final usesModernMatches = isOpenSeason || modernMatches.isNotEmpty;

    if (usesModernMatches) {
      return _ModernMonthView(
        month: _monthCursor,
        matches: modernMatches,
        events: seasonEvents,
        onRefresh: _refreshModernMatches,
      );
    }

    return _HistoricalMonthView(
      month: _monthCursor,
      seasonName: selectedSeasonName,
      future: _historyForSeason(selectedSeasonName),
      events: seasonEvents,
      onRefresh: () => _refreshHistory(selectedSeasonName),
    );
  }
}
