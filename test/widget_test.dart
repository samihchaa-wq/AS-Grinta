import 'package:as_grinta/features/auth/presentation/auth_loading_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loading screen displays the authentication loader',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthLoadingPage()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Chargement de votre espace...'), findsOneWidget);
  });
}
