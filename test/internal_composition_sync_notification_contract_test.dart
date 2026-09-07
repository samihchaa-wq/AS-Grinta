import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const migrationPath = 'supabase/migrations/'
      '20260907223000_internal_composition_sync_first_visual_notification.sql';
  const exactRosterMigrationPath = 'supabase/migrations/'
      '20260907223100_internal_composition_exact_roster_sync.sql';

  test('le joueur ne reçoit jamais la vue papier avant le terrain validé', () {
    final widget = File(
      'lib/features/sports_management/presentation/widgets/'
      'internal_team_composition_view.dart',
    ).readAsStringSync();
    final migration = File(migrationPath).readAsStringSync();

    expect(widget, contains('if (!widget.editable) _viewMode = 1;'));
    expect(widget, contains('if (widget.editable) ...['));
    expect(widget, contains("label: Text('Sur papier')"));
    expect(widget, contains("label: Text('Sur terrain')"));

    expect(
      migration,
      contains('v_can_see_assignments := public.is_match_staff()'),
    );
    expect(
      migration,
      contains(
          'or private.internal_composition_visual_is_complete(p_match_id)'),
    );
    expect(
      migration,
      contains('when v_can_see_assignments then entry.team_no else null'),
    );
  });

  test('effectif, papier et terrain partagent le même effectif convoqué', () {
    final migration = File(migrationPath).readAsStringSync();
    final exactRosterMigration =
        File(exactRosterMigrationPath).readAsStringSync();

    expect(migration,
        contains('from public.match_sport_participants participant'));
    expect(
      migration,
      contains("participant.convocation_status = 'convoked'"),
    );
    expect(
      migration,
      contains('v_stored <> v_expected'),
    );
    expect(
      migration,
      contains('private.internal_default_formation_code(v_team1_count)'),
    );
    expect(
      migration,
      contains('private.internal_default_formation_code(v_team2_count)'),
    );
    expect(
      exactRosterMigration,
      contains('participant.id = entry.participant_id'),
    );
    expect(
      exactRosterMigration,
      contains("participant.convocation_status = 'convoked'"),
    );
    expect(
      exactRosterMigration,
      contains('and not exists ('),
    );
  });

  test('seul le premier enregistrement terrain peut notifier', () {
    final repository = File(
      'lib/features/sports_management/data/'
      'internal_match_composition_repository.dart',
    ).readAsStringSync();
    final migration = File(migrationPath).readAsStringSync();

    expect(repository, contains("'admin_save_internal_composition_v5'"));
    expect(repository, contains('requireVisualComplete: false'));

    expect(
      migration,
      contains("'as_grinta.internal_visual_publish'"),
    );
    expect(
      migration,
      contains('pg_catalog.current_setting('),
    );
    expect(
      migration,
      contains('on conflict (match_id, kind) do nothing'),
    );
    expect(migration, contains("then 'Compositions faites'"));
  });

  test('le push entre nous vise tous les profils actifs abonnés', () {
    final migration = File(migrationPath).readAsStringSync();

    expect(migration, contains('from public.profiles profile'));
    expect(migration, contains("profile.status = 'active'"));
    expect(migration, contains('profile.notify_composition'));
  });
}
