import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/auth/presentation/auth_loading_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loading screen displays the authentication loader',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthLoadingPage()));

    final loader = find.byType(GrintaLoader);
    expect(loader, findsOneWidget);
    expect(
      find.descendant(of: loader, matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
    expect(find.text('Préparation de ton espace…'), findsNothing);
  });
}
