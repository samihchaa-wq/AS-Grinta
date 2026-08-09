import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('season prediction form uses the atomic saveAll path', () {
    final source = File(
      'lib/features/predictions/presentation/season_prediction_entry_page.dart',
    ).readAsStringSync();

    expect(source, contains('repository.saveAll('));
    expect(source, isNot(contains('await repository.save(item.copyWith')));
  });

  test('repository exposes one RPC for the complete submission', () {
    final source = File(
      'lib/features/predictions/data/season_predictions_repository.dart',
    ).readAsStringSync();

    expect(source, contains("'save_my_season_predictions'"));
  });
}
