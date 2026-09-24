import 'package:as_grinta/core/widgets/calendar_scoreline.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/match_history_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MatchModel finished({required String opponent, bool isHome = true}) =>
      MatchModel(
        id: 'match',
        seasonId: 'season',
        opponentId: 'opponent',
        kickoffAt: DateTime.utc(2026, 6, 15, 18, 45),
        isHome: isHome,
        plannedDurationMinutes: 90,
        status: 'termine',
        grintaScore: 3,
        opponentScore: 4,
        opponentName: opponent,
        matchType: 'championnat',
      );

  Future<void> pumpCard(
    WidgetTester tester,
    MatchModel match, {
    Widget? adminActions,
  }) async {
    await tester.binding.setSurfaceSize(const Size(375, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MatchHistoryCard(match: match, adminActions: adminActions),
          ),
        ),
      ),
    );
  }

  testWidgets('le score est centré dans la largeur de la carte', (
    tester,
  ) async {
    await pumpCard(
      tester,
      finished(opponent: 'AS Clinique Pasteur'),
      adminActions: IconButton(
        onPressed: () {},
        icon: const Icon(Icons.edit_outlined),
      ),
    );

    final card = tester.getRect(find.byType(Card));
    final score = tester.getRect(find.text('3 – 4'));
    expect(score.center.dx, moreOrLessEquals(card.center.dx, epsilon: 0.5));
  });

  testWidgets('seule AS Grinta porte son écusson', (tester) async {
    await pumpCard(tester, finished(opponent: 'FC Booster', isHome: false));

    final crests = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName ==
              CalendarScoreline.crestAsset,
    );
    expect(crests, findsOneWidget);
    // Grinta joue à l'extérieur : son écusson est à droite du score.
    expect(
      tester.getCenter(crests).dx,
      greaterThan(tester.getCenter(find.text('4 – 3')).dx),
    );
  });

  testWidgets('un nom trop long passe à la ligne sans changer de taille', (
    tester,
  ) async {
    const longName = 'Racing Club Toulouse Métropole Saint-Agne';
    await pumpCard(tester, finished(opponent: longName));

    final teamName = find.byWidgetPredicate(
      (widget) => widget is Text && widget.semanticsLabel == longName,
    );
    final text = tester.widget<Text>(teamName);
    expect(text.style?.fontSize, CalendarTeamName.regularSize);
    expect(text.maxLines, greaterThan(1));
    // Le nom est découpé en plusieurs lignes entre les mots.
    expect(text.data, contains('\n'));
    expect(text.data!.replaceAll('\n', ' '), longName);
  });

  testWidgets('chaque nom est centré dans sa moitié de carte', (
    tester,
  ) async {
    await pumpCard(tester, finished(opponent: 'FCB'));
    // Carte assez large pour réserver, en miroir de l'écusson, la place qui
    // garde « AS Grinta » au centre de sa moitié.
    await tester.binding.setSurfaceSize(const Size(900, 400));
    await tester.pump();

    for (final name in ['AS Grinta', 'FCB']) {
      final text = find.byWidgetPredicate(
        (widget) => widget is Text && widget.semanticsLabel == name,
      );
      final half = find.ancestor(of: text, matching: find.byType(Expanded));
      expect(
        tester.getCenter(text).dx,
        moreOrLessEquals(tester.getCenter(half.first).dx, epsilon: 0.5),
        reason: name,
      );
    }
  });

  group('balancedLines', () {
    // Largeur fictive : un caractère = 1.
    double width(String line) => line.length.toDouble();

    test('un nom qui tient reste sur une ligne', () {
      expect(CalendarTeamName.balancedLines('AS Grinta', width, 20), [
        'AS Grinta',
      ]);
    });

    test('un mot court final ne reste pas seul', () {
      expect(
        CalendarTeamName.balancedLines('TOAC Foot Loisir 2', width, 16),
        ['TOAC Foot', 'Loisir 2'],
      );
      expect(
        CalendarTeamName.balancedLines('Rouffiac Tolosan FC', width, 16),
        ['Rouffiac', 'Tolosan FC'],
      );
    });

    test('le plus petit nombre de lignes, le plus équilibré possible', () {
      expect(
        CalendarTeamName.balancedLines(
          'Amicale Olympique Cornebarrieu',
          width,
          13,
        ),
        ['Amicale', 'Olympique', 'Cornebarrieu'],
      );
    });

    test('un mot trop long à lui seul est laissé au retour automatique', () {
      expect(CalendarTeamName.balancedLines('Supercalifragilistic', width, 8), [
        'Supercalifragilistic',
      ]);
      // Avec d'autres mots, la coupure reste la plus équilibrée possible.
      expect(
        CalendarTeamName.balancedLines('FC Supercalifragilistic', width, 8),
        ['FC', 'Supercalifragilistic'],
      );
    });
  });
}
