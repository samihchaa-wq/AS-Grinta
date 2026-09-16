import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:flutter_test/flutter_test.dart';

BadgeDef _tier(String code, String name, String metric, int threshold,
        {int sortOrder = 0, bool standalone = false}) =>
    BadgeDef(
      code: code,
      name: name,
      description: '',
      emoji: '🏅',
      imageUrl: null,
      color: '#123456',
      family: 'joueur',
      kind: 'tier',
      category: 'joueur_all_time',
      metric: metric,
      threshold: threshold,
      sortOrder: sortOrder,
      standalone: standalone,
    );

final _paliersMatchs = <BadgeDef>[
  _tier('matches_played__50', 'Fidèle', 'matches_played', 50, sortOrder: 1),
  _tier('matches_played__100', 'Vétéran', 'matches_played', 100, sortOrder: 2),
  _tier('matches_played__200', 'Cadre du club', 'matches_played', 200,
      sortOrder: 3),
  _tier('matches_played__300', 'Légende du club', 'matches_played', 300,
      sortOrder: 4),
];

Armoire _armoire({
  required List<BadgeDef> catalog,
  required Map<String, DateTime> earnedAt,
  Map<String, int> metrics = const {},
  Map<String, int> displayMetrics = const {},
}) =>
    buildArmoire(
      catalog: catalog,
      earnedAt: earnedAt,
      featuredCodes: const {},
      seenCodes: earnedAt.keys.toSet(),
      metrics: metrics,
      displayMetrics: displayMetrics,
      starCounts: const {},
    );

void main() {
  test('tous les paliers gagnés restent visibles, pas seulement le plus haut',
      () {
    final armoire = _armoire(
      catalog: _paliersMatchs,
      earnedAt: {
        'matches_played__50': DateTime(2026, 8, 14),
        'matches_played__100': DateTime(2026, 8, 14),
      },
      metrics: const {'matches_played': 132},
      displayMetrics: const {'matches_played': 132},
    );

    expect(
      armoire.validated.map((b) => b.def.code),
      containsAll(<String>['matches_played__50', 'matches_played__100']),
    );
    // Le premier palier pas encore gagné reste la cible en cours.
    expect(armoire.inProgress.map((b) => b.def.code),
        contains('matches_played__200'));
    expect(armoire.validated.map((b) => b.def.code),
        isNot(contains('matches_played__200')));
  });

  test('seul le palier le plus haut porte le cumul réel', () {
    final armoire = _armoire(
      catalog: _paliersMatchs,
      earnedAt: {
        'matches_played__50': DateTime(2026, 8, 14),
        'matches_played__100': DateTime(2026, 8, 14),
      },
      metrics: const {'matches_played': 132},
      displayMetrics: const {'matches_played': 132},
    );

    final parCode = {for (final b in armoire.validated) b.def.code: b};
    // Sans ça, « Fidèle » et « Vétéran » afficheraient tous deux 132.
    expect(parCode['matches_played__50']!.displayValue, 50);
    expect(parCode['matches_played__100']!.displayValue, 132);
  });

  test('aucun palier gagné : rien en validé, le premier palier est en cours',
      () {
    final armoire = _armoire(
      catalog: _paliersMatchs,
      earnedAt: const {},
      metrics: const {'matches_played': 12},
      displayMetrics: const {'matches_played': 12},
    );

    expect(armoire.validated, isEmpty);
    expect(armoire.inProgress.single.def.code, 'matches_played__50');
    expect(armoire.inProgress.single.current, 12);
    expect(armoire.inProgress.single.target, 50);
  });

  test('les exploits autonomes gardent chacun leur propre vignette', () {
    final catalog = <BadgeDef>[
      _tier('max_match_goals__3', 'Triplé', 'max_match_goals', 3,
          sortOrder: 1, standalone: true),
      _tier('max_match_goals__4', 'Quadruplé', 'max_match_goals', 4,
          sortOrder: 2, standalone: true),
      _tier('max_match_goals__5', 'Quintuplé', 'max_match_goals', 5,
          sortOrder: 3, standalone: true),
    ];
    final armoire = _armoire(
      catalog: catalog,
      earnedAt: {
        'max_match_goals__3': DateTime(2026, 5, 1),
        'max_match_goals__4': DateTime(2026, 5, 1),
        'max_match_goals__5': DateTime(2026, 5, 1),
      },
      metrics: const {'max_match_goals': 5},
      displayMetrics: const {'max_match_goals': 5},
    );

    expect(armoire.validated.map((b) => b.def.code), <String>[
      'max_match_goals__3',
      'max_match_goals__4',
      'max_match_goals__5',
    ]);
    expect(armoire.inProgress, isEmpty);
  });
}
