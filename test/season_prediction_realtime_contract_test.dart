import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('season prediction writes stay local until the season is locked', () async {
    final migration = await File(
      'supabase/migrations/20260804230000_suppress_season_prediction_refresh_signal.sql',
    ).readAsString();
    final entryPage = await File(
      'lib/features/predictions/presentation/season_prediction_entry_page.dart',
    ).readAsString();

    expect(
      migration,
      contains(
        "if tg_table_schema = 'public' and tg_table_name = 'season_predictions' then\n    return null;\n  end if;",
      ),
    );
    expect(migration, contains("tg_table_name = 'profiles'"));
    expect(migration, contains("'match_sport_participants'"));
    expect(migration, contains('profile_revision'));
    expect(migration, contains('sports_revision'));
    expect(migration, isNot(contains('drop trigger')));

    // Le joueur voit immédiatement ses valeurs sauvegardées sans dépendre du
    // signal global : la page recharge explicitement son propre provider.
    expect(entryPage, contains('ref.invalidate(seasonPredictionsProvider);'));
    expect(
      entryPage,
      contains('await ref.read(seasonPredictionsProvider.future);'),
    );
  });
}
