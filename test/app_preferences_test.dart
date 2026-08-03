import 'package:as_grinta/features/preferences/data/preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copyWith conserve les préférences non modifiées', () {
    const preferences = AppPreferences(
      predictionNotifications: true,
      motmVoteNotifications: true,
      convocationNotifications: true,
    );

    final updated = preferences.copyWith(convocationNotifications: false);

    expect(updated.convocationNotifications, isFalse);
    expect(updated.motmVoteNotifications, isTrue);
    expect(updated.predictionNotifications, isTrue);
  });
}
