import 'dart:async';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/matches/data/calendar_history_repository.dart';
import 'package:as_grinta/features/matches/data/club_events_repository.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/matches/domain/club_event.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/predictions/presentation/merged_matches_view.dart';
import 'package:as_grinta/features/sports_management/data/sport_motm_vote_repository.dart';
import 'package:as_grinta/features/sports_management/domain/sport_motm_vote.dart';
import 'package:as_grinta/features/sports_management/presentation/match_availability_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Calendrier : ce que voit le joueur à l'ouverture et en faisant défiler.
void main() {
  Future<void> pumpCalendar(
    WidgetTester tester, {
    required int pastMatches,
    required int upcomingMatches,
    String? focusMatchId,
    List<MatchModel> extraMatches = const [],
    // Par défaut le vote du dernier match n'est pas encore clos : il reste en
    // haut, comme pendant la semaine qui suit un match.
    SportMotmVote? Function(String matchId) motmVote = _pendingVote,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final matches = [
      for (var i = pastMatches; i >= 1; i--)
        _match('past-$i', now.subtract(Duration(days: 7 * i)), finished: true),
      for (var i = 1; i <= upcomingMatches; i++)
        _match('next-$i', now.add(Duration(days: 7 * i)), finished: false),
      ...extraMatches,
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => AuthController(_FakeAuthRepository()),
          ),
          matchesControllerProvider.overrideWith(
            (ref) => _StaticMatchesController(ref, matches),
          ),
          isAdminViewProvider.overrideWithValue(false),
          sportsManagementEnabledProvider.overrideWithValue(false),
          clubEventsProvider.overrideWith(
            (ref) => Stream.value(const <ClubEvent>[]),
          ),
          allHistoricalMatchesProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          myMatchAvailabilityProvider.overrideWith((ref, id) async => null),
          calendarFocusMotmVoteProvider
              .overrideWith((ref, id) async => motmVote(id)),
        ],
        child: MaterialApp(
          home: Scaffold(body: MergedMatchesView(focusMatchId: focusMatchId)),
        ),
      ),
    );
    // Le positionnement se fait en plusieurs passes espacées de 60 ms.
    for (var i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> disposeCalendar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Rect headerRect(WidgetTester tester, String title) => tester.getRect(
        find
            .ancestor(of: find.text(title), matching: find.byType(DecoratedBox))
            .first,
      );

  testWidgets(
      'à l’ouverture, le dernier match joué est visible juste sous son '
      'en-tête', (tester) async {
    await pumpCalendar(tester, pastMatches: 12, upcomingMatches: 12);

    final header = headerRect(tester, 'Terminés');
    final card = tester.getRect(find.text('Clubpast1'));
    // Ni caché sous l'en-tête épinglé, ni perdu plus bas dans l'écran.
    expect(card.top, greaterThanOrEqualTo(header.bottom));
    expect(card.top - header.bottom, lessThan(120));

    await disposeCalendar(tester);
  });

  testWidgets(
      'le dernier match reste en haut moins de 24 h après la désignation de '
      'l’Homme du match', (tester) async {
    await pumpCalendar(
      tester,
      pastMatches: 12,
      upcomingMatches: 12,
      motmVote: (id) => _closedVote(
        id,
        DateTime.now().subtract(const Duration(hours: 23)),
      ),
    );

    final header = headerRect(tester, 'Terminés');
    final card = tester.getRect(find.text('Clubpast1'));
    expect(card.top, greaterThanOrEqualTo(header.bottom));
    expect(card.top - header.bottom, lessThan(120));

    await disposeCalendar(tester);
  });

  testWidgets(
      'plus de 24 h après la désignation de l’Homme du match, le prochain '
      'match passe en haut', (tester) async {
    await pumpCalendar(
      tester,
      pastMatches: 12,
      upcomingMatches: 12,
      motmVote: (id) => _closedVote(
        id,
        DateTime.now().subtract(const Duration(hours: 25)),
      ),
    );

    final header = headerRect(tester, 'À venir');
    final card = tester.getRect(find.text('Clubnext1'));
    expect(card.top, greaterThanOrEqualTo(header.bottom));
    expect(card.top - header.bottom, lessThan(120));

    await disposeCalendar(tester);
  });

  testWidgets(
      'sans vote pour le dernier match, le prochain match passe en haut 24 h '
      'après la fin du match', (tester) async {
    await pumpCalendar(
      tester,
      pastMatches: 12,
      upcomingMatches: 12,
      motmVote: (_) => null,
    );

    final header = headerRect(tester, 'À venir');
    final card = tester.getRect(find.text('Clubnext1'));
    expect(card.top, greaterThanOrEqualTo(header.bottom));
    expect(card.top - header.bottom, lessThan(120));

    await disposeCalendar(tester);
  });

  // Dans l'appli, les réglages du club arrivent après les matchs : la gestion
  // sportive paraît d'abord coupée, puis s'allume, et le vote peut être relu
  // pendant que l'écran défile. Rien de tout cela ne doit ramener l'écran sur
  // le dernier match joué.
  for (final reloadVote in [false, true]) {
    testWidgets(
        'vote clos depuis plusieurs jours : le prochain match reste en haut '
        'malgré des chargements tardifs${reloadVote ? ' et une relecture du vote' : ''}',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final matches = [
        for (var i = 6; i >= 1; i--)
          _match(
            'past-$i',
            now.subtract(Duration(days: 7 * i - 2)),
            finished: true,
          ),
        for (var i = 1; i <= 6; i++)
          _match(
            'next-$i',
            now.add(Duration(days: 7 * i - 5)),
            finished: false,
          ),
      ];
      final sportsFlag = StateProvider<bool>((ref) => false);
      late _DelayedMatchesController controller;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => AuthController(_FakeAuthRepository()),
            ),
            matchesControllerProvider.overrideWith(
              (ref) => controller = _DelayedMatchesController(ref),
            ),
            isAdminViewProvider.overrideWithValue(false),
            sportsManagementEnabledProvider.overrideWith(
              (ref) => ref.watch(sportsFlag),
            ),
            clubEventsProvider.overrideWith(
              (ref) => Stream.value(const <ClubEvent>[]),
            ),
            allHistoricalMatchesProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            myMatchAvailabilityProvider.overrideWith((ref, id) async => null),
            sportMotmVoteRepositoryProvider.overrideWithValue(
              _DelayedClosedVoteRepository(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MergedMatchesView()),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MergedMatchesView)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      controller.emit(matches);
      await tester.pump(const Duration(milliseconds: 150));
      container.read(sportsFlag.notifier).state = true;
      if (reloadVote) {
        await tester.pump(const Duration(milliseconds: 250));
        container.invalidate(sportMotmVoteProvider);
      }
      for (var i = 0; i < 30; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final header = headerRect(tester, 'À venir');
      final card = tester.getRect(find.text('Clubnext1'));
      expect(card.top, greaterThanOrEqualTo(header.bottom));
      expect(card.top - header.bottom, lessThan(120));
      expect(find.text('Clubpast1'), findsNothing);

      await disposeCalendar(tester);
    });
  }

  testWidgets(
      'dans les matchs à venir, seul l’en-tête « À venir » reste épinglé',
      (tester) async {
    await pumpCalendar(tester, pastMatches: 6, upcomingMatches: 12);

    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    expect(find.text('Terminés'), findsNothing);
    expect(
      headerRect(tester, 'À venir').top,
      tester.getRect(scrollable).top,
    );

    await disposeCalendar(tester);
  });

  testWidgets(
      'ouvert depuis une notification, le calendrier montre le match '
      'concerné', (tester) async {
    await pumpCalendar(
      tester,
      pastMatches: 12,
      upcomingMatches: 12,
      focusMatchId: 'next-6',
    );

    final header = headerRect(tester, 'À venir');
    final viewport = tester.getRect(find.byType(Scrollable).first);
    final card = tester.getRect(find.text('Clubnext6'));
    // La carte visée est en haut de l'écran, juste sous l'en-tête épinglé,
    // et non le dernier match joué.
    expect(card.top, greaterThanOrEqualTo(header.bottom));
    expect(card.top - header.bottom, lessThan(120));
    expect(card.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(find.text('Clubpast1'), findsNothing);

    await disposeCalendar(tester);
  });

  testWidgets(
      'un match demandé introuvable laisse le calendrier sur le dernier '
      'match joué', (tester) async {
    await pumpCalendar(
      tester,
      pastMatches: 12,
      upcomingMatches: 12,
      focusMatchId: 'match-inconnu',
    );

    final header = headerRect(tester, 'Terminés');
    final card = tester.getRect(find.text('Clubpast1'));
    expect(card.top, greaterThanOrEqualTo(header.bottom));
    expect(card.top - header.bottom, lessThan(120));

    await disposeCalendar(tester);
  });

  testWidgets('une longue saison ne construit pas toutes les cartes d’un coup',
      (tester) async {
    await pumpCalendar(tester, pastMatches: 80, upcomingMatches: 4);

    // Le calendrier s'ouvre près des derniers matchs joués : les plus anciens
    // ne sont construits qu'en y défilant.
    expect(find.text('Clubpast1'), findsOneWidget);
    expect(
      find.text('Clubpast80', skipOffstage: false),
      findsNothing,
    );

    await disposeCalendar(tester);
  });

  testWidgets(
      'un match annulé ne s’ouvre pas et annonce son annulation, avant comme '
      'après sa date', (tester) async {
    final now = DateTime.now();
    await pumpCalendar(
      tester,
      pastMatches: 2,
      upcomingMatches: 2,
      extraMatches: [
        _match(
          'cancelled-past',
          now.subtract(const Duration(days: 2)),
          finished: false,
          cancelled: true,
        ),
        _match(
          'cancelled-next',
          now.add(const Duration(days: 2)),
          finished: false,
          cancelled: true,
        ),
      ],
    );

    final labels = find.text('Match annulé', skipOffstage: false);
    expect(labels, findsNWidgets(2));
    expect(
      find.ancestor(of: labels, matching: find.byType(InkWell)),
      findsNothing,
    );

    await disposeCalendar(tester);
  });

  testWidgets(
      'ouvert depuis la notification « Match annulé », le calendrier montre '
      'le match annulé au milieu des autres', (tester) async {
    await pumpCalendar(
      tester,
      pastMatches: 12,
      upcomingMatches: 12,
      focusMatchId: 'cancelled',
      extraMatches: [
        _match(
          'cancelled',
          DateTime.now().add(const Duration(days: 7 * 6 + 3)),
          finished: false,
          cancelled: true,
        ),
      ],
    );

    final header = headerRect(tester, 'À venir');
    final card = tester.getRect(find.text('Clubcancelled'));
    expect(card.top, greaterThanOrEqualTo(header.bottom));
    expect(card.top - header.bottom, lessThan(120));
    expect(find.text('Match annulé'), findsOneWidget);
    // Les autres matchs restent affichés autour de lui.
    expect(find.text('Clubnext7'), findsOneWidget);

    await disposeCalendar(tester);
  });
}

