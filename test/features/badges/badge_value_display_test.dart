import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('numeric badge labels accept the real personal value', () {
    expect(baremeLabelFor('goals', 201), '201');
    expect(baremeLabelFor('matches_played_season', 0), '0');
    expect(baremeLabelFor('wins', 1), '1');
  });

  test('single-condition and title badges stay unnumbered', () {
    expect(baremeLabelFor('max_match_goals', 4), isNull);
    expect(baremeLabelFor('seasons_complete', 3), isNull);
    expect(baremeLabelFor('bet_against_grinta', 1), isNull);
    expect(baremeLabelFor('title_top_scorer', 2), isNull);
  });

  test('display value stays independent from unlock progress', () {
    const def = BadgeDef(
      code: 'matches_played_season__30',
      name: '30 matchs',
      description: '',
      emoji: '🏟️',
      imageUrl: null,
      color: '#123456',
      family: 'joueur',
      kind: 'tier',
      category: 'joueur_saison',
      metric: 'matches_played_season',
      threshold: 30,
      sortOrder: 1,
    );
    const badge = ArmoireBadge(
      def: def,
      state: BadgeState.inProgress,
      current: 29,
      target: 30,
      displayValue: 30,
    );

    expect(badge.displayValue, 30);
    expect(badge.current, 29);
    expect(badge.target, 30);
    expect(badge.progress, closeTo(29 / 30, 0.0001));
  });
}
