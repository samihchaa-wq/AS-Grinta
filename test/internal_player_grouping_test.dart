import 'package:as_grinta/features/sports_management/domain/internal_player_grouping.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerPositionProfile profile({
  required int appearances,
  required List<PlayerPositionSample> samples,
}) {
  return PlayerPositionProfile(
    displayName: 'Test',
    appearances: appearances,
    samples: samples,
    totalWeight: samples.fold<double>(0, (sum, sample) => sum + sample.weight),
  );
}

void main() {
  group('internalPlayerGroupFor', () {
    test('classe selon la moyenne pondérée des positions', () {
      expect(
        internalPlayerGroupFor(
          isGuest: false,
          isGoalkeeper: false,
          profile: profile(
            appearances: 8,
            samples: const [
              PlayerPositionSample('DG', 5),
              PlayerPositionSample('DCG', 3),
            ],
          ),
        ),
        InternalPlayerGroup.defenders,
      );
      expect(
        internalPlayerGroupFor(
          isGuest: false,
          isGoalkeeper: false,
          profile: profile(
            appearances: 8,
            samples: const [
              PlayerPositionSample('MDC', 4),
              PlayerPositionSample('MOC', 4),
            ],
          ),
        ),
        InternalPlayerGroup.midfielders,
      );
      expect(
        internalPlayerGroupFor(
          isGuest: false,
          isGoalkeeper: false,
          profile: profile(
            appearances: 8,
            samples: const [
              PlayerPositionSample('AG', 3),
              PlayerPositionSample('BU', 5),
            ],
          ),
        ),
        InternalPlayerGroup.attackers,
      );
    });

    test('un invité reste dans Autre, même avec tout un passé au poste', () {
      expect(
        internalPlayerGroupFor(
          isGuest: true,
          isGoalkeeper: false,
          profile: profile(
            appearances: 50,
            samples: const [PlayerPositionSample('MDC', 50)],
          ),
        ),
        InternalPlayerGroup.other,
      );
    });

    test('un poste principal sous 30 % ne suffit pas à classer', () {
      // Le meilleur poste ne pèse que 25 % : le ranger sous une ligne
      // afficherait une certitude que l'historique n'a pas.
      expect(
        internalPlayerGroupFor(
          isGuest: false,
          isGoalkeeper: false,
          profile: profile(
            appearances: 20,
            samples: const [
              PlayerPositionSample('MOD', 5),
              PlayerPositionSample('DCG', 4),
              PlayerPositionSample('MDC', 4),
              PlayerPositionSample('DCD', 4),
              PlayerPositionSample('DG', 3),
            ],
          ),
        ),
        InternalPlayerGroup.other,
      );
    });

    test('juste au-dessus de 30 %, le classement reprend', () {
      expect(
        internalPlayerGroupFor(
          isGuest: false,
          isGoalkeeper: false,
          profile: profile(
            appearances: 20,
            samples: const [
              PlayerPositionSample('MDC', 31),
              PlayerPositionSample('MDG', 25),
              PlayerPositionSample('MCD', 24),
              PlayerPositionSample('MC', 20),
            ],
          ),
        ),
        InternalPlayerGroup.midfielders,
      );
    });

    test('un gardien reste dans Autre', () {
      expect(
        internalPlayerGroupFor(
          isGuest: false,
          isGoalkeeper: true,
          profile: profile(
            appearances: 30,
            samples: const [PlayerPositionSample('GB', 30)],
          ),
        ),
        InternalPlayerGroup.other,
      );
    });

    test('un joueur avec trop peu de matchs reste dans Autre', () {
      expect(
        internalPlayerGroupFor(
          isGuest: false,
          isGoalkeeper: false,
          profile: profile(
            appearances: kMinimumInternalPositionAppearances - 1,
            samples: const [PlayerPositionSample('BU', 2)],
          ),
        ),
        InternalPlayerGroup.other,
      );
      expect(
        internalPlayerGroupFor(
            isGuest: false, isGoalkeeper: false, profile: null),
        InternalPlayerGroup.other,
      );
    });

    test('ignore les passages au but dans la moyenne d’un joueur de champ', () {
      expect(
        internalPlayerGroupFor(
          isGuest: false,
          isGoalkeeper: false,
          profile: profile(
            appearances: 6,
            samples: const [
              PlayerPositionSample('GB', 4),
              PlayerPositionSample('BU', 2),
            ],
          ),
        ),
        InternalPlayerGroup.attackers,
      );
    });
  });
}
