import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/sports_management/presentation/match_lineup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Avant J-6, la fiche d'un match n'affiche que l'onglet Info, sauf si un
/// admin a déjà ouvert les disponibilités : les joueurs doivent alors voir
/// Effectif, Compo et Prono dès la demande « Es-tu disponible ? ».
void main() {
  final kickoffAt = DateTime.now().add(const Duration(days: 10));

  testWidgets('dix jours avant, sans ouverture anticipée : Info seul',
      (tester) async {
    await _pump(tester, kickoffAt: kickoffAt, availabilityOpensAt: null);

    expect(find.text('Info'), findsOneWidget);
    expect(find.text('Effectif'), findsNothing);
    expect(find.text('Compo'), findsNothing);
    expect(find.text('Prono'), findsNothing);
  });

  testWidgets('dix jours avant, disponibilités ouvertes : onglets complets',
      (tester) async {
    await _pump(
      tester,
      kickoffAt: kickoffAt,
      availabilityOpensAt: DateTime.now().subtract(const Duration(hours: 1)),
    );

    expect(find.text('Info'), findsOneWidget);
    expect(find.text('Effectif'), findsOneWidget);
    expect(find.text('Compo'), findsOneWidget);
    expect(find.text('Prono'), findsOneWidget);
  });

  testWidgets('dix jours avant, ouverture prévue plus tard : Info seul',
      (tester) async {
    await _pump(
      tester,
      kickoffAt: kickoffAt,
      availabilityOpensAt: DateTime.now().add(const Duration(days: 1)),
    );

    expect(find.text('Info'), findsOneWidget);
    expect(find.text('Effectif'), findsNothing);
  });

  testWidgets(
      'depuis le calendrier, des disponibilités ouvertes : fiche complète',
      (tester) async {
    await _pump(
      tester,
      kickoffAt: kickoffAt,
      availabilityOpensAt: DateTime.now().subtract(const Duration(hours: 1)),
      location: '/matches/match-1/lineup?section=info&infoOnly=true',
    );

    expect(find.text('Effectif'), findsOneWidget);
    expect(find.text('Prono'), findsOneWidget);
  });

  testWidgets('depuis le calendrier, sans ouverture anticipée : fiche réduite',
      (tester) async {
    await _pump(
      tester,
      kickoffAt: kickoffAt,
      availabilityOpensAt: null,
      location: '/matches/match-1/lineup?section=info&infoOnly=true',
    );

    expect(find.text('Effectif'), findsNothing);
    expect(find.text('Prono'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required DateTime kickoffAt,
  required DateTime? availabilityOpensAt,
  String location = '/matches/match-1/lineup?section=info',
}) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/matches/:id/lineup',
        builder: (context, state) => const MatchLineupPage(matchId: 'match-1'),
      ),
    ],
  );
  final info = MatchInfo(
    kickoffAt: kickoffAt,
    address: null,
    lastEncounters: const [],
    matchType: 'amical',
    availabilityOpensAt: availabilityOpensAt,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sportsManagementEnabledProvider.overrideWithValue(true),
        isAdminViewProvider.overrideWithValue(false),
        matchInfoProvider('match-1').overrideWith((ref) async => info),
        matchDetailedInfoProvider('match-1').overrideWith((ref) async => info),
        upcomingMatchFixtureProvider('match-1').overrideWith(
          (ref) async => null,
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
