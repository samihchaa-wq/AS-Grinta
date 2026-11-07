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
    // Ancienneté du dernier match joué. Par défaut il date de la veille et
    // reste donc en haut ; les autres sont espacés d'une semaine.
    Duration lastPlayedAgo = const Duration(days: 1),
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final matches = [
      for (var i = pastMatches; i >= 1; i--)
        _match(
          'past-$i',
          now.subtract(lastPlayedAgo + Duration(days: 7 * (i - 1))),
          finished: true,
        ),
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

  // Le vote Homme du match se ferme 24 h après le coup d'envoi ; le résultat
  // reste ensuite en vue 24 h. Au-delà de 48 h, le prochain match passe en
  // haut.
  testWidgets(
      'le dernier match reste en haut jusqu’à 48 h après son coup d’envoi',
      (tester) async {
    await pumpCalendar(
      tester,
      pastMatches: 12,
      upcomingMatches: 12,
      lastPlayedAgo: const Duration(hours: 47),
    );

    final header = headerRect(tester, 'Terminés');
    final card = tester.getRect(find.text('Clubpast1'));
    expect(card.top, greaterThanOrEqualTo(header.bottom));
    expect(card.top - header.bottom, lessThan(120));

    await disposeCalendar(tester);
  });

  testWidgets(
      'plus de 48 h après le coup d’envoi du dernier match, le prochain '
      'match passe en haut', (tester) async {
    await pumpCalendar(
      tester,
      pastMatches: 12,
      upcomingMatches: 12,
      lastPlayedAgo: const Duration(hours: 49),
    );

    final header = headerRect(tester, 'À venir');
    final card = tester.getRect(find.text('Clubnext1'));
    expect(card.top, greaterThanOrEqualTo(header.bottom));
    expect(card.top - header.bottom, lessThan(120));
    expect(find.text('Clubpast1'), findsNothing);

    await disposeCalendar(tester);
  });

  testWidgets(
      'à l’ouverture, la liste reste masquée jusqu’à être placée sur le bon '
      'match, sans défiler sous les yeux', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final matches = [
      for (var i = 12; i >= 1; i--)
        _match(
          'past-$i',
          now.subtract(Duration(days: 7 * i - 2)),
          finished: true,
        ),
      for (var i = 1; i <= 12; i++)
        _match(
          'next-$i',
          now.add(Duration(days: 7 * i - 5)),
          finished: false,
        ),
    ];
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
          sportsManagementEnabledProvider.overrideWithValue(false),
          clubEventsProvider.overrideWith(
            (ref) => Stream.value(const <ClubEvent>[]),
          ),
          allHistoricalMatchesProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          myMatchAvailabilityProvider.overrideWith((ref, id) async => null),
        ],
        child: const MaterialApp(home: Scaffold(body: MergedMatchesView())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    controller.emit(matches);
    await tester.pump();

    double opacity() =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

    // Les matchs sont là, mais pas encore à la bonne place : rien n'est
    // montré, ni le haut de la liste ni une carte dépassée.
    expect(opacity(), 0);

    for (var i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(opacity(), 1);
    final header = headerRect(tester, 'À venir');
    final card = tester.getRect(find.text('Clubnext1'));
    expect(card.top, greaterThanOrEqualTo(header.bottom));
    expect(card.top - header.bottom, lessThan(120));

    await disposeCalendar(tester);
  });

  // Sur téléphone, l'historique des anciennes saisons (gardé sur
  // l'appareil) arrive avant les matchs de la saison. Pendant tout ce
  // chargement, l'écran ne doit jamais montrer la liste ailleurs que sur le
  // bon match : ni le haut de l'historique, ni une carte dépassée.
  testWidgets(
      'l’historique arrivé avant les matchs ne s’affiche jamais avant que la '
      'liste soit placée sur le bon match', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final matches = [
      for (var i = 8; i >= 1; i--)
        _match(
          'past-$i',
          now.subtract(Duration(days: 7 * i - 2)),
          finished: true,
        ),
      for (var i = 1; i <= 8; i++)
        _match(
          'next-$i',
          now.add(Duration(days: 7 * i - 5)),
          finished: false,
        ),
    ];
    final history = [
      for (var i = 0; i < 30; i++)
        HistoricalMatchResult(
          id: 'old-$i',
          date: DateTime(2014, 4, 1).add(Duration(days: 7 * i)),
          opponentName: 'Ancien$i',
          grintaScore: 1,
          opponentScore: 0,
          isHome: true,
        ),
    ];
    late _DelayedMatchesController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => AuthController(_FakeAuthRepository()),
          ),
          matchesControllerProvider.overrideWith(
            (ref) => controller = _DelayedMatchesController(
              ref,
              initiallyLoading: false,
            ),
          ),
          isAdminViewProvider.overrideWithValue(false),
          sportsManagementEnabledProvider.overrideWithValue(false),
          clubEventsProvider.overrideWith(
            (ref) => Stream.value(const <ClubEvent>[]),
          ),
          allHistoricalMatchesProvider.overrideWith(
            (ref) => Stream.value(history),
          ),
          myMatchAvailabilityProvider.overrideWith((ref, id) async => null),
        ],
        child: const MaterialApp(home: Scaffold(body: MergedMatchesView())),
      ),
    );

    double opacity() =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
    void expectHiddenOrOnNextMatch(String moment) {
      if (opacity() == 0) return;
      final next = find.text('Clubnext1');
      expect(next, findsOneWidget, reason: 'liste visible ailleurs ($moment)');
      final header = headerRect(tester, 'À venir');
      final card = tester.getRect(next);
      expect(
        card.top - header.bottom,
        inInclusiveRange(0, 120),
        reason: 'liste visible avant d’être placée ($moment)',
      );
    }

    // L'historique est là, les matchs pas encore.
    for (var i = 0; i < 5; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
      expectHiddenOrOnNextMatch('historique seul, passe $i');
    }
    controller.emit(matches);
    for (var i = 0; i < 40; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      expectHiddenOrOnNextMatch('après les matchs, passe $i');
    }
    expect(opacity(), 1);

    await disposeCalendar(tester);
  });

  testWidgets('un historique complété après l’affichage ne décale pas la liste',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final matches = [
      for (var i = 8; i >= 1; i--)
        _match(
          'past-$i',
          now.subtract(Duration(days: 7 * i - 2)),
          finished: true,
        ),
      for (var i = 1; i <= 8; i++)
        _match(
          'next-$i',
          now.add(Duration(days: 7 * i - 5)),
          finished: false,
        ),
    ];
    List<HistoricalMatchResult> history(int count) => [
          for (var i = 0; i < count; i++)
            HistoricalMatchResult(
              id: 'old-$i',
              date: DateTime(2014, 4, 1).add(Duration(days: 7 * i)),
              opponentName: 'Ancien$i',
              grintaScore: 1,
              opponentScore: 0,
              isHome: true,
            ),
        ];
    final historyStream = StreamController<List<HistoricalMatchResult>>();
    addTearDown(historyStream.close);
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
            (ref) => historyStream.stream,
          ),
          myMatchAvailabilityProvider.overrideWith((ref, id) async => null),
        ],
        child: const MaterialApp(home: Scaffold(body: MergedMatchesView())),
      ),
    );
    // Copie locale de l'historique, puis version complète du serveur.
    historyStream.add(history(5));
    for (var i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    historyStream.add(history(40));
    for (var i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final header = headerRect(tester, 'À venir');
    final card = tester.getRect(find.text('Clubnext1'));
    expect(card.top - header.bottom, inInclusiveRange(0, 120));

    await disposeCalendar(tester);
  });

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

/// Comme dans l'appli : la liste des matchs arrive après le premier affichage.
class _DelayedMatchesController extends MatchesController {
  _DelayedMatchesController(Ref ref, {bool initiallyLoading = true})
      : super(_UnusedMatchesRepository(), ref) {
    state = MatchesState(isLoading: initiallyLoading);
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
