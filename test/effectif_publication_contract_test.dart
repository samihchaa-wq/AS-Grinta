import 'dart:io';

import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses separate draft and published convocation states', () {
    final convocations = MatchConvocations.fromRpc({
      'match_id': 'match-1',
      'opponent_name': 'Contrat FC',
      'kickoff_at': '2026-08-01T18:00:00Z',
      'season_id': 'season-1',
      'squad_size_limit': 15,
      'published_squad_size_limit': 14,
      'convocation_state': 'published',
      'convocation_version': 2,
      'has_unpublished_changes': true,
      'available_count': 1,
      'convoked_count': 1,
      'not_convoked_count': 0,
      'players': [
        {
          'participant_id': 'participant-1',
          'season_player_id': 'player-1',
          'first_name': 'Alex',
          'last_name': 'Grinta',
          'availability_status': 'available',
          'convocation_status': 'convoked',
          'published_convocation_status': 'not_convoked',
          'manual_override': true,
          'recommended_not_convoked': false,
          'turn_should_consume': false,
          'turn_state': 'waived',
        },
      ],
    });

    expect(convocations.squadSizeLimit, 15);
    expect(convocations.publishedSquadSizeLimit, 14);
    expect(convocations.hasUnpublishedChanges, isTrue);
    expect(convocations.isReadyForComposition, isFalse);
    expect(convocations.players.single.hasUnpublishedConvocationChange, isTrue);
  });

  // Garde le contrat d’interface séparé du détail d’implémentation Supabase.
  test(
    'the admin flow keeps effectif and composition publications separate',
    () {
      final effectifSource = File(
        'lib/features/sports_management/presentation/'
        'admin_squad_plan_page_effectif.dart',
      ).readAsStringSync();
      final compositionSource = File(
        'lib/features/sports_management/presentation/'
        'admin_squad_plan_page_composition.dart',
      ).readAsStringSync();
      final repositorySource = File(
        'lib/features/sports_management/data/sport_waitlist_repository.dart',
      ).readAsStringSync();

      expect(effectifSource, contains('Enregistrer le brouillon'));
      expect(effectifSource, contains('Publier les convocations'));
      expect(effectifSource, contains('.publishEffectif('));
      expect(repositorySource, contains("'admin_publish_match_effectif'"));
      expect(compositionSource, isNot(contains('.publishMatch(')));
      expect(
        compositionSource,
        contains('Les convocations ne seront pas modifiées par cette action.'),
      );
    },
  );
}
