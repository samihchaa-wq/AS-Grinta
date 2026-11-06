import 'package:as_grinta/features/notifications/presentation/push_device_banner.dart';
import 'package:as_grinta/features/preferences/data/push_subscriptions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Le navigateur ne sait pas s'abonner dans un test : la doublure tient
/// l'état de l'abonnement de cet appareil.
class _FakePushSubscriptions implements PushSubscriptionsRepository {
  _FakePushSubscriptions({this.subscribed = false, this.allow = true});

  bool subscribed;
  final bool allow;
  int enableCalls = 0;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> isSubscribed() async => subscribed;

  @override
  Future<bool> resync() async => subscribed;

  @override
  Future<bool> enable() async {
    enableCalls += 1;
    if (!allow) return false;
    subscribed = true;
    await writePushOptOut(false);
    return true;
  }

  @override
  Future<void> disable() async => subscribed = false;
}

Future<void> _pump(
  WidgetTester tester,
  _FakePushSubscriptions repository, {
  PushDeviceAlert? forcedAlert,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pushSubscriptionsRepositoryProvider.overrideWithValue(repository),
        // Relit la doublure à chaque invalidation, comme la vraie cloche.
        pushStatusProvider.overrideWith(
          (ref) async => (supported: true, subscribed: repository.subscribed),
        ),
        if (forcedAlert != null)
          pushDeviceAlertProvider.overrideWith((ref) async => forcedAlert),
      ],
      child: const MaterialApp(
        home: Scaffold(body: Column(children: [PushDeviceBanner()])),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'un appareil désabonné sans l’avoir choisi est signalé, et réabonné en '
    'un geste',
    (tester) async {
      final repository = _FakePushSubscriptions();
      await _pump(tester, repository);

      expect(find.text('Notifications désactivées'), findsOneWidget);

      await tester.tap(find.text('Activer'));
      await tester.pumpAndSettle();

      expect(repository.enableCalls, 1);
      expect(find.text('Notifications désactivées'), findsNothing);
      expect(
        find.text('Notifications activées sur cet appareil.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('un appareil qui reçoit n’affiche rien', (tester) async {
    await _pump(tester, _FakePushSubscriptions(subscribed: true));

    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('« Non merci » est retenu sur cet appareil', (tester) async {
    final repository = _FakePushSubscriptions();
    await _pump(tester, repository);

    await tester.tap(find.text('Non merci'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications désactivées'), findsNothing);
    expect(await readPushOptOut(), isTrue);
    expect(repository.enableCalls, 0);

    // Réouverture de l'application : le choix tient toujours.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, repository);
    expect(find.text('Notifications désactivées'), findsNothing);
  });

  testWidgets(
    'un refus du téléphone est annoncé au lieu d’un faux succès',
    (tester) async {
      final repository = _FakePushSubscriptions(allow: false);
      await _pump(tester, repository);

      await tester.tap(find.text('Activer'));
      await tester.pumpAndSettle();

      expect(repository.subscribed, isFalse);
      expect(
        find.textContaining('Notifications bloquées sur ce téléphone'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'un téléphone qui bloque l’affichage le dit, et le redit tant qu’il '
    'bloque',
    (tester) async {
      await _pump(
        tester,
        _FakePushSubscriptions(),
        forcedAlert: PushDeviceAlert.blocked,
      );

      expect(find.text('Notifications bloquées'), findsOneWidget);
      expect(find.text('Activer'), findsNothing);

      await tester.tap(find.text('C’est fait'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Toujours bloquées'), findsOneWidget);
    },
  );
}
