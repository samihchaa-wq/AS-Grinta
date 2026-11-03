import 'package:as_grinta/features/match_live/data/match_live_notification_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingRepository implements MatchLiveNotificationRepository {
  _CountingRepository(this.opensAt);

  final DateTime opensAt;
  int fetchCount = 0;

  @override
  Future<MatchLiveNotificationStatus> fetchStatus(String matchId) async {
    fetchCount++;
    return MatchLiveNotificationStatus(
      eligible: false,
      subscribed: false,
      opensAt: opensAt,
    );
  }

  @override
  Future<MatchLiveNotificationStatus> setEnabled({
    required String matchId,
    required bool enabled,
  }) =>
      throw UnimplementedError();
}

void main() {
  final now = DateTime.utc(2026, 11, 3, 12);

  MatchLiveNotificationStatus closed(DateTime? opensAt) =>
      MatchLiveNotificationStatus(
        eligible: false,
        subscribed: false,
        opensAt: opensAt,
      );

  group('matchLiveNotificationRecheckDelay', () {
    test('ouverture proche : attend juste après l’ouverture', () {
      expect(
        matchLiveNotificationRecheckDelay(
          closed(now.add(const Duration(minutes: 10))),
          now,
        ),
        const Duration(minutes: 10, seconds: 1),
      );
    });

    test('match lointain : jamais plus de 12 h (le Web déborde à 24,8 j)', () {
      expect(
        matchLiveNotificationRecheckDelay(
          closed(now.add(const Duration(days: 40))),
          now,
        ),
        matchLiveNotificationMaxRecheckDelay,
      );
    });

    test('déjà ouvert, éligible ou sans date : aucune relecture', () {
      expect(
        matchLiveNotificationRecheckDelay(
          closed(now.subtract(const Duration(hours: 1))),
          now,
        ),
        isNull,
      );
      expect(matchLiveNotificationRecheckDelay(closed(null), now), isNull);
      expect(
        matchLiveNotificationRecheckDelay(
          MatchLiveNotificationStatus(
            eligible: true,
            subscribed: false,
            opensAt: now.add(const Duration(days: 2)),
          ),
          now,
        ),
        isNull,
      );
    });
  });

  // Ce test reproduit la panne réelle quand il tourne dans un navigateur
  // (`flutter test --platform chrome`) : avant le correctif, un match ouvrant
  // dans 40 jours relançait la requête des centaines de fois par seconde.
  test('un match lointain n’est lu qu’une fois, même affiché longtemps',
      () async {
    final repository = _CountingRepository(
      DateTime.now().add(const Duration(days: 40)),
    );
    final container = ProviderContainer(
      overrides: [
        matchLiveNotificationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final subscription = container.listen(
      matchLiveNotificationStatusProvider('match-lointain'),
      (_, __) {},
    );
    addTearDown(subscription.close);

    await Future<void>.delayed(const Duration(seconds: 2));
    expect(repository.fetchCount, 1);
  });
}
