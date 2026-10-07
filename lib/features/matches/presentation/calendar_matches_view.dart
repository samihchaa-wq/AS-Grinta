import 'dart:async';
import 'dart:math' as math;

import 'package:as_grinta/app/shell/module_navigation.dart';
import 'package:as_grinta/core/config/app_config.dart';
import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/calendar_card_palette.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/core/widgets/calendar_scoreline.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/match_live/data/match_live_notification_repository.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_notification_bell.dart';
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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

part 'calendar_matches_widgets.dart';

enum _CalendarDisplayMode { scroll, month }

class CalendarMatchesView extends ConsumerStatefulWidget {
  const CalendarMatchesView({super.key, this.focusMatchId});

  /// Match sur lequel ouvrir le défilé, sinon le dernier match joué.
  final String? focusMatchId;

  @override
  ConsumerState<CalendarMatchesView> createState() =>
      _CalendarMatchesViewState();
}

class _CalendarMatchesViewState extends ConsumerState<CalendarMatchesView> {
  _CalendarDisplayMode _displayMode = _CalendarDisplayMode.scroll;
  DateTime _monthCursor = DateTime(DateTime.now().year, DateTime.now().month);
  final Map<String, Future<List<HistoricalMatchResult>>> _historyLoads = {};
  bool _subscribing = false;

  @override
  void didUpdateWidget(covariant CalendarMatchesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Un match demandé (notification de disponibilité) se montre dans le
    // défilé, où se trouve son sélecteur de présence.
    if (widget.focusMatchId != null &&
        widget.focusMatchId != oldWidget.focusMatchId &&
        _displayMode != _CalendarDisplayMode.scroll) {
      setState(() => _displayMode = _CalendarDisplayMode.scroll);
    }
  }

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

  /// Copie le lien ; un presse-papiers refusé ne doit jamais empêcher la
  /// suite (ouverture de l'abonnement, message).
  Future<bool> _copyCalendarLink(Uri uri) async {
    try {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Lance [uri] tout de suite, sans rien attendre avant : appelé après un
  /// await, Safari sur iPhone ne voyait plus le geste de l'utilisateur et
  /// bloquait l'ouverture sans aucune erreur. Sur le web, [webWindowName]
  /// « _self » ouvre le lien dans la page en cours plutôt que dans une
  /// nouvelle fenêtre, que l'iPhone peut aussi bloquer en silence.
  void _launchNow(Uri uri, {String? webWindowName}) {
    final launch = kIsWeb
        ? launchUrl(uri, webOnlyWindowName: webWindowName)
        : launchUrl(uri, mode: LaunchMode.externalApplication);
    unawaited(launch.catchError((Object _) => false));
  }

  Uri _subscribePageUri(Uri httpsUri) {
    final base = AppConfig.publicAppUrl.endsWith('/')
        ? AppConfig.publicAppUrl
        : '${AppConfig.publicAppUrl}/';
    return Uri.parse(
      '${base}abonnement-calendrier.html'
      '#feed=${Uri.encodeComponent(httpsUri.toString())}',
    );
  }

  Future<void> _openAppleCalendar(Uri httpsUri) async {
    // Le lien webcal ouvre l'abonnement ; le https, collé dans Safari,
    // proposait « Ajouter tous les événements », une copie unique qui ne se
    // met jamais à jour.
    final webcalUri = httpsUri.replace(scheme: 'webcal');
    _launchNow(webcalUri, webWindowName: '_self');
    final copied = await _copyCalendarLink(webcalUri);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(
          copied
              ? 'Apple Calendrier ne propose pas « S’abonner » ? Ouvre la page d’abonnement, ou colle le lien copié dans Calendrier > Calendriers > Ajouter > Ajouter un calendrier avec abonnement.'
              : 'Apple Calendrier ne propose pas « S’abonner » ? Ouvre la page d’abonnement.',
        ),
        action: SnackBarAction(
          label: 'Ouvrir',
          onPressed: () =>
              _launchNow(_subscribePageUri(httpsUri), webWindowName: '_self'),
        ),
      ),
    );
  }

  Future<void> _useGoogleCalendar(Uri httpsUri) async {
    final copied = await _copyCalendarLink(httpsUri);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          copied
              ? 'Lien copié. L’appli Google Agenda ne permet pas l’abonnement : ouvre calendar.google.com dans un navigateur (sur téléphone, en version ordinateur), puis Autres agendas > + > À partir de l’URL.'
              : 'Copie impossible. Ouvre la page d’abonnement pour copier le lien, puis ajoute-le dans Google Agenda en version web : Autres agendas > + > À partir de l’URL.',
        ),
        action: copied
            ? null
            : SnackBarAction(
                label: 'Ouvrir',
                onPressed: () => _launchNow(
                  _subscribePageUri(httpsUri),
                  webWindowName: '_self',
                ),
              ),
      ),
    );
  }

  Future<void> _useOutlookCalendar(Uri httpsUri) async {
    _launchNow(Uri.parse('https://outlook.live.com/calendar/0/view/month'));
    final copied = await _copyCalendarLink(httpsUri);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          copied
              ? 'Lien copié. Dans Outlook : Ajouter un calendrier > S’abonner à partir du web, puis colle le lien.'
              : 'Copie impossible. Dans Outlook : Ajouter un calendrier > S’abonner à partir du web, avec le lien de la page d’abonnement.',
        ),
      ),
    );
  }

  Future<void> _showCalendarSubscriptionChoices(Uri httpsUri) async {
    await showModalBottomSheet<void>(
      context: context,
      // Au-dessus de la barre de navigation du bas, sinon elle masque la fin
      // de la liste.
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        Future<void> choose(Future<void> Function() action) async {
          Navigator.of(sheetContext).pop();
          await action();
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'S’abonner au calendrier',
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w400),
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
                    'Android : abonnement à faire sur Google Agenda en version web',
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
                    final copied = await _copyCalendarLink(httpsUri);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          copied
                              ? 'Lien du calendrier copié.'
                              : 'Copie impossible sur cet appareil.',
                        ),
                      ),
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
    // Plusieurs appuis pendant le chargement empilaient autant de fenêtres
    // de choix identiques.
    if (_subscribing) return;
    _subscribing = true;
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
    } finally {
      _subscribing = false;
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
                      MergedMatchesView(focusMatchId: widget.focusMatchId),
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
