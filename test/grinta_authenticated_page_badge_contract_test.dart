import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authenticated route screens keep the club home badge contract', () {
    const routedScreens = <String>[
      'lib/features/predictions/presentation/pronos_hub_page.dart',
      'lib/features/matches/presentation/match_details_page.dart',
      'lib/features/matches/presentation/historical_match_detail_page.dart',
      'lib/features/sports_management/presentation/match_lineup_page.dart',
      'lib/features/sports_management/presentation/sport_motm_vote_page.dart',
      'lib/features/sports_management/presentation/match_report_page.dart',
      'lib/features/matches/presentation/upcoming_match_prediction_page.dart',
      'lib/features/sports_management/presentation/admin_squad_plan_page_state.dart',
      'lib/features/sports_management/presentation/admin_guests_page.dart',
      'lib/features/admin/presentation/admin_page.dart',
      'lib/features/admin/presentation/opponent_stadium_library_page.dart',
      'lib/features/matches/presentation/matches_page.dart',
      'lib/features/sports_management/presentation/admin_waitlist_page.dart',
      'lib/features/badges/presentation/badge_admin_page.dart',
      'lib/features/admin/presentation/admin_notification_page.dart',
      'lib/features/more/presentation/more_page.dart',
      'lib/features/players/presentation/players_registry_page.dart',
      'lib/features/profile/presentation/profile_page.dart',
      'lib/features/privacy/presentation/privacy_page.dart',
      'lib/features/badges/presentation/armoire_page.dart',
      'lib/features/notifications/presentation/notifications_page.dart',
      'lib/features/statistics/presentation/stats_hub_page.dart',
      'lib/features/season_wrapped/presentation/season_wrapped_page.dart',
    ];

    for (final path in routedScreens) {
      final source = File(path).readAsStringSync();
      final hasSharedHeader = source.contains('GrintaAppBar(');
      final hasExplicitHomeBadge = source.contains('GrintaClubHomeButton(');
      expect(
        hasSharedHeader || hasExplicitHomeBadge,
        isTrue,
        reason: '$path doit afficher le badge club qui ramène au calendrier.',
      );
    }
  });
}
