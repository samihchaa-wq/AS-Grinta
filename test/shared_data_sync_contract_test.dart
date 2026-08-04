import 'dart:io';

import 'package:as_grinta/core/sync/shared_data_sync.dart';
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
      expect(sync, contains('profileRevision'));
      expect(
        sync,
        contains('refreshAll(refreshProfile: shouldRefreshProfile)'),
      );

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
      final scopedProfileMigration = await File(
        'supabase/migrations/20260804220000_scope_profile_refresh_signal.sql',
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

      expect(scopedProfileMigration, contains('profile_revision'));
      expect(
        scopedProfileMigration,
        contains("tg_table_name = 'profiles'"),
      );
      expect(
        scopedProfileMigration,
        contains('profile_revision <= revision'),
      );

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

  test('non-profile signals skip only the profile refresh', () {
    final cursor = SharedDataSignalCursor();

    expect(cursor.register(_signal(revision: 10, profileRevision: 4)), isNull);
    expect(cursor.register(_signal(revision: 11, profileRevision: 4)), isFalse);
    expect(cursor.register(_signal(revision: 12, profileRevision: 5)), isTrue);
    expect(cursor.register(_signal(revision: 12, profileRevision: 5)), isNull);
  });

  test('legacy signal rows preserve the previous refresh behavior', () {
    final signal = SharedDataChangeSignal.fromRow({
      'revision': 27,
      'updated_at': '2026-08-04T17:20:00Z',
    });

    expect(signal.profileRevision, signal.revision);
  });
}

SharedDataChangeSignal _signal({
  required int revision,
  required int profileRevision,
}) {
  return SharedDataChangeSignal(
    revision: revision,
    profileRevision: profileRevision,
    updatedAt: DateTime.utc(2026, 8, 4),
  );
}
