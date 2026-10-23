import 'package:as_grinta/features/sports_management/domain/composition_simulation.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_history.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les quatre matchs à onze de la saison 2026-2027 joués avant le
/// 27 octobre, tels que la production les a enregistrés : coordonnées des
/// titulaires, remplaçants, et identité canonique de chacun.
///
/// L'ancienne simulation envoyait, sur chacun d'eux, un défenseur central au
/// milieu pendant qu'un vrai milieu restait sur le banc. Ce test rejoue la
/// saison avec ce que l'écran savait avant chaque match, et vérifie que la
/// proposition ressemble à ce que l'équipe a réellement aligné.
const Map<String, String> _playerIds = {
  'Samih': '89f24276-dac0-4046-87a3-6c28e48fef3a',
  'Alyoun': '2c40dbe5-a804-4b9f-9256-432ab85ce495',
  'Julien': 'a1cac6b7-ef09-493f-9d3e-7078fcaa3d97',
  'Stéphane': '7fe67f9b-75c0-4606-8030-021b00900cc1',
  'Amine': 'c1fe7ae2-3dea-4981-9510-a61826e5341a',
  'Flo': '1343e65c-63fa-4f8f-af56-56d3136962b5',
  'Luka': 'b9f696f7-297d-4891-96f1-34a974c0f7a1',
  'Alban': 'a595c2c2-be69-430c-8dd5-6bbaa2dd7a65',
  'François': '0cd558f5-b283-4e7c-bc3d-ac09f63655f8',
  'Milan': '5c681291-ec75-47ed-8bee-1b538b69cefe',
  'Allan': '9af382c3-7df3-4109-8c07-601754f19f89',
  'Olivier': 'b26acaab-3d33-4371-a80f-5692ffb6d026',
  'Samuel': 'c5ba5eda-9cb3-4ec5-aa68-eef33b84a3ad',
  'Romain': 'bd469e77-23a2-4be4-98e4-2e85923fac69',
  'Nicolas': '4bbdab69-6f29-430d-8c05-eb8bc4b1e547',
  'Hakim': 'aaa132f5-1fca-47dc-a875-5c2aaa4a9ae9',
  'Simon': '0d8871eb-b369-4578-8ba6-17790623fceb',
  'Aki': 'a0a105a2-5041-4555-90bd-a75140ad701c',
};

/// Défenseurs de métier : aucun ne doit être envoyé au milieu.
const Set<String> _defenders = {
  'Julien',
  'Stéphane',
  'Olivier',
  'Simon',
  'Hakim',
};

class _PlayedMatch {
  const _PlayedMatch(this.kickoffAt, this.starters, this.bench);

  final DateTime kickoffAt;
  final Map<String, Offset> starters;
  final List<String> bench;

  List<String> get squad => [...starters.keys, ...bench];
}

final List<_PlayedMatch> _season = [
  _PlayedMatch(
    DateTime.utc(2026, 9, 21, 18, 45),
    const {
      'Samih': Offset(.50, .85),
      'Alyoun': Offset(.10, .65),
      'Julien': Offset(.32, .70),
      'Stéphane': Offset(.68, .70),
      'Amine': Offset(.90, .65),
      'Flo': Offset(.30, .50),
      'Luka': Offset(.70, .50),
      'Alban': Offset(.50, .27),
      'François': Offset(.12, .22),
      'Milan': Offset(.50, .08),
      'Allan': Offset(.88, .22),
    },
    const ['Romain', 'Simon', 'Aki', 'Hakim', 'Olivier'],
  ),
  _PlayedMatch(
    DateTime.utc(2026, 9, 28, 19),
    const {
      'Samih': Offset(.50, .85),
      'Alyoun': Offset(.10, .65),
      'Julien': Offset(.32, .70),
      'Olivier': Offset(.68, .70),
      'Samuel': Offset(.90, .65),
      'Flo': Offset(.30, .50),
      'Romain': Offset(.70, .50),
      'Alban': Offset(.50, .27),
      'François': Offset(.12, .22),
      'Milan': Offset(.50, .08),
      'Allan': Offset(.88, .22),
    },
    const ['Nicolas', 'Amine', 'Stéphane'],
  ),
  _PlayedMatch(
    DateTime.utc(2026, 10, 5, 18, 45),
    const {
      'Samih': Offset(.50, .89),
      'Amine': Offset(.12, .67),
      'Olivier': Offset(.36, .72),
      'Stéphane': Offset(.64, .72),
      'Samuel': Offset(.88, .67),
      'Luka': Offset(.36, .55),
      'Romain': Offset(.64, .55),
      'Alban': Offset(.50, .36),
      'Nicolas': Offset(.15, .23),
      'Milan': Offset(.50, .14),
      'Allan': Offset(.85, .23),
    },
    const ['Julien', 'François'],
  ),
  _PlayedMatch(
    DateTime.utc(2026, 10, 12, 18, 45),
    const {
      'Samih': Offset(.50, .89),
      'Amine': Offset(.12, .67),
      'Julien': Offset(.36, .72),
      'Stéphane': Offset(.64, .72),
      'Olivier': Offset(.88, .67),
      'Flo': Offset(.36, .55),
      'Romain': Offset(.64, .55),
      'Alban': Offset(.50, .36),
      'François': Offset(.15, .23),
      'Milan': Offset(.50, .14),
      'Allan': Offset(.85, .23),
    },
    const ['Samuel', 'Hakim', 'Luka'],
  ),
];

