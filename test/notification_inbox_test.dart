import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/badges/data/badge_inbox_repository.dart';
import 'package:as_grinta/features/notifications/data/notification_inbox_repository.dart';
import 'package:as_grinta/features/notifications/presentation/notification_history_view.dart';
import 'package:as_grinta/features/notifications/presentation/notification_inbox_button.dart';
import 'package:as_grinta/features/notifications/presentation/notifications_page.dart';
import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Historique en mémoire, qui note ce que l'écran lui demande.
class _FakeInbox implements NotificationInboxRepository {
  _FakeInbox(this.entries);

  List<NotificationHistoryEntry> entries;
  int markAllReadCalls = 0;
  final List<int> deleted = [];
  bool failDelete = false;
  Object? fetchError;

  @override
  Future<List<NotificationHistoryEntry>> fetchHistory() async {
    final error = fetchError;
    if (error != null) throw error;
    return List.of(entries);
  }

  @override
  Future<int> unreadCount() async =>
      entries.where((entry) => entry.unread).length;

  @override
  Future<int> markAllRead() async {
    markAllReadCalls += 1;
    final now = DateTime(2026, 10, 14, 18);
    var marked = 0;
    entries = [
      for (final entry in entries)
        if (entry.unread)
          () {
            marked += 1;
            return NotificationHistoryEntry(
              id: entry.id,
              kind: entry.kind,
              title: entry.title,
              body: entry.body,
              createdAt: entry.createdAt,
              matchId: entry.matchId,
              url: entry.url,
              readAt: now,
            );
          }()
        else
          entry,
    ];
    return marked;
  }

  @override
  Future<void> delete(int id) async {
    if (failDelete) {
      throw StateError('La notification n’a pas pu être supprimée.');
    }
    deleted.add(id);
    entries = entries.where((entry) => entry.id != id).toList();
  }
}

NotificationHistoryEntry _entry(
  int id,
  String title, {
  bool unread = false,
  String? url,
  int minutesAgo = 0,
}) {
  final createdAt = DateTime(2026, 10, 14, 17).subtract(
    Duration(minutes: minutesAgo),
  );
  return NotificationHistoryEntry(
    id: id,
    kind: 'availability_open',
    title: title,
    body: 'Corps de $title',
    createdAt: createdAt,
    url: url,
    readAt: unread ? null : createdAt,
  );
}

