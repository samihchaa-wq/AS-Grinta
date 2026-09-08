import 'package:as_grinta/features/sports_management/domain/player_position_identity.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerPositionProfile profile(String displayName, {int appearances = 10}) {
  return PlayerPositionProfile(
    displayName: displayName,
    appearances: appearances,
    totalWeight: 10,
    samples: const [PlayerPositionSample('MDC', 10)],
  );
}

void main() {
  group('normalizePlayerName', () {
    test('met en minuscules et resserre les espaces', () {
      expect(normalizePlayerName('  Romain   SPIGOLON '), 'romain spigolon');
    });

    test('conserve les accents, comme la base', () {
      expect(normalizePlayerName('Frédéric Hermet'), 'frédéric hermet');
    });
  });

  group('realignPlayerPositionProfiles', () {
    final archive = <String, PlayerPositionProfile>{
      'ancien-romain': profile('Romain Spigolon'),
      'stable-flo': profile('Flo Arnauduc'),
    };

    test('déplace un profil sur l’identité qui porte désormais son histoire',
        () {
      final realigned = realignPlayerPositionProfiles(
        identitiesByName: const {'romain spigolon': 'nouveau-romain'},
        archive: archive,
      );

      expect(realigned['nouveau-romain']?.displayName, 'Romain Spigolon');
      expect(realigned.containsKey('ancien-romain'), isFalse);
    });

    test('laisse intacts les profils dont l’identité n’a pas bougé', () {
      final realigned = realignPlayerPositionProfiles(
        identitiesByName: const {'romain spigolon': 'nouveau-romain'},
        archive: archive,
      );

      expect(realigned['stable-flo']?.displayName, 'Flo Arnauduc');
      expect(realigned.length, archive.length);
    });

    test('garde la clé figée quand la base ne connaît pas le nom', () {
      final realigned = realignPlayerPositionProfiles(
        identitiesByName: const {'quelqu’un d’autre': 'inconnu'},
        archive: archive,
      );

      expect(realigned, same(archive));
    });

    test('ne fait rien sans résolution', () {
      expect(
        realignPlayerPositionProfiles(
          identitiesByName: const {},
          archive: archive,
        ),
        same(archive),
      );
    });

    test('retrouve le nom quelle que soit la casse ou les espaces', () {
      final realigned = realignPlayerPositionProfiles(
        identitiesByName: const {'flo arnauduc': 'nouveau-flo'},
        archive: <String, PlayerPositionProfile>{
          'ancien-flo': profile('  FLO   Arnauduc  '),
        },
      );

      expect(realigned.keys.single, 'nouveau-flo');
    });

    test('sur une collision, garde le profil le plus fourni', () {
      final realigned = realignPlayerPositionProfiles(
        identitiesByName: const {
          'jean petit': 'identite-unique',
          'jean grand': 'identite-unique',
        },
        archive: <String, PlayerPositionProfile>{
          'a': profile('Jean Petit', appearances: 4),
          'b': profile('Jean Grand', appearances: 40),
        },
      );

      expect(realigned.keys.single, 'identite-unique');
      expect(realigned['identite-unique']?.appearances, 40);
    });

    test('l’archive livrée reste cohérente avec elle-même', () {
      // Chaque profil porte un nom : sans nom, le réancrage serait aveugle.
      expect(
        kPlayerPositionProfiles.values
            .every((entry) => entry.displayName.trim().isNotEmpty),
        isTrue,
      );
    });
  });

  group('relabelPlayerPositionProfilesForDisplay', () {
    test('raccorde un surnom visible au profil de la même identité', () {
      final relabelled = relabelPlayerPositionProfilesForDisplay(
        profiles: <String, PlayerPositionProfile>{
          'luka-id': profile('Luka Brunel'),
          'milan-id': profile('Milan Couzin'),
        },
        displayNamesByPlayerId: const {
          'luka-id': 'Lulu',
          'milan-id': 'Pipo',
        },
      );

      final profilesByName = <String, PlayerPositionProfile>{
        for (final entry in relabelled.values)
          normalizePlayerName(entry.displayName): entry,
      };

      expect(profilesByName[normalizePlayerName('Lulu')], isNotNull);
      expect(profilesByName[normalizePlayerName('Pipo')], isNotNull);
      expect(relabelled['luka-id']?.appearances, 10);
      expect(relabelled['luka-id']?.mainSlotLabel, 'MDC');
    });

    test('ne relie jamais deux identités portant le même libellé visible', () {
      final original = <String, PlayerPositionProfile>{
        'alex-1': profile('Alex Martin'),
        'alex-2': profile('Alex Dupont'),
      };
      final relabelled = relabelPlayerPositionProfilesForDisplay(
        profiles: original,
        displayNamesByPlayerId: const {
          'alex-1': 'Alex',
          'alex-2': 'Alex',
        },
      );

      expect(relabelled, same(original));
      expect(relabelled['alex-1']?.displayName, 'Alex Martin');
      expect(relabelled['alex-2']?.displayName, 'Alex Dupont');
    });
  });
}
