import 'package:as_grinta/features/sports_management/domain/composition_simulation.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';
import 'package:flutter_test/flutter_test.dart';

/// Identités canoniques de l'effectif, telles que le fichier de postes les
/// connaît. Elles servent à vérifier la simulation sur des joueurs réels
/// plutôt que sur des profils inventés.
const String samihGardien = '89f24276-dac0-4046-87a3-6c28e48fef3a';
const String samuelGranier = 'c5ba5eda-9cb3-4ec5-aa68-eef33b84a3ad';
const String stephaneFernandez = '7fe67f9b-75c0-4606-8030-021b00900cc1';
const String julienCesar = 'a1cac6b7-ef09-493f-9d3e-7078fcaa3d97';
const String olivierMillet = 'b26acaab-3d33-4371-a80f-5692ffb6d026';
const String alyounCherfi = '2c40dbe5-a804-4b9f-9256-432ab85ce495';
const String julioVignard = '2e161341-e2b5-48d2-b852-717be71024aa';
const String romainSpigolon = 'aba6998e-e020-4e62-9b35-4a9583ca5ad9';
const String floArnauduc = '1343e65c-63fa-4f8f-af56-56d3136962b5';
const String lukaBrunel = 'b9f696f7-297d-4891-96f1-34a974c0f7a1';
const String allanBamokena = '9af382c3-7df3-4109-8c07-601754f19f89';
const String nicolasBelmonte = '4bbdab69-6f29-430d-8c05-eb8bc4b1e547';
const String milanCouzin = '5c681291-ec75-47ed-8bee-1b538b69cefe';
const String hakimCherfi = 'aaa132f5-1fca-47dc-a875-5c2aaa4a9ae9';
const String simonReis = 'af7dfe56-0be5-4d5c-8dda-140a99df7dbf';

SimulationCandidate candidate(
  String name, {
  String? playerId,
  int benchCount = 0,
  bool isGuest = false,
  bool isGoalkeeper = false,
}) {
  return SimulationCandidate(
    participantId: name,
    displayName: name,
    benchCount: benchCount,
    profile: playerId == null ? null : kPlayerPositionProfiles[playerId],
    isGuest: isGuest,
    isGoalkeeper: isGoalkeeper,
  );
}

/// Le poste occupé par un joueur, ou null s'il n'est pas sur le terrain.
String? slotOf(SimulatedComposition simulation, String name) {
  for (final placement in simulation.placements) {
    if (placement.candidate.participantId == name) return placement.slot.label;
  }
  return null;
}

SimulatedPlacementReason? reasonOf(
  SimulatedComposition simulation,
  String name,
) {
  for (final placement in simulation.placements) {
    if (placement.candidate.participantId == name) return placement.reason;
  }
  return null;
}

