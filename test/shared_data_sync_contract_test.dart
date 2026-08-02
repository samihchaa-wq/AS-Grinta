import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'shared data sync reconnects and refreshes the main cached modules',
    () async {
      final sync =
          await File('lib/core/sync/shared_data_sync.dart').readAsString();
      final app = await File('lib/app/app.dart').readAsString();

      expect(sync, contains("from('shared_data_change_signals')"));
      expect(sync, contains(".eq('key', 'global')"));
      expect(sync, contains('const Duration(milliseconds: 350)'));

      for (final provider in <String>[
        'matchDetailsProvider',
        'matchInfoProvider',
        'inlineMatchPredictionProvider',
        'statisticsPeriodProvider',
        'teamStatisticsPeriodProvider',
        'leaderboardProvider',
        'adminDashboardProvider',
        'rosterProvider',
        'myArmoireProvider',
        'featuredBadgesProvider',
        'hasUnseenBadgeProvider',
        'myMatchAvailabilityProvider',
        'matchAvailabilityBoardProvider',
        'publishedMatchCompositionProvider',
        'publishedSportMatchResultProvider',
        'sportMotmVoteProvider',
      ]) {
        expect(
          sync,
          contains('invalidate($provider)'),
          reason: '$provider doit participer au refresh inter-modules',
        );
      }

      expect(sync, contains('matchesControllerProvider.notifier).load'));
      expect(sync, contains('predictionsControllerProvider.notifier).load'));
      expect(
        sync,
        contains('authControllerProvider.notifier).refreshProfile'),
      );

      expect(app, contains('ref.watch(sharedDataSyncListenerProvider);'));
      expect(app, contains('ref.invalidate(sharedDataSignalProvider);'));
      expect(
        app,
        contains('sharedDataRefreshCoordinatorProvider).refreshAll()'),
      );
    },
  );

  test(
    'shared data migration is a safe revision-only realtime channel',
    () async {
      final migration = await File(
        'supabase/migrations/20260803000000_shared_data_change_signal.sql',
      ).readAsString();

      expect(
        migration,
        contains(
          'create table if not exists public.shared_data_change_signals',
        ),
      );
      expect(
        migration,
        contains(
          'alter table public.shared_data_change_signals enable row level security',
        ),
      );
      expect(
        migration,
        contains('grant select on table public.shared_data_change_signals'),
      );
      expect(migration, contains('private.is_active_profile()'));
      expect(
        migration,
        contains(
          'for each statement execute function private.signal_shared_data_change()',
        ),
      );
      expect(migration, contains('alter publication supabase_realtime'));

      for (final table in <String>[
        'matches',
        'season_players',
        'profiles',
        'match_player_stats',
        'match_attendance',
        'profile_badges',
        'match_sport_participants',
        'match_sport_workflows',
        'match_sport_finalizations',
      ]) {
        expect(migration, contains("'$table'"));
      }
    },
  );
}
