import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:as_grinta/features/sports_management/presentation/match_lineup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Un match annulé n'a plus de fiche : une notification envoyée avant le
/// changement (l'ancienne « Match annulé » ouvrait l'onglet Info) mène au
/// calendrier, sur la carte du match qui annonce l'annulation.
void main() {
  for (final isAdmin in [false, true]) {
    testWidgets(
        'la fiche d’un match annulé ouvre le calendrier sur sa carte '
        '(${isAdmin ? 'admin' : 'joueur'})', (tester) async {
      final router = GoRouter(
        initialLocation: '/matches/match-1/lineup?section=info',
        routes: [
          GoRoute(
            path: '/matches',
            builder: (context, state) => Scaffold(
              body: Text('Calendrier ${state.uri.queryParameters['match']}'),
            ),
          ),
          GoRoute(
            path: '/matches/:id/lineup',
            builder: (context, state) =>
                const MatchLineupPage(matchId: 'match-1'),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sportsManagementEnabledProvider.overrideWithValue(true),
            isAdminViewProvider.overrideWithValue(isAdmin),
            matchInfoProvider('match-1').overrideWith(
              (ref) async => MatchInfo(
                kickoffAt: DateTime.now().add(const Duration(days: 2)),
                address: null,
                lastEncounters: const [],
                matchType: 'amical',
                isCancelled: true,
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Calendrier match-1'), findsOneWidget);
      expect(find.byType(MatchLineupPage), findsNothing);
    });
  }
}
