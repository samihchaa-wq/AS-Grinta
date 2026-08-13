import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:as_grinta/features/badges/data/statistics_badge_emblems_provider.dart';
import 'package:as_grinta/features/badges/presentation/badge_display_scope.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem_body.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const twoBadges = <String, List<StatisticsBadgeEmblemData>>{
    'p1': [
      StatisticsBadgeEmblemData(
        emoji: '🔥',
        imageUrl: null,
        color: null,
        valueLabel: '12',
        descriptor: 'BUTS · SAISON',
        hasStar: false,
        stars: 1,
        category: 'joueur_saison',
      ),
      StatisticsBadgeEmblemData(
        emoji: '⚽',
        imageUrl: null,
        color: null,
        valueLabel: null,
        descriptor: 'TRIPLÉ',
        hasStar: false,
        stars: 1,
        category: 'joueur_saison',
      ),
    ],
  };

  Widget harness({
    required double width,
    required String name,
    bool showBadges = true,
    double? badgeSize,
  }) {
    return ProviderScope(
      overrides: [
        statisticsBadgeEmblemsProvider.overrideWith((ref) async => twoBadges),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: BadgeDisplayScope(
            showBadges: showBadges,
            child: Center(
              child: SizedBox(
                width: width,
                child: Row(
                  children: [
                    Expanded(
                      child: NameWithBadges(
                        profileId: 'p1',
                        name: name,
                        badgeSize: badgeSize,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('un nom très long + 2 badges ne débordent pas (colonne étroite)',
      (tester) async {
    await tester.pumpWidget(
      harness(
        width: 110,
        name: 'Jean-Christophe de la Villardière-Montmorency',
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Les 2 badges restent visibles à droite du nom tronqué.
    expect(find.text('🔥'), findsOneWidget);
    expect(find.text('⚽'), findsOneWidget);
  });

  testWidgets('un nom court + 3 badges ne débordent pas (largeur normale)',
      (tester) async {
    await tester.pumpWidget(harness(width: 240, name: 'Karim'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Karim'), findsOneWidget);
  });

  testWidgets(
      'un prénom court reste entier avec 2 grands badges (colonne de classement)',
      (tester) async {
    // Largeur représentative de la colonne « Joueurs » d'un classement sur
    // un téléphone : le prénom doit rester lisible en entier.
    await tester.pumpWidget(harness(width: 150, name: 'Samih'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Samih'), findsOneWidget);
    expect(find.text('🔥'), findsOneWidget);
    expect(find.text('⚽'), findsOneWidget);
  });

  testWidgets('deux emblèmes de 48 tiennent dans la colonne figée',
      (tester) async {
    // Largeur réelle laissée au nom dans Statistiques : colonne figée moins
    // ses marges (16 + 8), le rang (22) et son écart (4).
    const available = grintaTablePinnedWidth - 16 - 8 - 22 - 4;
    await tester.pumpWidget(
      harness(width: available, name: 'Milan', badgeSize: 48),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Le prénom reste entier, les deux emblèmes restent visibles.
    expect(find.text('Milan'), findsOneWidget);
    expect(find.text('🔥'), findsOneWidget);
    expect(find.text('⚽'), findsOneWidget);

    // L'emblème occupe à l'écran toute la place demandée : sa hauteur suit
    // exactement ses proportions, sans bande vide au-dessus ni en dessous.
    final drawn = tester.getRect(find.byType(BadgeEmblem).first);
    expect(drawn.width, closeTo(48, 0.5));
    expect(
      drawn.height,
      closeTo(48 * badgeEmblemHeightRatio(hasValue: true), 0.5),
    );
  });

  testWidgets('hors Statistiques, seul le nom est rendu', (tester) async {
    await tester.pumpWidget(
      harness(width: 240, name: 'Samih', showBadges: false),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Samih'), findsOneWidget);
    expect(find.text('🔥'), findsNothing);
    expect(find.text('⚽'), findsNothing);
  });

  testWidgets('sans portée déclarée, aucun badge ne fuite', (tester) async {
    // Un écran qui n'active rien (Calendrier, fiche de match, feuille modale)
    // ne doit ni afficher de badge ni exiger un routeur au-dessus de lui.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          statisticsBadgeEmblemsProvider.overrideWith((ref) async => twoBadges),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: NameWithBadges(profileId: 'p1', name: 'Samih'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Samih'), findsOneWidget);
    expect(find.text('🔥'), findsNothing);
  });
}
