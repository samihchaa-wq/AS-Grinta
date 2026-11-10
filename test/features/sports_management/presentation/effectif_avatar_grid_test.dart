import 'dart:io';

import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('convocation player reads its profile photo', () {
    final player = ConvocationPlayer.fromJson({
      'participant_id': 'participant-1',
      'season_player_id': 'season-player-1',
      'first_name': 'Alban',
      'last_name': 'Test',
      'display_name': 'Alban',
      'photo_url': 'players/alban.webp',
      'availability_status': 'available',
      'convocation_status': 'convoked',
    });

    expect(player.photoUrl, 'players/alban.webp');
    expect(player.displayName, 'Alban');
  });

  test('effectif roster keeps three columns, photos and waitlist', () {
    final roster = File(
      'lib/features/sports_management/presentation/'
      'admin_squad_plan_effectif_roster.dart',
    ).readAsStringSync();
    final effectif = File(
      'lib/features/sports_management/presentation/'
      'admin_squad_plan_page_effectif.dart',
    ).readAsStringSync();
    final shared = File(
      'lib/features/sports_management/presentation/widgets/'
      'effectif_avatar_grid.dart',
    ).readAsStringSync();
    final playerBoard = File(
      'lib/features/sports_management/presentation/widgets/'
      'match_availability_board_card.dart',
    ).readAsStringSync();

    expect(shared, contains('static const int columns = 3;'));
    expect(shared, contains('PlayerAvatar('));
    expect(roster, contains('EffectifAvatarGrid('));
    expect(roster, contains('EffectifPlayerTile('));
    // L'effectif admin suit aussi le maillot du match (coach compris).
    expect(
      roster,
      contains('kitPhotos[player.seasonPlayerId] ?? player.photoUrl'),
    );
    expect(effectif, contains('matchKitPhotoOverridesProvider(matchId)'));
    expect(
      RegExp(r'kitPhotos: kitPhotos,').allMatches(effectif).length,
      greaterThanOrEqualTo(4),
    );
    // La vue des joueurs utilise les mêmes briques que celle des admins.
    expect(playerBoard, contains('EffectifAvatarGrid('));
    expect(playerBoard, contains('EffectifPlayerTile('));
    // Player-facing roster applies the kit-specific photo when available.
    expect(
      playerBoard,
      contains('kitPhotos[player.seasonPlayerId] ?? player.photoUrl'),
    );
    expect(playerBoard, contains('matchKitPhotoOverridesProvider(matchId)'));
    expect(playerBoard, contains('EffectifColumnsLayout('));
    expect(effectif, contains('EffectifColumnsLayout('));
    expect(effectif, contains("title: 'Liste d’attente'"));
    expect(
      RegExp(r'_EffectifAvatarColumn\(').allMatches(effectif).length,
      greaterThanOrEqualTo(4),
    );
  });
}
