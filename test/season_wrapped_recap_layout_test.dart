import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_slides.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'le récapitulatif garde Homme du match entier et relie les lignes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const stat = SeasonWrappedStat(
        label: 'Homme du match',
        value: '2',
        rank: 3,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 342,
                child: WrappedRecapLine(
                  stat: stat,
                  skin: WrappedSkin.flash,
                  highlighted: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final labelFinder = find.text('HOMME DU MATCH');
      expect(labelFinder, findsOneWidget);
      expect(tester.widget<Text>(labelFinder).overflow, isNull);
      expect(
        find.ancestor(of: labelFinder, matching: find.byType(FittedBox)),
        findsOneWidget,
      );

      final containers = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(WrappedRecapLine),
              matching: find.byType(Container),
            ),
          )
          .where((container) => container.decoration is BoxDecoration)
          .toList();
      expect(containers, hasLength(1));

      final decoration = containers.single.decoration! as BoxDecoration;
      expect(
        decoration.color,
        WrappedSkin.flash.text.withValues(alpha: .055),
      );
      expect(decoration.borderRadius, BorderRadius.circular(6));
    },
  );
}
