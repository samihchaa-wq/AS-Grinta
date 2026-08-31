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

    expect(roster, contains('static const int _columns = 3;'));
    expect(roster, contains('PlayerAvatar('));
    expect(roster, contains('photoUrl: player.photoUrl'));
    expect(effectif, contains("title: 'Liste d’attente'"));
    expect(
      RegExp(r'_EffectifAvatarColumn\(').allMatches(effectif).length,
      greaterThanOrEqualTo(4),
    );
  });
}
