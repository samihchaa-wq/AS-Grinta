import 'dart:io';

import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the immediate published convocation state', () {
    final convocations = MatchConvocations.fromRpc({
      'match_id': 'match-1',
      'opponent_name': 'Contrat FC',
      'kickoff_at': '2026-08-01T18:00:00Z',
      'season_id': 'season-1',
      'squad_size_limit': 15,
      'published_squad_size_limit': 15,
      'convocation_state': 'published',
      'convocation_version': 3,
      'has_unpublished_changes': false,
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
          'published_convocation_status': 'convoked',
          'manual_override': true,
          'recommended_not_convoked': false,
          'turn_should_consume': false,
          'turn_state': 'waived',
        },
      ],
    });

    expect(convocations.squadSizeLimit, 15);
    expect(convocations.publishedSquadSizeLimit, 15);
    expect(convocations.hasUnpublishedChanges, isFalse);
    expect(convocations.isReadyForComposition, isTrue);
    expect(convocations.players.single.isConvoked, isTrue);
    expect(
      convocations.players.single.publishedConvocationStatus,
      ConvocationStatus.convoked,
    );
    expect(
      convocations.players.single.hasUnpublishedConvocationChange,
      isFalse,
    );
  });

  test('the admin flow has one save button and no draft or publication step', () {
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

    expect(effectifSource, isNot(contains('Enregistrer le brouillon')));
    expect(effectifSource, isNot(contains('Enregistrer les convocations')));
    expect(effectifSource, contains("label: const Text('Enregistrer')"));
    expect(
      effectifSource,
      contains('jusqu’à ce que tu appuies sur Enregistrer'),
    );
    expect(effectifSource, contains('.publishEffectif('));
    expect(repositorySource, contains("'admin_publish_match_effectif'"));

    expect(compositionSource, contains("label: const Text('Enregistrer')"));
    expect(compositionSource, contains('puis appuie sur Enregistrer'));
    expect(
      compositionSource,
      isNot(contains("label: const Text('Publier la composition')")),
    );
    expect(
      compositionSource,
      isNot(
        contains(
          'Les convocations ne seront pas modifiées par cette action.',
        ),
      ),
    );
  });
}
