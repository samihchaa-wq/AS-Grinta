import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/badges/data/badge_inbox_repository.dart';
import 'package:as_grinta/features/notifications/presentation/notifications_page.dart';
import 'package:as_grinta/features/preferences/data/preferences_repository.dart';
import 'package:as_grinta/features/preferences/data/push_subscriptions_repository.dart';
import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le navigateur ne sait ni s'abonner ni se désabonner dans un test : cette
/// doublure tient l'état de l'abonnement à sa place, et compte les appels
/// pour qu'un désabonnement rejoué ou oublié se voie.
class _FakePushSubscriptions implements PushSubscriptionsRepository {
  _FakePushSubscriptions({
    required this.subscribed,
    this.failOnDisable = false,
  });

  bool subscribed;
  final bool failOnDisable;
  int disableCalls = 0;
  int enableCalls = 0;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> isSubscribed() async => subscribed;

  @override
  Future<bool> enable() async {
    enableCalls += 1;
    subscribed = true;
    return true;
  }

  @override
  Future<void> disable() async {
    disableCalls += 1;
    if (failOnDisable) throw StateError('réseau indisponible');
    subscribed = false;
  }
}

Future<void> _pumpNotifications(
  WidgetTester tester,
  _FakePushSubscriptions repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pushSubscriptionsRepositoryProvider.overrideWithValue(repository),
        // Relit la doublure à chaque invalidation : c'est ce qui prouve que
        // la carte se met à jour après l'action, et pas seulement que
        // l'action a été appelée.
        pushStatusProvider.overrideWith(
          (ref) async => (supported: true, subscribed: repository.subscribed),
        ),
        appPreferencesProvider.overrideWith(
          (ref) async => const AppPreferences(),
        ),
        // Le reste de l'écran est réservé aux administrateurs : le garder
        // fermé isole la carte des notifications de cet appareil.
        isAdminViewProvider.overrideWithValue(false),
        // La barre du haut porte deux boutons qui interrogent le serveur.
        // Sans ces doublures, le test échouerait pour une raison sans rapport
        // avec le bouton qu'il vérifie.
        hasUnseenBadgeProvider.overrideWith((ref) async => false),
        seasonWrappedStateProvider.overrideWith(
          (ref) async => const SeasonWrappedState.unavailable(),
        ),
      ],
      child: const MaterialApp(home: NotificationsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('carte des notifications de cet appareil', () {
    testWidgets('un appareil abonné peut être désactivé', (tester) async {
      final repository = _FakePushSubscriptions(subscribed: true);
      await _pumpNotifications(tester, repository);

      expect(
        find.text('Notifications actives sur cet appareil'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Désactiver'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Activer'), findsNothing);
    });

    testWidgets(
      'appuyer sur Désactiver désabonne et bascule la carte',
      (tester) async {
        final repository = _FakePushSubscriptions(subscribed: true);
        await _pumpNotifications(tester, repository);

        await tester.tap(find.widgetWithText(TextButton, 'Désactiver'));
        await tester.pumpAndSettle();

        expect(repository.disableCalls, 1);
        expect(repository.subscribed, isFalse);
        expect(
          find.text('Notifications désactivées sur cet appareil.'),
          findsOneWidget,
        );
        // Sans cette bascule, le bouton resterait affiché alors que
        // l'appareil n'est plus abonné.
        expect(find.widgetWithText(TextButton, 'Activer'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Désactiver'), findsNothing);
      },
    );

    testWidgets(
      'un échec de désabonnement est annoncé, pas masqué',
      (tester) async {
        final repository = _FakePushSubscriptions(
          subscribed: true,
          failOnDisable: true,
        );
        await _pumpNotifications(tester, repository);

        await tester.tap(find.widgetWithText(TextButton, 'Désactiver'));
        await tester.pumpAndSettle();

        expect(repository.disableCalls, 1);
        expect(repository.subscribed, isTrue);
        expect(
          find.text('Impossible de désactiver les notifications.'),
          findsOneWidget,
        );
        // L'appareil est toujours abonné : la carte ne doit pas prétendre
        // le contraire.
        expect(find.widgetWithText(TextButton, 'Désactiver'), findsOneWidget);
      },
    );

    testWidgets(
      'un appareil non abonné garde le bouton d’activation',
      (tester) async {
        final repository = _FakePushSubscriptions(subscribed: false);
        await _pumpNotifications(tester, repository);

        expect(find.text('Notifications désactivées'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Activer'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Désactiver'), findsNothing);
      },
    );
  });
}
