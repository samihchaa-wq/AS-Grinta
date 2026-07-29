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

  testWidgets('determinate statistic rings do not become animated loaders',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(child: GrintaProgressIndicator(value: 0)),
              Expanded(child: GrintaProgressIndicator(value: .5)),
              Expanded(child: GrintaProgressIndicator(value: 1)),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsNWidgets(3));
    final values = tester
        .widgetList<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        )
        .map((indicator) => indicator.value)
        .toList();
    expect(values, [0, .5, 1]);
  });

  testWidgets('page-sized indeterminate loader keeps a stable 92px size',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: GrintaProgressIndicator()),
        ),
      ),
    );

    final loader = find.byType(GrintaProgressIndicator);
    final paint = find.descendant(
      of: loader,
      matching: find.byType(CustomPaint),
    );
    expect(paint, findsOneWidget);
    expect(tester.getSize(paint), const Size.square(92));
  });
}
