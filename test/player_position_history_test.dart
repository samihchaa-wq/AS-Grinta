import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_history.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';
import 'package:flutter_test/flutter_test.dart';

/// Romain Spigolon : MDC très marqué dans l'archive.
const String romainSpigolon = 'aba6998e-e020-4e62-9b35-4a9583ca5ad9';

/// Un joueur inconnu de l'archive, comme une recrue.
const String recrue = 'recrue-sans-archive';

PlayedPosition played(
  String playerId,
  String slotLabel, {
  required int year,
  int month = 9,
}) {
  return PlayedPosition(
    playerId: playerId,
    position: matchSheetSlotPositions[slotLabel]!,
    kickoffAt: DateTime.utc(year, month, 15),
  );
}

List<PlayedPosition> repeated(
  String playerId,
  String slotLabel, {
  required int times,
  required int year,
}) {
  return [
    for (var index = 0; index < times; index += 1)
      played(playerId, slotLabel, year: year),
  ];
}

void main() {
  group('Lecture d’un placement joué', () {
    test('la position est ramenée au poste le plus proche', () {
      final entry = PlayedPosition(
        playerId: recrue,
        position: const Offset(.34, .69),
        kickoffAt: DateTime.utc(2026, 9, 15),
      );

      expect(entry.slotLabel, 'DCG');
    });

    test('une saison commence en juillet', () {
      expect(played(recrue, 'BU', year: 2026, month: 8).season, 2026);
      expect(played(recrue, 'BU', year: 2026, month: 7).season, 2026);
      expect(played(recrue, 'BU', year: 2026, month: 6).season, 2025);
      expect(played(recrue, 'BU', year: 2027, month: 1).season, 2026);
    });

    test('un match récent pèse plus qu’un match ancien', () {
      final recent = played(recrue, 'BU', year: 2027).weight;
      final reference = played(recrue, 'BU', year: 2025).weight;
      final vieux = played(recrue, 'BU', year: 2021).weight;

      expect(reference, closeTo(1, .0001));
      expect(recent, greaterThan(reference));
      expect(vieux, lessThan(reference));
      // Demi-vie de deux saisons : quatre ans en arrière valent un quart.
      expect(vieux, closeTo(.25, .0001));
    });
  });

  group('Fusion avec l’archive', () {
    test('sans historique, les profils figés sont rendus tels quels', () {
      final merged = mergePlayerPositionProfiles(history: const []);

      expect(merged, same(kPlayerPositionProfiles));
    });

    test('l’archive reste intacte pour les joueurs sans nouveau match', () {
      final merged = mergePlayerPositionProfiles(
        history: repeated(recrue, 'BU', times: 3, year: 2026),
      );

      expect(
        merged[romainSpigolon]!.mainSlotLabel,
        kPlayerPositionProfiles[romainSpigolon]!.mainSlotLabel,
      );
    });

    test('un joueur absent de l’archive se construit un profil', () {
      final merged = mergePlayerPositionProfiles(
        history: repeated(recrue, 'DD', times: 4, year: 2026),
      );

      expect(merged[recrue], isNotNull);
      expect(merged[recrue]!.mainSlotLabel, 'DD');
      expect(merged[recrue]!.appearances, 4);
      expect(merged[recrue]!.displayName, isEmpty);
    });

    test('quelques matchs ne renversent pas un poste très marqué', () {
      final avant = kPlayerPositionProfiles[romainSpigolon]!;
      final merged = mergePlayerPositionProfiles(
        history: repeated(romainSpigolon, 'DCD', times: 3, year: 2026),
      );

      expect(avant.mainSlotLabel, 'MDC');
      expect(merged[romainSpigolon]!.mainSlotLabel, 'MDC');
    });

    test('un changement de poste durable finit par faire basculer le profil',
        () {
      final merged = mergePlayerPositionProfiles(
        history: [
          ...repeated(romainSpigolon, 'DCD', times: 20, year: 2026),
          ...repeated(romainSpigolon, 'DCD', times: 20, year: 2027),
        ],
      );

      expect(merged[romainSpigolon]!.mainSlotLabel, 'DCD');
      expect(
        merged[romainSpigolon]!.secondarySlotLabel,
        kPlayerPositionProfiles[romainSpigolon]!.mainSlotLabel,
      );
    });

    test('les matchs joués s’ajoutent au compteur de titularisations', () {
      final avant = kPlayerPositionProfiles[romainSpigolon]!.appearances;
      final merged = mergePlayerPositionProfiles(
        history: repeated(romainSpigolon, 'MDC', times: 5, year: 2026),
      );

      expect(merged[romainSpigolon]!.appearances, avant + 5);
    });

    test('les postes fusionnés restent triés et bornés', () {
      final merged = mergePlayerPositionProfiles(
        history: [
          for (final slot in matchSheetSlotPositions.keys)
            played(romainSpigolon, slot, year: 2026),
        ],
      );

      final samples = merged[romainSpigolon]!.samples;
      expect(samples.length, lessThanOrEqualTo(6));
      for (var index = 1; index < samples.length; index += 1) {
        expect(
          samples[index - 1].weight,
          greaterThanOrEqualTo(samples[index].weight),
        );
      }
    });

    test('un joueur polyvalent peut se fixer un poste', () {
      // Aki Salabee n'a aucun poste dominant dans l'archive ; une série de
      // titularisations au même poste doit finir par lui en donner un.
      const aki = '6aa3588d-4131-444e-802c-5a0913244831';
      expect(kPlayerPositionProfiles[aki]!.isVersatile, isTrue);

      final merged = mergePlayerPositionProfiles(
        history: repeated(aki, 'MDC', times: 15, year: 2027),
      );

      expect(merged[aki]!.isVersatile, isFalse);
      expect(merged[aki]!.mainSlotLabel, 'MDC');
    });
  });
}
