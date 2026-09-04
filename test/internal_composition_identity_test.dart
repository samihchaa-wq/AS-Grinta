import 'package:as_grinta/features/sports_management/domain/internal_match_composition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InternalCompositionEntry.playerId', () {
    test('porte l’identité canonique d’un joueur de l’effectif', () {
      final entry = InternalCompositionEntry.fromJson(const {
        'participant_id': 'participant-1',
        'season_player_id': 'season-player-1',
        'player_id': 'canonical-1',
        'display_name': 'Steph',
      });

      expect(entry.playerId, 'canonical-1');
      expect(entry.isGuest, isFalse);
    });

    test('porte aussi celle d’un invité', () {
      final entry = InternalCompositionEntry.fromJson(const {
        'participant_id': 'participant-2',
        'guest_player_id': 'guest-1',
        'player_id': 'canonical-2',
        'display_name': 'Roman',
        'is_guest': true,
      });

      expect(entry.playerId, 'canonical-2');
      expect(entry.isGuest, isTrue);
    });

    test('reste nulle quand le serveur ne la renvoie pas encore', () {
      final entry = InternalCompositionEntry.fromJson(const {
        'participant_id': 'participant-3',
        'season_player_id': 'season-player-3',
        'display_name': 'Lulu',
      });

      expect(entry.playerId, isNull);
    });

    test('survit à une affectation d’équipe', () {
      final entry = InternalCompositionEntry.fromJson(const {
        'participant_id': 'participant-4',
        'season_player_id': 'season-player-4',
        'player_id': 'canonical-4',
        'display_name': 'Pipo',
      });

      expect(entry.copyWith(teamNo: 2).playerId, 'canonical-4');
      expect(entry.copyWith(clearTeam: true).playerId, 'canonical-4');
    });
  });
}
