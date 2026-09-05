import 'package:as_grinta/features/preferences/data/preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copyWith conserve les préférences non modifiées', () {
    const preferences = AppPreferences(
      predictionNotifications: true,
      motmVoteNotifications: true,
      convocationNotifications: true,
      compositionNotifications: true,
    );

    final updated = preferences.copyWith(convocationNotifications: false);

    expect(updated.convocationNotifications, isFalse);
    expect(updated.motmVoteNotifications, isTrue);
    expect(updated.predictionNotifications, isTrue);
    expect(updated.compositionNotifications, isTrue);
  });

  test('la notification de composition se coupe sans toucher aux autres', () {
    const preferences = AppPreferences();

    final updated = preferences.copyWith(compositionNotifications: false);

    expect(updated.compositionNotifications, isFalse);
    expect(updated.convocationNotifications, isTrue);
    expect(updated.motmVoteNotifications, isTrue);
    expect(updated.predictionNotifications, isTrue);
  });

  test('chaque notification est active tant que le joueur n’y touche pas', () {
    const preferences = AppPreferences();

    expect(preferences.compositionNotifications, isTrue);
    expect(preferences.convocationNotifications, isTrue);
    expect(preferences.motmVoteNotifications, isTrue);
    expect(preferences.predictionNotifications, isTrue);
  });
}