void main() {
  final formation = formationForCode('4-2-1-3');

  group('Fichier des postes de référence', () {
    test('chaque poste cité existe sur la feuille de match', () {
      for (final profile in kPlayerPositionProfiles.values) {
        for (final share in profile.samples) {
          expect(
            matchSheetSlotPositions.containsKey(share.slotLabel),
            isTrue,
            reason: '${profile.displayName} : poste inconnu '
                '${share.slotLabel}',
          );
        }
      }
    });

    test('les postes sont triés du plus fréquent au moins fréquent', () {
      for (final profile in kPlayerPositionProfiles.values) {
        expect(profile.samples, isNotEmpty);
        for (var index = 1; index < profile.samples.length; index += 1) {
          expect(
            profile.samples[index - 1].weight,
            greaterThanOrEqualTo(profile.samples[index].weight),
            reason: profile.displayName,
          );
        }
      }
    });

    test('les couteaux suisses sont ceux sans poste dominant', () {
      expect(kPlayerPositionProfiles[hakimCherfi]!.isVersatile, isTrue);
      expect(kPlayerPositionProfiles[simonReis]!.isVersatile, isTrue);
      expect(kPlayerPositionProfiles[milanCouzin]!.isVersatile, isFalse);
      expect(kPlayerPositionProfiles[samihGardien]!.mainSlotLabel, 'GB');
    });
  });

  group('Placement au poste de référence', () {
    test('un effectif type se range à ses postes habituels', () {
      final simulation = simulateComposition(
        slots: formation.slots,
        candidates: [
          candidate('Samih', playerId: samihGardien, isGoalkeeper: true),
          candidate('Alyoun', playerId: alyounCherfi),
          candidate('Julien', playerId: julienCesar),
          candidate('Olivier', playerId: olivierMillet),
          candidate('Julio', playerId: julioVignard),
          candidate('Romain', playerId: romainSpigolon),
          candidate('Flo', playerId: floArnauduc),
          candidate('Luka', playerId: lukaBrunel),
          candidate('Nicolas', playerId: nicolasBelmonte),
          candidate('Milan', playerId: milanCouzin),
          candidate('Allan', playerId: allanBamokena),
        ],
      );

      expect(simulation.emptySlots, isEmpty);
      expect(slotOf(simulation, 'Samih'), 'GB');
      expect(slotOf(simulation, 'Alyoun'), 'DG');
      expect(slotOf(simulation, 'Julio'), 'DD');
      expect(slotOf(simulation, 'Milan'), 'BU');
      expect(slotOf(simulation, 'Allan'), 'AD');
      expect(slotOf(simulation, 'Nicolas'), 'AG');
      // Fernandez absent : les deux axiaux sont Cesar et Millet.
      expect(slotOf(simulation, 'Julien'), 'DCG');
      expect(slotOf(simulation, 'Olivier'), 'DCD');
      expect(simulation.stretchedPlacements, isEmpty);
    });

    test('le second poste sert quand le premier est déjà pris', () {
      final simulation = simulateComposition(
        slots: formation.slots,
        candidates: [
          // Fernandez et Millet visent tous deux DCD ; l'un glisse en DCG,
          // qui est bien le second poste des deux.
          candidate('Stéphane', playerId: stephaneFernandez, benchCount: 3),
          candidate('Olivier', playerId: olivierMillet),
        ],
      );

      expect(slotOf(simulation, 'Stéphane'), 'DCD');
      expect(reasonOf(simulation, 'Stéphane'),
          SimulatedPlacementReason.mainPosition);
      expect(slotOf(simulation, 'Olivier'), 'DCG');
      expect(reasonOf(simulation, 'Olivier'),
          SimulatedPlacementReason.secondaryPosition);
    });

    test('un couteau suisse comble un poste laissé libre', () {
      final simulation = simulateComposition(
        slots: formationForCode('4-4-2 à plat').slots,
        candidates: [
          candidate('Stéphane', playerId: stephaneFernandez),
          candidate('Julien', playerId: julienCesar),
          candidate('Hakim', playerId: hakimCherfi),
        ],
      );

      expect(slotOf(simulation, 'Stéphane'), 'DCD');
      expect(slotOf(simulation, 'Julien'), 'DCG');
      expect(slotOf(simulation, 'Hakim'), isNotNull);
      expect(
        reasonOf(simulation, 'Hakim'),
        SimulatedPlacementReason.versatileAdjustment,
      );
    });

    test('un poste sans candidat naturel revient au joueur le plus proche', () {
      // Aucun buteur convoqué : le dispositif garde ses trois postes
      // offensifs, comblés par glissement plutôt que laissés vides.
      final simulation = simulateComposition(
        slots: formation.slots,
        candidates: [
          candidate('Nicolas', playerId: nicolasBelmonte),
          candidate('Allan', playerId: allanBamokena),
          candidate('Luka', playerId: lukaBrunel),
        ],
      );

      expect(slotOf(simulation, 'Nicolas'), 'AG');
      expect(slotOf(simulation, 'Allan'), 'AD');
      expect(slotOf(simulation, 'Luka'), isNotNull);
      expect(simulation.bench, isEmpty);
    });
  });

  group('Rotation par le compteur banc', () {
    test('à poste égal, le plus souvent remplaçant est titularisé', () {
      final simulation = simulateComposition(
        slots: formation.slots,
        candidates: [
          candidate('Alyoun', playerId: alyounCherfi, benchCount: 1),
          candidate('Alyoun bis', playerId: alyounCherfi, benchCount: 7),
        ],
      );

      expect(slotOf(simulation, 'Alyoun bis'), 'DG');
      expect(slotOf(simulation, 'Alyoun'), isNot('DG'));
    });

    test('le banc est ordonné du plus attendu au moins attendu', () {
      final simulation = simulateComposition(
        slots: <FootballFormationSlot>[
          const FootballFormationSlot(label: 'BU', position: Offset(.50, .08)),
        ],
        candidates: [
          candidate('Peu', playerId: nicolasBelmonte, benchCount: 1),
          candidate('Beaucoup', playerId: lukaBrunel, benchCount: 9),
          candidate('Moyen', playerId: allanBamokena, benchCount: 4),
          candidate('Titulaire', playerId: milanCouzin, benchCount: 12),
        ],
      );

      expect(slotOf(simulation, 'Titulaire'), 'BU');
      expect(
        simulation.bench.map((entry) => entry.displayName),
        ['Beaucoup', 'Moyen', 'Peu'],
      );
    });

    test('une même convocation redonne toujours la même équipe', () {
      List<SimulationCandidate> squad() => [
            candidate('Samih', playerId: samihGardien, isGoalkeeper: true),
            candidate('Aki', benchCount: 2),
            candidate('Hakim', playerId: hakimCherfi, benchCount: 2),
            candidate('Simon', playerId: simonReis, benchCount: 2),
            candidate('Flo', playerId: floArnauduc, benchCount: 2),
          ];

      final first = simulateComposition(
        slots: formation.slots,
        candidates: squad(),
      );
      final second = simulateComposition(
        slots: formation.slots,
        candidates: squad(),
      );

      expect(
        first.placements
            .map((p) => '${p.slot.label}:${p.candidate.displayName}'),
        second.placements
            .map((p) => '${p.slot.label}:${p.candidate.displayName}'),
      );
    });
  });

  group('Gardien', () {
    test('le gardien déclaré prend les buts', () {
      final simulation = simulateComposition(
        slots: formation.slots,
        candidates: [
          candidate('Samih', playerId: samihGardien, isGoalkeeper: true),
          candidate('Stéphane', playerId: stephaneFernandez, benchCount: 9),
        ],
      );

      expect(slotOf(simulation, 'Samih'), 'GB');
      expect(
        reasonOf(simulation, 'Samih'),
        SimulatedPlacementReason.goalkeeper,
      );
    });

    test('sans gardien convoqué, les buts restent vides', () {
      final simulation = simulateComposition(
        slots: formation.slots,
        candidates: [
          // Granier a déjà gardé les buts, mais il n'est pas gardien déclaré.
          candidate('Samuel', playerId: samuelGranier, benchCount: 9),
          candidate('Stéphane', playerId: stephaneFernandez, benchCount: 9),
        ],
      );

      expect(simulation.emptySlots.map((slot) => slot.label), contains('GB'));
      expect(slotOf(simulation, 'Samuel'), isNot('GB'));
      expect(slotOf(simulation, 'Stéphane'), isNot('GB'));
    });

    test('le second gardien va sur le banc, jamais en défense', () {
      final simulation = simulateComposition(
        slots: formation.slots,
        candidates: [
          candidate('Habituel', playerId: samihGardien, isGoalkeeper: true),
          candidate(
            'Doublure',
            playerId: samihGardien,
            isGoalkeeper: true,
            benchCount: 8,
          ),
        ],
      );

      // La rotation vaut aussi pour les gants : celui qui a le plus attendu
      // prend les buts.
      expect(slotOf(simulation, 'Doublure'), 'GB');
      // L'autre reste gardien : il ne dépanne pas à un poste de champ.
      expect(slotOf(simulation, 'Habituel'), isNull);
      expect(
        simulation.bench.map((entry) => entry.displayName),
        contains('Habituel'),
      );
    });
  });

  group('Invités et joueurs sans profil', () {
    test('un invité reste sur le banc même si le terrain est incomplet', () {
      final simulation = simulateComposition(
        slots: formation.slots,
        candidates: [
          candidate('Invité', isGuest: true, benchCount: 12),
          candidate('Milan', playerId: milanCouzin),
        ],
      );

      expect(slotOf(simulation, 'Invité'), isNull);
      expect(
        simulation.bench.map((entry) => entry.displayName),
        contains('Invité'),
      );
      expect(simulation.emptySlots, isNotEmpty);
    });

    test('un joueur sans profil ne sert qu’à combler un poste vide', () {
      final simulation = simulateComposition(
        slots: <FootballFormationSlot>[
          const FootballFormationSlot(label: 'BU', position: Offset(.50, .08)),
          const FootballFormationSlot(label: 'DC', position: Offset(.50, .72)),
        ],
        candidates: [
          candidate('Recrue', benchCount: 12),
          candidate('Milan', playerId: milanCouzin, benchCount: 0),
        ],
      );

      // Malgré son compteur banc, la recrue ne prend pas la pointe à Couzin :
      // elle hérite du poste que personne ne revendique.
      expect(slotOf(simulation, 'Milan'), 'BU');
      expect(slotOf(simulation, 'Recrue'), 'DC');
      expect(
        reasonOf(simulation, 'Recrue'),
        SimulatedPlacementReason.lastResort,
      );
    });

    test('aucun convoqué ne donne ni titulaire ni remplaçant', () {
      final simulation = simulateComposition(
        slots: formation.slots,
        candidates: const [],
      );

      expect(simulation.placements, isEmpty);
      expect(simulation.bench, isEmpty);
      expect(simulation.emptySlots, hasLength(formation.slotLabels.length));
    });
  });
}
