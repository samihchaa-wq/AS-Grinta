import 'package:as_grinta/core/design_system/components/grinta_button.dart';
import 'package:as_grinta/core/design_system/components/grinta_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('button triggers its action', (tester) async {
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GrintaButton(label: 'Valider', onPressed: () => tapCount += 1),
        ),
      ),
    );

    await tester.tap(find.text('Valider'));
    await tester.pump();

    expect(tapCount, 1);
  });

  testWidgets('loading button disables repeated actions', (tester) async {
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GrintaButton(
            label: 'Valider',
            isLoading: true,
            onPressed: () => tapCount += 1,
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(GrintaButton));
    await tester.pump();

    expect(tapCount, 0);
  });

  testWidgets('icon button exposes its tooltip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GrintaIconButton(
            icon: Icons.more_horiz,
            tooltip: 'Plus d’options',
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Plus d’options'), findsOneWidget);
  });
}
