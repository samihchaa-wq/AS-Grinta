import 'package:as_grinta/core/design_system/components/grinta_loading.dart';
import 'package:as_grinta/core/design_system/components/grinta_status_message.dart';
import 'package:as_grinta/core/design_system/components/grinta_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('text field exposes its label and error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GrintaTextField(
            label: 'Nom du joueur',
            errorText: 'Champ obligatoire',
          ),
        ),
      ),
    );

    expect(find.text('Nom du joueur'), findsOneWidget);
    expect(find.text('Champ obligatoire'), findsOneWidget);
  });

  testWidgets('status message renders semantic feedback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GrintaStatusMessage(
            title: 'Match enregistré',
            message: 'Les statistiques sont à jour.',
            tone: GrintaStatusTone.success,
          ),
        ),
      ),
    );

    expect(find.text('Match enregistré'), findsOneWidget);
    expect(find.text('Les statistiques sont à jour.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('loading indicator renders an optional label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GrintaLoadingIndicator(label: 'Chargement du classement'),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Chargement du classement'), findsOneWidget);
  });
}
