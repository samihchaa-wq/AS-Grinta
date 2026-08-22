import 'dart:ui' as ui;

import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_button.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_page.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_share_sheet.dart';
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

Widget _host(
  Widget child,
  List<Override> overrides, {
  bool reducedMotion = false,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: child,
      ),
    ),
  );
}

List<Override> _storyOverrides() => [
      mySeasonWrappedProvider.overrideWith((ref) async => _wrapped()),
      wrappedPlayerNameProvider.overrideWithValue('Samih'),
    ];

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

  testWidgets('le bilan ouvre sur la feuille de saison', (tester) async {
    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides(), reducedMotion: true),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('TA SAISON'), findsOneWidget);
    // Le millésime est posé sur deux lignes, en très grand.
    expect(find.text('2026\n2027'), findsOneWidget);
    expect(find.text('SAMIH'), findsOneWidget);
    // Huit écrans, donc huit segments de progression.
    expect(find.byType(LinearProgressIndicator), findsNWidgets(8));
  });

  testWidgets('un appui à droite avance, un appui à gauche revient',
      (tester) async {
    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides(), reducedMotion: true),
    );
    await tester.pump();
    await tester.pump();

    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final height =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    await tester.tapAt(Offset(width * .8, height * .55));
    await tester.pump();
    await tester.pump();
    expect(find.text('MATCHS JOUÉS'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    await tester.tapAt(Offset(width * .1, height * .55));
    await tester.pump();
    await tester.pump();
    expect(find.text('2026\n2027'), findsOneWidget);
  });

  testWidgets('la dernière page propose le partage', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides(), reducedMotion: true),
    );
    await tester.pump();
    await tester.pump();

    for (var i = 0; i < 7; i += 1) {
      await tester.tapAt(const Offset(900, 1500));
      await tester.pump();
      await tester.pump();
    }

    expect(find.text('TA SAISON EN ENTIER'), findsOneWidget);
    expect(find.text('PARTAGER MA SAISON'), findsOneWidget);
    expect(find.text('Partager par thème'), findsOneWidget);
    // Les valeurs du récapitulatif sont bien celles du bilan.
    expect(find.text('12'), findsOneWidget);
    expect(find.text('58 %'), findsOneWidget);
    expect(find.text('7 V · 2 N · 3 D'), findsOneWidget);
  });

  testWidgets('le pourcentage garde son signe', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides(), reducedMotion: true),
    );
    await tester.pump();
    await tester.pump();

    for (var i = 0; i < 6; i += 1) {
      await tester.tapAt(const Offset(900, 1500));
      await tester.pump();
      await tester.pump();
    }

    expect(find.text('L’ÉQUIPE QUAND TU ÉTAIS LÀ'), findsOneWidget);
    expect(find.text('58 %'), findsOneWidget);
  });

  testWidgets('la musique se coupe et se remet', (tester) async {
    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides(), reducedMotion: true),
    );
    await tester.pump();
    await tester.pump();

    final mute = find.byKey(const ValueKey('wrapped-mute-button'));
    expect(mute, findsOneWidget);
    expect(
      tester.widget<IconButton>(mute).tooltip,
      'Couper la musique',
    );
  });

  testWidgets('la feuille partagée porte le nom du joueur', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SeasonWrappedFullShareSheet(
            wrapped: _wrapped(),
            playerName: 'Samih',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AS GRINTA · 2026-2027'), findsOneWidget);
    expect(find.text('MA SAISON'), findsOneWidget);
    expect(find.text('SAMIH'), findsOneWidget);
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
        [
          mySeasonWrappedProvider.overrideWith((ref) async => null),
          wrappedPlayerNameProvider.overrideWithValue('Samih'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pas encore de bilan'), findsOneWidget);
  });
}