MatchModel _match(
  String id,
  DateTime kickoffAt, {
  required bool finished,
  bool cancelled = false,
}) =>
    MatchModel(
      id: id,
      seasonId: 's1',
      opponentId: 'o-$id',
      kickoffAt: kickoffAt,
      isHome: true,
      plannedDurationMinutes: 90,
      status: cancelled
          ? 'annule'
          : finished
              ? 'termine'
              : 'a_venir',
      grintaScore: finished ? 2 : null,
      opponentScore: finished ? 1 : null,
      resultValidatedAt:
          finished ? kickoffAt.add(const Duration(hours: 2)) : null,
      // Le calendrier n'affiche que le premier mot du nom de l'adversaire.
      opponentName: 'Club${id.replaceAll('-', '')}',
      seasonName: '2026-2027',
    );

class _StaticMatchesController extends MatchesController {
  _StaticMatchesController(Ref ref, List<MatchModel> matches)
      : super(_UnusedMatchesRepository(), ref) {
    state = MatchesState(matches: matches, isLoading: false);
  }

  @override
  Future<void> load({
    String? seasonId,
    bool allSeasons = false,
    bool forceRefresh = false,
  }) async {}
}

class _UnusedMatchesRepository implements MatchesRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthRepository implements AuthRepository {
  final _events = StreamController<supabase.AuthState>.broadcast();

