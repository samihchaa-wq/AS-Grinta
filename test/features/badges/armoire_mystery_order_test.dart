import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:flutter_test/flutter_test.dart';

BadgeDef _custom(String code, String name, {int sortOrder = 900}) => BadgeDef(
      code: code,
      name: name,
      description: 'Description de $name',
      emoji: '🏅',
      imageUrl: null,
      color: '#123456',
      family: 'joueur',
      kind: 'custom',
      category: 'faits_de_jeu',
      metric: null,
      threshold: null,
      sortOrder: sortOrder,
    );

void main() {
  final catalog = [
    _custom('custom_une_deux', 'Une-deux', sortOrder: 1),
    _custom('custom_traitre', 'Traître', sortOrder: 2),
    _custom('custom_doubl_hdm', 'Doublé HDM', sortOrder: 900),
    _custom('custom_boucle', 'La boucle est bouclée', sortOrder: 3),
    _custom('custom_equipe', 'Équipe type', sortOrder: 4),
    _custom('role_goalkeeper', 'Gardien', sortOrder: 5),
  ];

  Armoire build(Map<String, DateTime> earnedAt) => buildArmoire(
        catalog: catalog,
        earnedAt: earnedAt,
        featuredCodes: const {},
        seenCodes: earnedAt.keys.toSet(),
        metrics: const {},
        displayMetrics: const {},
        starCounts: const {},
      );

  test('les badges à découvrir sont rangés par ordre alphabétique', () {
    final armoire = build(const {});

    expect(armoire.toDiscover.map((b) => b.def.name), [
      'Doublé HDM',
      'Équipe type',
      'Gardien',
      'La boucle est bouclée',
      'Traître',
      'Une-deux',
    ]);
  });

  test('un mystère gagné se révèle à sa place, sans remonter en tête', () {
    final armoire = build({
      'custom_doubl_hdm': DateTime(2026, 9, 30),
      'role_goalkeeper': DateTime(2026, 8, 15),
    });

    final discover = armoire.toDiscover;
    expect(discover.map((b) => b.def.name), [
      'Doublé HDM',
      'Équipe type',
      'La boucle est bouclée',
      'Traître',
      'Une-deux',
    ]);
    expect(discover.first.state, BadgeState.validated);
    expect(
      discover.skip(1).every((b) => b.state == BadgeState.locked),
      isTrue,
    );
    // Le mystère gagné n'est pas répété dans « Débloqués ».
    expect(armoire.unlocked.map((b) => b.def.code), ['role_goalkeeper']);
  });

  test('le tri ignore majuscules et accents', () {
    final names = ['zèbre', 'Équipe', 'arbre', 'Été', 'ecole']
      ..sort(compareBadgeNames);
    expect(names, ['arbre', 'ecole', 'Équipe', 'Été', 'zèbre']);
  });
}
