import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('season predictions use only the guarded batch RPC', () async {
    final repository = await File(
      'lib/features/predictions/data/season_predictions_repository.dart',
    ).readAsString();

    expect(repository, contains("'save_my_season_predictions'"));
    expect(repository, isNot(contains("from('season_predictions').upsert")));
    expect(
      repository,
      isNot(contains('Future<void> save(SeasonPredictionItem item)')),
    );
  });
}
