import 'package:as_grinta/features/badges/data/badge_inbox_repository.dart';
import 'package:as_grinta/features/badges/presentation/badge_trophy_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('affiche 1 lorsqu’un badge est nouveau', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hasUnseenBadgeProvider.overrideWith((ref) async => true),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BadgeTrophyButton()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('🏆'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('masque la pastille lorsque tout est vu', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hasUnseenBadgeProvider.overrideWith((ref) async => false),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BadgeTrophyButton()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('🏆'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });
}
