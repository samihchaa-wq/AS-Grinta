import 'package:as_grinta/features/admin/presentation/admin_page.dart';
import 'package:as_grinta/features/live/presentation/live_gameplay_page.dart';
import 'package:as_grinta/features/live/presentation/live_page.dart';
import 'package:as_grinta/features/matches/presentation/match_form_page.dart';
import 'package:as_grinta/features/predictions/presentation/leaderboard_page.dart';
import 'package:as_grinta/features/predictions/presentation/season_predictions_page.dart';
import 'package:as_grinta/features/profile/presentation/profile_page.dart';
import 'package:as_grinta/features/statistics/presentation/statistics_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('critical V1 screens compile', () {
    const screens = <Widget>[
      AdminPage(),
      LivePage(matchId: 'compile-test'),
      LiveGameplayPage(matchId: 'compile-test'),
      MatchFormPage(),
      LeaderboardPage(),
      SeasonPredictionsPage(),
      ProfilePage(),
      StatisticsPage(),
    ];

    expect(screens.length, 8);
  });
}
