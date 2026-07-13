import 'package:as_grinta/core/design_system/components/grinta_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders card hierarchy and content', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GrintaCard(
            title: 'Prochain match',
            subtitle: 'Dimanche à 15:00',
            child: Text('AS Grinta – Toulouse FC'),
          ),
        ),
      ),
    );

    expect(find.text('Prochain match'), findsOneWidget);
    expect(find.text('Dimanche à 15:00'), findsOneWidget);
    expect(find.text('AS Grinta – Toulouse FC'), findsOneWidget);
  });

  testWidgets('exposes interactive cards as buttons', (tester) async {
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GrintaCard(
            onTap: () => tapCount += 1,
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ouvrir'));
    await tester.pump();

    expect(tapCount, 1);
    expect(
      tester
          .getSemantics(find.byType(GrintaCard))
          .hasFlag(SemanticsFlag.isButton),
      isTrue,
    );
  });
}
