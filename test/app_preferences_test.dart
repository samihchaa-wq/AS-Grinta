import 'package:as_grinta/features/preferences/data/preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copyWith conserve les préférences non modifiées', () {
    const preferences = AppPreferences(
      predictionOpen: true,
      predictionReminders: true,
      matchReminders: true,
    );

    final updated = preferences.copyWith(matchReminders: false);

    expect(updated.matchReminders, isFalse);
    expect(updated.predictionReminders, isTrue);
    expect(updated.predictionOpen, isTrue);
  });
}
