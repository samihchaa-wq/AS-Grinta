import 'package:as_grinta/features/matches/data/historical_match_detail_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// L'import d'archives place un faux joueur nommé « Poste laissé vide » aux
/// emplacements dont la vieille feuille de match ne donne pas le nom. Sans
/// filtre, l'appli le raccourcissait en « Poste » et l'affichait comme un
/// joueur : ces tests verrouillent le fait qu'il reste un trou.
void main() {
  Map<String, dynamic> vacantSlot(String name) => {
        'name': name,
        'position_label': 'Arrière latéral',
        'x_pct': 10.0,
        'y_pct': 68.5,
        'is_gk': false,
      };

  test('un emplacement vide ne devient pas un joueur nommé « Poste »', () {
    final detail = historicalMatchDetailFromRow({
      'formation': '4-1-4-1',
      'field_players': [
        {
          'name': 'Milan Couzin',
          'position_label': 'Avant-centre',
          'x_pct': 50.0,
          'y_pct': 5.0,
          'is_gk': false,
        },
        vacantSlot('Poste laissé vide'),
      ],
      'bench_players': ['Poste laissé vide', 'Julio Vignard'],
      'present_names': ['Poste laissé vide', 'Milan Couzin'],
      'scorers': [
        {'name': 'Milan Couzin', 'goals': 3},
        {'name': 'Poste laissé vide', 'goals': 1},
      ],
      'motm_names': ['Poste laissé vide', 'Milan Couzin'],
      'photo_urls': {'Poste laissé vide': 'photo.jpg'},
    });

    expect(detail.fieldPlayers.length, 2);
    final vacant = detail.fieldPlayers.last;
    expect(vacant.isVacant, isTrue);
    expect(vacant.name, isEmpty);
    expect(vacant.photoUrl, isNull);
    expect(vacant.xPct, 10.0);
    expect(detail.fieldPlayers.first.name, 'Milan');
    expect(detail.fieldPlayers.first.isVacant, isFalse);

    expect(detail.benchPlayers.map((p) => p.name), ['Julio']);
    expect(detail.presentNames, ['Milan']);
    expect(detail.scorers.map((s) => s.name), ['Milan']);
    expect(detail.motmNames, ['Milan']);
    expect(detail.hasComposition, isTrue);
  });

  test('le faux nom est reconnu quels que soient accents, casse et espaces',
      () {
    for (final variant in [
      'Poste laissé vide',
      'poste laisse vide',
      '  POSTE  LAISSÉ  VIDE ',
    ]) {
      final detail = historicalMatchDetailFromRow({
        'field_players': [
          vacantSlot(variant),
          {
            'name': 'Milan Couzin',
            'position_label': 'Avant-centre',
            'x_pct': 50.0,
            'y_pct': 5.0,
            'is_gk': false,
          },
        ],
      });
      expect(
        detail.fieldPlayers.first.isVacant,
        isTrue,
        reason: 'variante « $variant » non reconnue',
      );
    }
  });

  test("un vrai joueur dont le prénom est Poste n'est pas confondu", () {
    final detail = historicalMatchDetailFromRow({
      'field_players': [vacantSlot('Poste Dupont')],
    });

    expect(detail.fieldPlayers.single.isVacant, isFalse);
    expect(detail.fieldPlayers.single.name, 'Poste');
  });

  test('les emplacements vides ne créent pas de faux homonymes', () {
    final detail = historicalMatchDetailFromRow({
      'field_players': [
        vacantSlot('Poste laissé vide'),
        vacantSlot('Poste laissé vide'),
        {
          'name': 'Xavier Grand',
          'position_label': 'Milieu offensif',
          'x_pct': 33.0,
          'y_pct': 30.2,
          'is_gk': false,
        },
        {
          'name': 'Xavier Petit',
          'position_label': 'Milieu offensif',
          'x_pct': 67.0,
          'y_pct': 30.2,
          'is_gk': false,
        },
      ],
    });

    expect(
      detail.fieldPlayers.map((p) => p.name),
      ['', '', 'Xavier G.', 'Xavier P.'],
    );
  });

  test('un terrain fait uniquement de trous bascule sur la liste simple', () {
    final detail = historicalMatchDetailFromRow({
      'field_players': [
        vacantSlot('Poste laissé vide'),
        vacantSlot('Poste laissé vide'),
      ],
      'present_names': ['Milan Couzin'],
    });

    expect(detail.hasComposition, isFalse);
    expect(detail.isEmpty, isFalse);
  });
}
