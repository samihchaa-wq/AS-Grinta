import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_entry_card.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SeasonWrapped _wrapped() => SeasonWrapped.fromJson({
      'season_name': '2026-2027',
      'roster_size': 14,
      'matches_played': 12,
      'matches_played_rank': 4,
      'wins': 7,
      'draws': 2,
      'losses': 3,
      'win_pct': 58.33,
      'win_pct_rank': 2,
      'win_pct_pool': 9,
      'avg_response_hours': 5,
      'avg_response_rank': 1,
      'avg_response_pool': 9,
      'goals': 5,
      'goals_rank': 1,
      'motm': 0,
      'motm_rank': 8,
      'clean_matches': 6,
      'clean_matches_rank': 2,
      'versatility': 3,
      'versatility_rank': 1,
      'top_position': 'Milieu',
    });

Widget _host(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('la carte reste invisible pendant la saison', (tester) async {
    await tester.pumpWidget(
      _host(
        const Scaffold(body: SeasonWrappedEntryCard()),
        [
          seasonWrappedStateProvider.overrideWith(
            (ref) async => const SeasonWrappedState.unavailable(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ma saison'), findsNothing);
  });

  testWidgets('la carte apparaît entre deux saisons', (tester) async {
    await tester.pumpWidget(
      _host(
        const Scaffold(body: SeasonWrappedEntryCard()),
        [
          seasonWrappedStateProvider.overrideWith(
            (ref) async => const SeasonWrappedState(
              available: true,
              seasonName: '2026-2027',
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ma saison'), findsOneWidget);
    expect(find.textContaining('2026-2027'), findsOneWidget);
  });

  testWidgets('le bilan affiche les neuf critères', (tester) async {
    // Un écran haut, pour que la liste construise ses neuf cartes d'un coup.
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        const SeasonWrappedPage(),
        [mySeasonWrappedProvider.overrideWith((ref) async => _wrapped())],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saison 2026-2027'), findsOneWidget);
    expect(find.text('Matchs joués'), findsOneWidget);
    expect(find.text('Poste le plus joué'), findsOneWidget);
    expect(find.text('Polyvalence'), findsOneWidget);

    // Un critère classé montre son rang, un critère non classé n'en a pas.
    expect(find.text('4e sur 14'), findsOneWidget);
    expect(find.text('1er sur 9'), findsOneWidget);
    expect(find.text('7 V · 2 N · 3 D'), findsOneWidget);
  });

  testWidgets('un joueur sans bilan voit un message clair', (tester) async {
    await tester.pumpWidget(
      _host(
        const SeasonWrappedPage(),
        [mySeasonWrappedProvider.overrideWith((ref) async => null)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pas encore de bilan'), findsOneWidget);
  });
}