  @override
  Stream<supabase.AuthState> get authStateChanges => _events.stream;

  @override
  bool get hasSession => false;

  @override
  Future<Never> fetchProfile({bool retryAfterSignIn = false}) =>
      Completer<Never>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SportMotmVote _pendingVote(String matchId) =>
    _vote(matchId, SportMotmVoteState.draft, closedAt: null);

SportMotmVote _closedVote(String matchId, DateTime closedAt) =>
    _vote(matchId, SportMotmVoteState.closed, closedAt: closedAt);

SportMotmVote _vote(
  String matchId,
  SportMotmVoteState state, {
  required DateTime? closedAt,
}) =>
    SportMotmVote(
      matchId: matchId,
      opponentName: 'Club',
      isHome: true,
      scoreAsGrinta: 1,
      scoreAdverse: 0,
      state: state,
      opensAt: closedAt?.subtract(const Duration(hours: 24)),
      closesAt: closedAt,
      closedAt: closedAt,
      finalizationVersion: 1,
      hasVoted: false,
      canVote: false,
      isEligibleVoter: false,
      totalVotes: 0,
      maxVotes: 0,
      candidates: const [],
    );

/// Répond comme le serveur pour un vote clos il y a trois jours, avec le
/// délai d'un vrai appel réseau.
class _DelayedClosedVoteRepository implements SportMotmVoteRepository {
  @override
  Future<SportMotmVote?> fetch(String matchId) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return _closedVote(
      matchId,
      DateTime.now().subtract(const Duration(days: 3)),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Comme dans l'appli : la liste des matchs arrive après le premier affichage.
class _DelayedMatchesController extends MatchesController {
  _DelayedMatchesController(Ref ref) : super(_UnusedMatchesRepository(), ref) {
    state = const MatchesState(isLoading: true);
  }

  void emit(List<MatchModel> matches) =>
      state = MatchesState(matches: matches, isLoading: false);

  @override
  Future<void> load({
    String? seasonId,
    bool allSeasons = false,
    bool forceRefresh = false,
  }) async {}
}
