import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/matches_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MatchModel _match({
  required String status,
  required bool isHome,
  int? grinta,
  int? opponent,
}) =>
    MatchModel(
      id: 'm1',
      seasonId: 's1',
      opponentId: 'o1',
      kickoffAt: DateTime(2026, 9, 20, 15),
      isHome: isHome,
      plannedDurationMinutes: 90,
      status: status,
      grintaScore: grinta,
      opponentScore: opponent,
      opponentName: 'AS Pantin',
    );

void main() {
  test('un nom d’équipe et son score ne se séparent jamais', () {
    final title = adminMatchTitle(
      _match(status: 'termine', isHome: false, grinta: 2, opponent: 2),
    );

    expect(title, 'AS Pantin 2 - 2 AS Grinta');
    // Seules coupures possibles : autour du tiret central.
    expect(' '.allMatches(title).length, 2);
  });

  test('un match à venir garde aussi ses noms d’équipe entiers', () {
    final title = adminMatchTitle(_match(status: 'a_venir', isHome: true));

    expect(title, 'AS Grinta – AS Pantin');
  });

  testWidgets('sur une ligne trop courte, la coupure tombe sur le tiret',
      (tester) async {
    final title = adminMatchTitle(
      _match(status: 'termine', isHome: false, grinta: 2, opponent: 2),
    );
    final painter = TextPainter(
      text: TextSpan(text: title, style: const TextStyle(fontSize: 18)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 300);

    final lines = painter.computeLineMetrics();
    expect(lines.length, greaterThan(1));
    final firstLineEnd =
        painter.getLineBoundary(const TextPosition(offset: 0)).end;
    expect(title.substring(0, firstLineEnd).trim(), 'AS Pantin 2 -');
  });
}
