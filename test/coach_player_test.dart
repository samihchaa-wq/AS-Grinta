import 'package:as_grinta/features/coach/domain/coach_board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deux invités de même nom restent distincts', () {
    const first = CoachPlayer(
      id: 'guest|field|1|Alex',
      name: 'Alex',
      isGuest: true,
    );
    const second = CoachPlayer(
      id: 'guest|field|2|Alex',
      name: 'Alex',
      isGuest: true,
    );

    expect(first.displayName, second.displayName);
    expect(first.id, isNot(second.id));
  });

  test('le surnom reste prioritaire', () {
    const player = CoachPlayer(
      id: 'p1',
      name: 'Jean Dupont',
      surnom: 'Jeannot',
    );

    expect(player.displayName, 'Jeannot');
  });
}
