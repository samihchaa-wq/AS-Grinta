import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Le comportement du chargement du calendrier (une seule requête à la fois,
/// copie en mémoire, affichage de la copie de l'appareil d'abord, copie propre
/// à chaque joueur, lectures parallèles, conservation de la disponibilité) est
/// vérifié par calendar_data_loading_test.dart,
/// match_availability_provider_test.dart et merged_matches_view_test.dart.
///
/// Restent ici les durées de conservation en mémoire : elles se mesurent avec
/// `DateTime.now()`, qu'un test ne peut pas avancer sans modifier le code de
/// l'application.
void main() {
  test('durées de conservation des copies en mémoire', () async {
    final history = await File(
      'lib/features/matches/data/calendar_history_repository.dart',
    ).readAsString();
    final events = await File(
      'lib/features/matches/data/club_events_repository.dart',
    ).readAsString();

    expect(history, contains('_allCacheTtl = Duration(minutes: 10)'));
    expect(events, contains('_cacheTtl = Duration(minutes: 2)'));
  });
}
