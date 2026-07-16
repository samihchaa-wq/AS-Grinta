import 'package:as_grinta/features/badges/data/featured_badges_repository.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final threeBadges = <String, List<FeaturedBadge>>{
    'p1': const [
      FeaturedBadge(emoji: '🔥', imageUrl: null),
      FeaturedBadge(emoji: '⚽', imageUrl: null),
      FeaturedBadge(emoji: '🏆', imageUrl: null),
    ],
  };

  Widget harness({required double width, required String name}) {
    return ProviderScope(
      overrides: [
        featuredBadgesProvider.overrideWith((ref) async => threeBadges),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: Row(
                children: [
                  Expanded(
                    child: NameWithBadges(profileId: 'p1', name: name),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('un nom très long + 3 badges ne débordent pas (colonne étroite)',
      (tester) async {
    await tester.pumpWidget(
      harness(
        width: 110,
        name: 'Jean-Christophe de la Villardière-Montmorency',
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Les 3 badges restent visibles à droite du nom tronqué.
    expect(find.text('🔥'), findsOneWidget);
    expect(find.text('⚽'), findsOneWidget);
    expect(find.text('🏆'), findsOneWidget);
  });

  testWidgets('un nom court + 3 badges ne débordent pas (largeur normale)',
      (tester) async {
    await tester.pumpWidget(harness(width: 240, name: 'Karim'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Karim'), findsOneWidget);
  });
}
