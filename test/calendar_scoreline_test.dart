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

  testWidgets('un nom trop long passe sur plusieurs lignes, en plus petit', (
    tester,
  ) async {
    const longName = 'Racing Club Toulouse Métropole Saint-Agne';
    await pumpCard(tester, finished(opponent: longName));

    final text = tester.widget<Text>(find.text(longName));
    expect(text.style?.fontSize, CalendarTeamName.compactSize);
    expect(text.maxLines, greaterThan(1));
  });

  testWidgets('un nom court reste sur une ligne, en taille normale', (
    tester,
  ) async {
    await pumpCard(tester, finished(opponent: 'FCB'));

    final text = tester.widget<Text>(find.text('FCB'));
    expect(text.style?.fontSize, CalendarTeamName.regularSize);
    expect(text.maxLines, 1);
  });
}