Future<GoRouter> _pumpHistory(WidgetTester tester, _FakeInbox inbox) async {
  final router = GoRouter(
    initialLocation: '/notifications',
    routes: [
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const Scaffold(body: NotificationHistoryView()),
      ),
      GoRoute(
        path: '/matches',
        builder: (_, state) => Scaffold(
          body: Text('Calendrier ${state.uri.queryParameters['match'] ?? ''}'),
        ),
      ),
      GoRoute(
        path: '/matches/:id/vote',
        builder: (_, state) =>
            Scaffold(body: Text('Vote ${state.pathParameters['id']}')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationInboxRepositoryProvider.overrideWithValue(inbox),
        unreadNotificationCountProvider.overrideWith(
          (ref) => ref.watch(notificationInboxRepositoryProvider).unreadCount(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('route ouverte par une notification', () {
    test('les adresses du serveur deviennent des routes', () {
      expect(notificationRoute('matches/abc/vote'), '/matches/abc/vote');
      expect(notificationRoute('matches?match=abc'), '/matches?match=abc');
      expect(notificationRoute('#/armoire'), '/armoire');
      expect(
          notificationRoute('/admin/administration'), '/admin/administration');
      expect(notificationRoute('.'), '/matches');
      expect(notificationRoute(''), '/matches');
      expect(notificationRoute(null), isNull);
      expect(notificationRoute('https://exemple.invalid/x'), isNull);
    });
  });

  group('cloche de l’en-tête', () {
    Future<void> pumpBell(WidgetTester tester, int unread) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unreadNotificationCountProvider.overrideWith((ref) async => unread),
          ],
          child: const MaterialApp(
            home: Scaffold(body: Center(child: NotificationInboxButton())),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sans notification non lue, pas de chiffre', (tester) async {
      await pumpBell(tester, 0);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      expect(
        find.byKey(const ValueKey('notification-unread-pill')),
        findsNothing,
      );
    });

    testWidgets('affiche le nombre de non-lues', (tester) async {
      await pumpBell(tester, 3);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('notification-unread-pill')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('au-delà de 9, affiche 9+', (tester) async {
      await pumpBell(tester, 12);
      expect(find.text('9+'), findsOneWidget);
      expect(find.text('12'), findsNothing);
    });

    testWidgets('ouvre l’écran des notifications', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) =>
                const Scaffold(body: Center(child: NotificationInboxButton())),
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, __) =>
                const Scaffold(body: Text('Écran notifications')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unreadNotificationCountProvider.overrideWith((ref) async => 1),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('notification-inbox-button')));
      await tester.pumpAndSettle();
      expect(find.text('Écran notifications'), findsOneWidget);
    });
  });

  group('historique', () {
    testWidgets(
      'la plus récente en premier ; ouvrir l’écran marque tout comme lu',
      (tester) async {
        final inbox = _FakeInbox([
          _entry(2, 'Récente', unread: true, minutesAgo: 1),
          _entry(1, 'Ancienne', minutesAgo: 60),
        ]);
        await _pumpHistory(tester, inbox);

        final recent = tester.getTopLeft(find.text('Récente'));
        final old = tester.getTopLeft(find.text('Ancienne'));
        expect(recent.dy, lessThan(old.dy));
        expect(inbox.markAllReadCalls, 1);
        expect(inbox.entries.every((entry) => !entry.unread), isTrue);
      },
    );

    testWidgets('glisser vers la gauche supprime la notification', (
      tester,
    ) async {
      final inbox = _FakeInbox([_entry(1, 'À supprimer'), _entry(2, 'Garde')]);
      await _pumpHistory(tester, inbox);

      await tester.drag(find.text('À supprimer'), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.text('À supprimer'), findsNothing);
      expect(find.text('Garde'), findsOneWidget);
      expect(inbox.deleted, [1]);
    });

    testWidgets('un échec de suppression remet la ligne et le dit', (
      tester,
    ) async {
      final inbox = _FakeInbox([_entry(1, 'Reste là')])..failDelete = true;
      await _pumpHistory(tester, inbox);

      await tester.drag(find.text('Reste là'), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.text('Reste là'), findsOneWidget);
      expect(
        find.text('La notification n’a pas pu être supprimée.'),
        findsOneWidget,
      );
    });

    testWidgets('historique vide : un message l’explique', (tester) async {
      await _pumpHistory(tester, _FakeInbox([]));
      expect(find.text('Aucune notification pour l’instant'), findsOneWidget);
    });

    testWidgets('serveur injoignable : message calme et nouvel essai', (
      tester,
    ) async {
      final inbox = _FakeInbox([_entry(1, 'Revenue')])
        ..fetchError = StateError('Ta session a expiré. Reconnecte-toi.');
      await _pumpHistory(tester, inbox);
      expect(find.text('Historique indisponible'), findsOneWidget);

      inbox.fetchError = null;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Revenue'), findsOneWidget);
    });

    testWidgets('toucher une notification ouvre son écran', (tester) async {
      final inbox = _FakeInbox([
        _entry(1, 'Fin du match', url: 'matches/m1/vote'),
        _entry(2, 'Disponibilité', url: 'matches?match=m2', minutesAgo: 5),
      ]);
      final router = await _pumpHistory(tester, inbox);

      await tester.tap(find.text('Fin du match'));
      await tester.pumpAndSettle();
      expect(find.text('Vote m1'), findsOneWidget);

      router.go('/notifications');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disponibilité'));
      await tester.pumpAndSettle();
      expect(find.text('Calendrier m2'), findsOneWidget);
    });
  });

  group('écran Notifications', () {
    testWidgets('s’ouvre sur l’historique, Paramètres en second onglet', (
      tester,
    ) async {
      final inbox = _FakeInbox([_entry(1, 'Convocation', unread: true)]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationInboxRepositoryProvider.overrideWithValue(inbox),
          ],
          child: const MaterialApp(home: NotificationsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Historique'), findsOneWidget);
      expect(find.text('Paramètres'), findsOneWidget);
      expect(find.text('Convocation'), findsOneWidget);
      expect(inbox.markAllReadCalls, 1);
    });
  });

  testWidgets('l’en-tête garde ses quatre boutons sur un petit téléphone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unreadNotificationCountProvider.overrideWith((ref) async => 12),
          hasUnseenBadgeProvider.overrideWith((ref) async => true),
          seasonWrappedStateProvider.overrideWith(
            (ref) async => const SeasonWrappedState.unavailable(),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              appBar: GrintaAppBar(
                title: const Text('Statistiques'),
                actions: grintaHomeActions(context),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('notification-inbox-button')),
      findsOneWidget,
    );
    expect(find.text('9+'), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });
}
