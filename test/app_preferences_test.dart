import 'package:as_grinta/features/preferences/data/preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copyWith conserve les préférences non modifiées', () {
    const preferences = AppPreferences(
      matchReminders: true,
      predictionReminders: true,
    );

    final updated = preferences.copyWith(matchReminders: false);

    expect(updated.matchReminders, isFalse);
    expect(updated.predictionReminders, isTrue);
  });
}
