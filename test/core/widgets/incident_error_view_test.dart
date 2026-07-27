import 'package:as_grinta/core/widgets/incident_error_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('affiche une référence non sensible et permet de réessayer', (
    tester,
  ) async {
    var retried = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: IncidentErrorView(
          title: 'Une erreur est survenue',
          message: 'Réessaie dans un instant.',
          incidentReference: 'MPG-20260727-120000-001',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('Une erreur est survenue'), findsOneWidget);
    expect(find.text('Référence : MPG-20260727-120000-001'), findsOneWidget);
    expect(find.textContaining('exception'), findsNothing);

    await tester.tap(find.text('Réessayer'));
    expect(retried, isTrue);
  });
}
