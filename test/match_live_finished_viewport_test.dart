import 'package:as_grinta/features/match_live/presentation/match_live_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'le compte rendu terminé borne un Expanded dans le scroll admin',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                const SizedBox(height: 120),
                MatchLiveFinishedViewport(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Compte rendu'),
                      const Expanded(
                        child: SingleChildScrollView(
                          child: SizedBox(height: 1200),
                        ),
                      ),
                      FilledButton(
                        onPressed: () {},
                        child: const Text('VALIDER LE COMPTE RENDU'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Compte rendu'), findsOneWidget);
      expect(find.text('VALIDER LE COMPTE RENDU'), findsOneWidget);

      final viewport = tester.getSize(find.byType(MatchLiveFinishedViewport));
      expect(viewport.height, lessThanOrEqualTo(600));
    },
  );
}
