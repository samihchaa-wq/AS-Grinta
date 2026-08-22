import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_button.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_page.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_share_sheet.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  testWidgets('le bouton reste invisible pendant la saison', (tester) async {
    await tester.pumpWidget(
      _host(
        const Scaffold(body: SeasonWrappedButton()),
        [
          seasonWrappedStateProvider.overrideWith(
            (ref) async => const SeasonWrappedState.unavailable(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('season-wrapped-button')), findsNothing);
  });

  testWidgets('le bouton apparaît entre deux saisons', (tester) async {
    await tester.pumpWidget(
      _host(
        const Scaffold(body: SeasonWrappedButton()),
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

    expect(find.byKey(const ValueKey('season-wrapped-button')), findsOneWidget);
  });

  testWidgets('le bilan tient en trois feuilles partageables', (tester) async {
    // Un écran haut, pour que la liste construise ses trois feuilles d'un coup.
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
    expect(find.text('Ma présence'), findsOneWidget);
    expect(find.text('Mes résultats'), findsOneWidget);
    expect(find.text('Mon apport'), findsOneWidget);
    expect(find.text('Partager'), findsNWidgets(3));
  });

  testWidgets('le rang s’affiche seul, sans effectif', (tester) async {
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

    expect(find.text('4e'), findsOneWidget);
    expect(find.textContaining('4e sur'), findsNothing);
    // Un critère qui ne se classe pas n'affiche aucun rang.
    expect(find.text('7 V · 2 N · 3 D'), findsOneWidget);
  });

  testWidgets('la feuille partagée porte le nom du joueur', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SeasonWrappedShareSheet(
          sheet: _wrapped().sheets.first,
          seasonName: '2026-2027',
          playerName: 'Samih',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AS GRINTA'), findsOneWidget);
    expect(find.text('Saison 2026-2027'), findsOneWidget);
    expect(find.text('Ma présence'), findsOneWidget);
    expect(find.text('Samih'), findsOneWidget);
  });

  testWidgets('la feuille se transforme en une vraie image', (tester) async {
    final captureKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        // Centrée, la feuille garde sa taille propre — comme dans l'écran,
        // où elle est posée hors champ sans contrainte d'étirement.
        home: Center(
          child: RepaintBoundary(
            key: captureKey,
            child: SeasonWrappedShareSheet(
              sheet: _wrapped().sheets.first,
              seasonName: '2026-2027',
              playerName: 'Samih',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;

    // L'encodage PNG est un vrai travail asynchrone : il doit sortir du temps
    // simulé du test, sinon il ne se termine jamais.
    await tester.runAsync(() async {
      final image = await boundary.toImage(
        pixelRatio: kSeasonWrappedSharePixelRatio,
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

      expect(image.width, (kSeasonWrappedShareWidth * 3).round());
      expect(image.height, (kSeasonWrappedShareHeight * 3).round());
      expect(bytes, isNotNull);
      expect(bytes!.lengthInBytes, greaterThan(0));
      image.dispose();
    });
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
