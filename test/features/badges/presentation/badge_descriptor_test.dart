import 'package:as_grinta/features/badges/presentation/badge_descriptor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('goalkeeper role badge has a dedicated descriptor', () {
    final descriptor = badgeDescriptorFor(code: 'role_goalkeeper');

    expect(descriptor.label, 'GARDIEN');
    expect(descriptor.period, isNull);
  });

  test('le nom d’un badge mystère est écrit en majuscules, accents compris',
      () {
    final descriptor = badgeDescriptorFor(
      code: 'custom_mal_chauff_1790198442991',
      category: 'faits_de_jeu',
      name: 'Mal échauffé',
    );

    expect(descriptor.label, 'MAL ÉCHAUFFÉ');
    expect(descriptor.period, isNull);
  });
}
