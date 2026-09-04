import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:as_grinta/features/matches/data/historical_match_detail_repository.dart';
import 'package:as_grinta/features/matches/presentation/historical_match_detail_page.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _archiveRow({
  required List<String> names,
  Map<String, dynamic> identities = const {},
  List<Map<String, dynamic>> scorers = const [],
}) {
  return {
    'formation': '4-4-2',
    'field_players': [
      for (final name in names)
        {'name': name, 'is_gk': false, 'x_pct': 50, 'y_pct': 50},
    ],
    'bench_players': const <String>[],
    'present_names': names,
    'scorers': scorers,
    'motm_names': const <String>[],
    'photo_urls': const <String, dynamic>{},
    'display_names': identities,
  };
}

void main() {
  group('Calendrier : un match archivé appelle les joueurs par leur surnom',
      () {
    test('le surnom du club remplace le prénom de la feuille de match', () {
      final detail = historicalMatchDetailFromRow(
        _archiveRow(
          names: ['Olivier Millet'],
          identities: {
            'Olivier Millet': {'name': 'Poulain', 'last_initial': 'M'},
          },
        ),
      );

      expect(detail.fieldPlayers.single.name, 'Poulain');
      expect(detail.fieldPlayers.single.lastInitial, 'M');
      expect(detail.presentNames, ['Poulain']);
    });

    test('un joueur que l’archive ne relie à personne garde son prénom', () {
      final detail = historicalMatchDetailFromRow(
        _archiveRow(names: ['Xavier Inconnu']),
      );

      expect(detail.fieldPlayers.single.name, 'Xavier');
      expect(detail.fieldPlayers.single.lastInitial, 'I');
    });

    test('deux appellations identiques reçoivent l’initiale du nom', () {
      final detail = historicalMatchDetailFromRow(
        _archiveRow(
          names: ['Julien Cesar', 'Julien Durand'],
          identities: {
            'Julien Cesar': {'name': 'Julien', 'last_initial': 'C'},
            'Julien Durand': {'name': 'Julien', 'last_initial': 'D'},
          },
        ),
      );

      expect(
        detail.fieldPlayers.map((player) => player.name),
        ['Julien C.', 'Julien D.'],
      );
    });

    test('les buteurs portent la même appellation que le terrain', () {
      final detail = historicalMatchDetailFromRow(
        _archiveRow(
          names: ['Milan Couzin'],
          identities: {
            'Milan Couzin': {'name': 'Pipo', 'last_initial': 'C'},
          },
          scorers: [
            {'name': 'Milan Couzin', 'goals': 2},
          ],
        ),
      );

      expect(detail.scorers.single.name, 'Pipo');
      expect(detail.scorers.single.goals, 2);
    });

    test('le coach reste exclu de l’effectif de secours même surnommé', () {
      final detail = historicalMatchDetailFromRow(
        _archiveRow(
          names: ['Philippe Couzin', 'Milan Couzin'],
          identities: {
            'Philippe Couzin': {'name': 'Coach', 'last_initial': 'C'},
            'Milan Couzin': {'name': 'Pipo', 'last_initial': 'C'},
          },
        ),
      );

      final roster = historicalFallbackPlayers(detail);
      expect(roster.map((player) => player.name), isNot(contains('Coach')));
      expect(roster.map((player) => player.name), contains('Pipo'));
    });
  });

  group('Statistiques : vrais prénoms, initiale seulement si homonymes', () {
    test('un prénom unique reste seul', () {
      expect(statisticsName('Olivier', lastInitial: 'M'), 'Olivier');
    });

    test('deux homonymes sont départagés par l’initiale du nom', () {
      expect(
        statisticsName('Julien', lastInitial: 'C', isHomonym: true),
        'Julien C.',
      );
      expect(
        statisticsName('Julien', lastInitial: 'Durand', isHomonym: true),
        'Julien D.',
      );
    });

    test('sans nom de famille connu, aucun suffixe n’est inventé', () {
      expect(statisticsName('Aki', isHomonym: true), 'Aki');
    });
  });
}
