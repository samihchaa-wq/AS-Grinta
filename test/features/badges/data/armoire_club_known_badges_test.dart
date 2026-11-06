import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:flutter_test/flutter_test.dart';

BadgeDef _custom(String code, String name) => BadgeDef(
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
      sortOrder: 900,
    );

BadgeDef _secretTier(String code, String name) => BadgeDef(
      code: code,
      name: name,
      description: 'Description de $name',
      emoji: '🏅',
      imageUrl: null,
      color: '#123456',
      family: 'joueur',
      kind: 'tier',
      category: 'faits_de_jeu',
      metric: 'max_match_goals',
      threshold: 3,
      sortOrder: 10,
      standalone: true,
      secret: true,
    );

void main() {
  final catalog = [
    _custom('custom_doubl_hdm', 'Doublé HDM'),
    _custom('custom_traitre', 'Traître'),
    _secretTier('triple', 'Triplé'),
  ];

  Armoire build({
    Map<String, DateTime> earnedAt = const {},
    Set<String> clubEarnedCodes = const {},
  }) =>
      buildArmoire(
        catalog: catalog,
        earnedAt: earnedAt,
        featuredCodes: const {},
        seenCodes: earnedAt.keys.toSet(),
        metrics: const {},
        displayMetrics: const {},
        starCounts: const {},
        clubEarnedCodes: clubEarnedCodes,
      );

  ArmoireBadge find(Armoire armoire, String code) =>
      armoire.toDiscover.firstWhere((b) => b.def.code == code);

  test('un mystère que personne n’a gagné reste masqué', () {
    final armoire = build();
    expect(armoire.toDiscover.every((b) => !b.knownToClub), isTrue);
  });

  test('un mystère déjà gagné par un autre membre se dévoile, sous cadenas',
      () {
    final armoire = build(clubEarnedCodes: {'custom_doubl_hdm', 'triple'});

    final doubled = find(armoire, 'custom_doubl_hdm');
    expect(doubled.state, BadgeState.locked);
    expect(doubled.knownToClub, isTrue);

    final triple = find(armoire, 'triple');
    expect(triple.state, BadgeState.locked);
    expect(triple.knownToClub, isTrue);

    expect(find(armoire, 'custom_traitre').knownToClub, isFalse);
  });

  test('un mystère gagné par la personne elle-même reste affiché normalement',
      () {
    final armoire = build(
      earnedAt: {'custom_doubl_hdm': DateTime(2026, 9, 30)},
      clubEarnedCodes: {'custom_doubl_hdm'},
    );

    final doubled = find(armoire, 'custom_doubl_hdm');
    expect(doubled.state, BadgeState.validated);
    expect(doubled.knownToClub, isFalse);
  });

  test(
      'les titulaires sont regroupés par badge, sans doublon, par ordre '
      'alphabétique', () {
    final holders = groupBadgeHolders([
      {
        'profile_id': 'p2',
        'badges': {'code': 'custom_doubl_hdm'},
        'profiles': {'first_name': 'poulain', 'surnom': null},
      },
      {
        'profile_id': 'p1',
        'badges': {'code': 'custom_doubl_hdm'},
        'profiles': {'first_name': 'Samih', 'surnom': 'Amine'},
      },
      {
        'profile_id': 'p1',
        'badges': {'code': 'custom_doubl_hdm'},
        'profiles': {'first_name': 'Samih', 'surnom': 'Amine'},
      },
      {
        'profile_id': 'p3',
        'badges': {'code': 'triple'},
        'profiles': {'first_name': '', 'surnom': ''},
      },
      {
        'profile_id': 'p4',
        'badges': null,
        'profiles': {'first_name': 'Sans badge'},
      },
    ]);

    expect(holders.keys, unorderedEquals(['custom_doubl_hdm', 'triple']));
    expect(
      holders['custom_doubl_hdm']!.map((h) => h.name),
      ['Amine', 'Poulain'],
    );
    expect(holders['triple']!.single.name, 'Joueur');
  });
}
