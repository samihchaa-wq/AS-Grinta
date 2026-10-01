import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/match_live/data/match_live_repository.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_tab.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/sports_management/presentation/match_lineup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// À partir de T-15, le Live occupe toute la fiche du match : ni encadré du
/// match ni onglets, pour les joueurs comme pour les coachs.
void main() {
  for (final coach in [false, true]) {
    final who = coach ? 'coach' : 'joueur';

    testWidgets('$who, T-15 : seulement le Live', (tester) async {
      await _pump(
        tester,
        kickoffAt: DateTime.now().add(const Duration(minutes: 10)),
        coach: coach,
      );

      expect(find.byType(MatchLiveTab), findsOneWidget);
      expect(find.byType(UpcomingMatchFixtureHeader), findsNothing);
      expect(find.text('Info'), findsNothing);
      expect(find.text('Effectif'), findsNothing);
      expect(find.text('Compo'), findsNothing);
      expect(find.text('Piloter'), coach ? findsOneWidget : findsNothing);
    });

    testWidgets('$who, la veille : onglets habituels', (tester) async {
      await _pump(
        tester,
        kickoffAt: DateTime.now().add(const Duration(hours: 20)),
        coach: coach,
      );

      expect(find.text('Info'), findsOneWidget);
      expect(find.byType(MatchLiveTab), findsNothing);
    });
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required DateTime kickoffAt,
  required bool coach,
}) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/matches/match-1/lineup?section=live',
    routes: [
      GoRoute(
        path: '/matches/:id/lineup',
        builder: (context, state) => const MatchLineupPage(matchId: 'match-1'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sportsManagementEnabledProvider.overrideWithValue(true),
        isAdminViewProvider.overrideWithValue(false),
        matchInfoProvider('match-1').overrideWith(
          (ref) async => MatchInfo(
            kickoffAt: kickoffAt,
            address: null,
            lastEncounters: const [],
            matchType: 'amical',
          ),
        ),
        upcomingMatchFixtureProvider('match-1').overrideWith(
          (ref) async => null,
        ),
        isMatchCoachOrAdminProvider.overrideWith((ref, id) async => coach),
        matchLiveRepositoryProvider.overrideWithValue(_StubRepository()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _StubRepository implements MatchLiveRepository {
  final _bundle = MatchLiveStateBundle.fromRpc(const {
    'match_id': 'match-1',
    'session_exists': false,
    'state': null,
  });

  @override
  Future<MatchLiveStateBundle> fetchLiveState(String matchId) async => _bundle;

  @override
  Stream<void> watchChanges(String matchId) => const Stream<void>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<MatchLiveStateBundle>.value(_bundle);
}
