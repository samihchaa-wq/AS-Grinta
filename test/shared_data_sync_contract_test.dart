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
      expect(sync, contains('sportsRevision'));
      expect(sync, contains('SharedDataRefreshScope.sports'));
      expect(
        sync,
        contains('refreshProfile: shouldRefreshProfile'),
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
      final scopedSportsMigration = await File(
        'supabase/migrations/20260804223000_scope_sports_refresh_signal.sql',
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

      expect(scopedSportsMigration, contains('sports_revision'));
      expect(
        scopedSportsMigration,
        contains("'match_sport_participants'"),
      );
      expect(
        scopedSportsMigration,
        contains("'match_composition_publications'"),
      );
      expect(
        scopedSportsMigration,
        contains('sports_revision <= revision'),
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

  test('sports-only signals select the targeted refresh', () {
    final cursor = SharedDataSignalCursor();

    expect(
      cursor.register(
        _signal(revision: 10, profileRevision: 4, sportsRevision: 6),
      ),
      isNull,
    );

    final sportsDecision = cursor.register(
      _signal(revision: 11, profileRevision: 4, sportsRevision: 7),
    );
    expect(sportsDecision?.scope, SharedDataRefreshScope.sports);
    expect(sportsDecision?.refreshProfile, isFalse);
  });

  test('mixed or profile signals preserve the global refresh', () {
    final cursor = SharedDataSignalCursor();

    expect(
      cursor.register(
        _signal(revision: 20, profileRevision: 8, sportsRevision: 10),
      ),
      isNull,
    );

    final mixedDecision = cursor.register(
      _signal(revision: 22, profileRevision: 8, sportsRevision: 11),
    );
    expect(mixedDecision?.scope, SharedDataRefreshScope.all);
    expect(mixedDecision?.refreshProfile, isFalse);

    final profileDecision = cursor.register(
      _signal(revision: 23, profileRevision: 9, sportsRevision: 11),
    );
    expect(profileDecision?.scope, SharedDataRefreshScope.all);
    expect(profileDecision?.refreshProfile, isTrue);
    expect(
      cursor.register(
        _signal(revision: 23, profileRevision: 9, sportsRevision: 11),
      ),
      isNull,
    );
  });

  test('legacy signal rows preserve the previous refresh behavior', () {
    final signal = SharedDataChangeSignal.fromRow({
      'revision': 27,
      'updated_at': '2026-08-04T17:20:00Z',
    });

    expect(signal.profileRevision, signal.revision);
    expect(signal.sportsRevision, 0);

    final cursor = SharedDataSignalCursor();
    expect(cursor.register(signal), isNull);
    final next = cursor.register(
      SharedDataChangeSignal.fromRow({
        'revision': 28,
        'updated_at': '2026-08-04T17:21:00Z',
      }),
    );
    expect(next?.scope, SharedDataRefreshScope.all);
    expect(next?.refreshProfile, isTrue);
  });
}

SharedDataChangeSignal _signal({
  required int revision,
  required int profileRevision,
  required int sportsRevision,
}) {
  return SharedDataChangeSignal(
    revision: revision,
    profileRevision: profileRevision,
    sportsRevision: sportsRevision,
    updatedAt: DateTime.utc(2026, 8, 4),
  );
}
