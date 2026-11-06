import 'package:as_grinta/features/matches/data/historical_match_detail_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Initiale du nom dans les compositions', () {
    test('l’entrée de composition lit l’initiale envoyée par le serveur', () {
      final entry = MatchCompositionEntry.fromJson({
        'participant_id': 'participant-1',
        'season_player_id': 'season-player-1',
        'display_name': 'Julien',
        'last_initial': 'C',
        'zone': 'field',
        'sort_order': 1,
      });

      expect(entry.displayName, 'Julien');
      expect(entry.lastInitial, 'C');
    });

    test('l’initiale suit le joueur quand on le déplace sur le terrain', () {
      final entry = MatchCompositionEntry.fromJson({
        'participant_id': 'participant-1',
        'display_name': 'Julien',
        'last_initial': 'D',
        'zone': 'available',
      }).moveTo(MatchCompositionZone.bench);

      expect(entry.lastInitial, 'D');
    });

    test('une composition sans initiale reste lisible', () {
      final entry = MatchCompositionEntry.fromJson({
        'participant_id': 'participant-1',
        'display_name': 'Aki',
        'zone': 'bench',
      });

      expect(entry.lastInitial, isNull);
    });

    test('un joueur d’archive garde l’initiale de son nom complet', () {
      const player = HistoricalFieldPlayer(
        name: 'Samuel',
        lastInitial: 'G',
        positionLabel: '',
        xPct: 50,
        yPct: 50,
        isGoalkeeper: false,
        photoUrl: null,
      );

      expect(player.lastInitial, 'G');
    });
  });
}
