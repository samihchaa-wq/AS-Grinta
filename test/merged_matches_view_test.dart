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
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final matches = [
      for (var i = pastMatches; i >= 1; i--)
        _match('past-$i', now.subtract(Duration(days: 7 * i)), finished: true),
      for (var i = 1; i <= upcomingMatches; i++)
        _match('next-$i', now.add(Duration(days: 7 * i)), finished: false),
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
        child: const MaterialApp(home: Scaffold(body: MergedMatchesView())),
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
}

MatchModel _match(String id, DateTime kickoffAt, {required bool finished}) =>
    MatchModel(
      id: id,
      seasonId: 's1',
      opponentId: 'o-$id',
      kickoffAt: kickoffAt,
      isHome: true,
      plannedDurationMinutes: 90,
      status: finished ? 'termine' : 'a_venir',
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
