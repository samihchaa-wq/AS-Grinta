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
  group('cloche des notifications de cet appareil', () {
    // Les notifications réglables ont aussi leur cloche : on ne regarde que
    // celle de l'encadré du haut.
    final essentialCard = find.ancestor(
      of: find.text('Notifications essentielles'),
      matching: find.byType(Card),
    );
    final activeBell = find.descendant(
      of: essentialCard,
      matching: find.byIcon(Icons.notifications_rounded),
    );
    final inactiveBell = find.descendant(
      of: essentialCard,
      matching: find.byIcon(Icons.notifications_none_rounded),
    );

    testWidgets('un appareil abonné affiche la cloche active', (tester) async {
      final repository = _FakePushSubscriptions(subscribed: true);
      await _pumpNotifications(tester, repository);

      expect(find.text('Notifications essentielles'), findsOneWidget);
      expect(activeBell, findsOneWidget);
      expect(inactiveBell, findsNothing);
    });

    testWidgets(
      'appuyer sur la cloche active désabonne et la passe en gris',
      (tester) async {
        final repository = _FakePushSubscriptions(subscribed: true);
        await _pumpNotifications(tester, repository);

        await tester.tap(activeBell);
        await tester.pumpAndSettle();

        expect(repository.disableCalls, 1);
        expect(repository.subscribed, isFalse);
        expect(
          find.text('Notifications désactivées sur cet appareil.'),
          findsOneWidget,
        );
        // Sans cette bascule, la cloche resterait verte alors que
        // l'appareil n'est plus abonné.
        expect(inactiveBell, findsOneWidget);
        expect(activeBell, findsNothing);
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

        await tester.tap(activeBell);
        await tester.pumpAndSettle();

        expect(repository.disableCalls, 1);
        expect(repository.subscribed, isTrue);
        expect(
          find.text('Impossible de désactiver les notifications.'),
          findsOneWidget,
        );
        // L'appareil est toujours abonné : la cloche ne doit pas prétendre
        // le contraire.
        expect(activeBell, findsOneWidget);
      },
    );

    testWidgets(
      'appuyer sur la cloche grise abonne et la passe en vert',
      (tester) async {
        final repository = _FakePushSubscriptions(subscribed: false);
        await _pumpNotifications(tester, repository);

        expect(inactiveBell, findsOneWidget);
        await tester.tap(inactiveBell);
        await tester.pumpAndSettle();

        expect(repository.enableCalls, 1);
        expect(activeBell, findsOneWidget);
        expect(inactiveBell, findsNothing);
      },
    );
  });

  testWidgets(
    'chaque notification réglable a sa cloche, verte une fois activée',
    (tester) async {
      await _pumpNotifications(
        tester,
        _FakePushSubscriptions(subscribed: true),
      );

      for (final title in const [
        'Rappel pronostic',
        'Vote Homme du match',
        'Composition en ligne',
        'Badge débloqué',
      ]) {
        final row = find.ancestor(
          of: find.text(title),
          matching: find.byType(Row),
        );
        expect(
          find.descendant(
            of: row.first,
            matching: find.byIcon(Icons.notifications_rounded),
          ),
          findsOneWidget,
          reason: title,
        );
      }
      expect(find.byType(Switch), findsNothing);
    },
  );

  group('coupure générale des notifications (administrateur)', () {
    late List<bool> pauseCalls;

    Future<void> pumpAdmin(WidgetTester tester) async {
      pauseCalls = [];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            setNotificationsPausedProvider.overrideWithValue(
              (enable) async => pauseCalls.add(enable),
            ),
            pushSubscriptionsRepositoryProvider.overrideWithValue(
              _FakePushSubscriptions(subscribed: true),
            ),
            pushStatusProvider.overrideWith(
              (ref) async => (supported: true, subscribed: true),
            ),
            appPreferencesProvider.overrideWith(
              (ref) async => const AppPreferences(),
            ),
            isAdminViewProvider.overrideWithValue(true),
            adminAvailabilityChangeNotificationProvider.overrideWith(
              (ref) async => true,
            ),
            notificationsPausedProvider.overrideWith((ref) async => false),
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

    Future<void> tapKillSwitch(WidgetTester tester) async {
      // La carte est en bas d'une liste construite à la demande.
      final title = find.text('Désactiver toutes les notifications');
      await tester.scrollUntilVisible(
        title,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      await tester.tap(title);
      await tester.pumpAndSettle();
    }

    testWidgets('annuler la confirmation ne coupe rien', (tester) async {
      await pumpAdmin(tester);
      await tapKillSwitch(tester);

      expect(
        find.text('Désactiver toutes les notifications ?'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
      await tester.pumpAndSettle();

      expect(find.text('Désactiver toutes les notifications ?'), findsNothing);
      expect(pauseCalls, isEmpty);
      expect(
        find.text('Toutes les notifications sont désactivées.'),
        findsNothing,
      );
    });

    testWidgets('confirmer coupe les notifications du club', (tester) async {
      await pumpAdmin(tester);
      await tapKillSwitch(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Tout désactiver'));
      await tester.pumpAndSettle();

      expect(pauseCalls, [true]);
      expect(
        find.text('Toutes les notifications sont désactivées.'),
        findsOneWidget,
      );
    });
  });
}
