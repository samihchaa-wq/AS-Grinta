import 'package:as_grinta/features/badges/data/badge_inbox_repository.dart';
import 'package:as_grinta/features/badges/presentation/badge_trophy_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('affiche un indicateur lorsqu’un badge est nouveau', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [hasUnseenBadgeProvider.overrideWith((ref) async => true)],
        child: const MaterialApp(home: Scaffold(body: BadgeTrophyButton())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
    expect(
      find.byKey(const ValueKey('badge-unseen-indicator')),
      findsOneWidget,
    );
  });

  testWidgets('masque l’indicateur lorsque tout est vu', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [hasUnseenBadgeProvider.overrideWith((ref) async => false)],
        child: const MaterialApp(home: Scaffold(body: BadgeTrophyButton())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('badge-unseen-indicator')), findsNothing);
  });
}
