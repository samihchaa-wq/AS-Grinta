import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'season prediction writes stay local until the season is locked',
    () async {
      final databaseContract = await File(
        'supabase/tests/database/season_prediction_refresh_signal.test.sql',
      ).readAsString();
      final entryPage = await File(
        'lib/features/predictions/presentation/season_prediction_entry_page.dart',
      ).readAsString();

      // Le comportement serveur est exercé par la suite pgTAP sur la base
      // reconstruite. Ce test Flutter vérifie que ce contrat reste présent sans
      // dépendre de la représentation historique des migrations.
      expect(
        databaseContract,
        contains(
          'enregistrer un prono de saison ne déclenche plus le refresh global',
        ),
      );
      expect(
        databaseContract,
        contains(
          'modifier un prono de saison ne déclenche plus le refresh global',
        ),
      );
      expect(
        databaseContract,
        contains(
          'les changements de saison continuent de déclencher le refresh global',
        ),
      );

      // Le joueur voit immédiatement ses valeurs sauvegardées sans dépendre du
      // signal global : la page recharge explicitement son propre provider.
      expect(entryPage, contains('ref.invalidate(seasonPredictionsProvider);'));
      expect(
        entryPage,
        contains('await ref.read(seasonPredictionsProvider.future);'),
      );
    },
  );
}
