import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'club badge stays after the back button and returns to calendar',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/matches',
        routes: [
          GoRoute(
            path: '/matches',
            builder: (_, __) => const _TestPage(
              title: 'Calendrier',
              bodyKey: ValueKey<String>('calendar-body'),
            ),
          ),
          GoRoute(
            path: '/details',
            builder: (_, __) => const _TestPage(
              title: 'Détails',
              bodyKey: ValueKey<String>('details-body'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.byKey(grintaClubHomeBadgeKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('calendar-body')),
        findsOneWidget,
      );

      router.push('/details');
      await tester.pumpAndSettle();

      final backButton = find.byType(BackButton);
      final badge = find.byKey(grintaClubHomeBadgeKey);
      expect(backButton, findsOneWidget);
      expect(badge, findsOneWidget);

      final backRect = tester.getRect(backButton);
      final badgeRect = tester.getRect(badge);
      expect(badgeRect.left, greaterThanOrEqualTo(backRect.right));

      await tester.tap(badge);
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/matches');
      expect(
        find.byKey(const ValueKey<String>('calendar-body')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('details-body')), findsNothing);
    },
  );
}

class _TestPage extends StatelessWidget {
  const _TestPage({required this.title, required this.bodyKey});

  final String title;
  final Key bodyKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(title: Text(title)),
      body: SizedBox(key: bodyKey),
    );
  }
}
