import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('les éditions de match transmettent la version chargée', () {
    final repository = File('lib/features/matches/data/matches_repository.dart')
        .readAsStringSync();
    final controller = File(
      'lib/features/matches/presentation/matches_controller.dart',
    ).readAsStringSync();
    final form = File('lib/features/matches/presentation/match_form_page.dart')
        .readAsStringSync();

    expect(repository, contains("'p_expected_updated_at'"));
    expect(repository, contains('expectedUpdatedAt.toUtc().toIso8601String()'));
    expect(controller, contains('required DateTime? expectedUpdatedAt'));
    expect(controller, contains('expectedUpdatedAt: expectedUpdatedAt'));
    expect(form, contains('expectedUpdatedAt: widget.match!.updatedAt'));
  });
}