/// Ceux qui ont commencé remplaçants la dernière fois qu'ils ont joué, parmi
/// les [played] premiers matchs de la saison.
Set<String> _benchedLastTime(int played) {
  final lastStatus = <String, bool>{};
  for (final match in _season.take(played)) {
    for (final name in match.starters.keys) {
      lastStatus[name] = false;
    }
    for (final name in match.bench) {
      lastStatus[name] = true;
    }
  }
  return {
    for (final entry in lastStatus.entries)
      if (entry.value) entry.key,
  };
}

/// Simule la composition d'un match avec ce que l'écran savait juste avant :
/// les postes nourris des matchs déjà joués, le compteur banc et ceux qui
/// étaient remplaçants la dernière fois qu'ils ont joué.
SimulatedComposition _simulateBefore(int matchIndex, List<String> squad) {
  final played = _season.take(matchIndex);
  final profiles = mergePlayerPositionProfiles(
    history: [
      for (final match in played)
        for (final starter in match.starters.entries)
          PlayedPosition(
            playerId: _playerIds[starter.key]!,
            position: starter.value,
            kickoffAt: match.kickoffAt,
          ),
    ],
  );
  final benchCounts = <String, int>{};
  for (final match in played) {
    for (final name in match.bench) {
      benchCounts.update(name, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  final benchedLastTime = _benchedLastTime(matchIndex);

  return simulateComposition(
    slots: formationForCode('4-2-1-3').slots,
    candidates: [
      for (final name in squad)
        SimulationCandidate(
          participantId: name,
          displayName: name,
          benchCount: benchCounts[name] ?? 0,
          profile: profiles[_playerIds[name]],
          isGoalkeeper: name == 'Samih',
          benchedLastTime: benchedLastTime.contains(name),
        ),
    ],
  );
}

String? _slotOf(SimulatedComposition simulation, String name) {
  for (final placement in simulation.placements) {
    if (placement.candidate.participantId == name) return placement.slot.label;
  }
  return null;
}

void main() {
  for (var index = 0; index < _season.length; index += 1) {
    final match = _season[index];
    final date = match.kickoffAt.toIso8601String().substring(0, 10);

    test('$date : la proposition ressemble au onze réellement aligné', () {
      final simulation = _simulateBefore(index, match.squad);
      final starters = {
        for (final placement in simulation.placements)
          placement.candidate.participantId,
      };

      expect(simulation.emptySlots, isEmpty);
      expect(simulation.stretchedPlacements, isEmpty);
      for (final defender in _defenders) {
        expect(
          ['MDG', 'MDD', 'MOC'],
          isNot(contains(_slotOf(simulation, defender))),
          reason: '$defender ne joue pas au milieu',
        );
      }
      // La rotation titularise ceux qui étaient remplaçants la dernière fois
      // qu'ils ont joué ; l'équipe ne l'a pas toujours fait (Hakim, laissé
      // sur le banc le 12 octobre). Hors ces cas, au plus un choix
      // d'entraîneur d'écart avec le onze aligné.
      final rotationOverrides = _benchedLastTime(index)
          .where((name) => match.bench.contains(name))
          .length;
      expect(
        match.starters.keys.where(starters.contains).length,
        greaterThanOrEqualTo(10 - rotationOverrides),
        reason: 'titulaires simulés : $starters',
      );
    });

    if (index > 0) {
      test('$date : les remplaçants de leur dernier match sont titulaires', () {
        final simulation = _simulateBefore(index, match.squad);
        final starters = {
          for (final placement in simulation.placements)
            placement.candidate.participantId,
        };
        for (final name in _benchedLastTime(index)) {
          if (!match.squad.contains(name)) continue;
          expect(starters, contains(name));
        }
      });
    }
  }

  test('27 octobre : la convocation réelle donne un onze cohérent', () {
    final simulation = _simulateBefore(_season.length, const [
      'Samih',
      'Alban',
      'Allan',
      'Amine',
      'Flo',
      'Hakim',
      'Julien',
      'Luka',
      'Milan',
      'Nicolas',
      'Olivier',
      'Romain',
      'Simon',
      'Stéphane',
    ]);

    expect(simulation.emptySlots, isEmpty);
    expect(simulation.stretchedPlacements, isEmpty);
    // Hakim et Luka, remplaçants le 12 octobre ; Simon, remplaçant le
    // 21 septembre, la dernière fois qu'il a joué.
    expect(simulation.promotedFromBench.map((p) => p.candidate.displayName),
        unorderedEquals(['Hakim', 'Luka', 'Simon']));
    expect(_slotOf(simulation, 'Samih'), 'GB');
    expect(_slotOf(simulation, 'Milan'), 'BU');
    expect(_slotOf(simulation, 'Allan'), 'AD');
    expect(_slotOf(simulation, 'Alban'), 'MOC');
    for (final defender in _defenders) {
      expect(
        ['MDG', 'MDD', 'MOC'],
        isNot(contains(_slotOf(simulation, defender))),
        reason: '$defender ne joue pas au milieu',
      );
    }
  });
}
