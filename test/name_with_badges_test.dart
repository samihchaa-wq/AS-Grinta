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
        descriptor: BadgeDescriptor('BUTS', 'SAISON'),
        hasStar: false,
        stars: 1,
        category: 'joueur_saison',
      ),
      StatisticsBadgeEmblemData(
        emoji: '⚽',
        imageUrl: null,
        color: null,
        valueLabel: null,
        descriptor: BadgeDescriptor('TRIPLÉ'),
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

  testWidgets('un nom très long + son badge ne débordent pas (colonne étroite)',
      (tester) async {
    await tester.pumpWidget(
      harness(
        width: 110,
        name: 'Jean-Christophe de la Villardière-Montmorency',
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Le badge arboré reste visible à droite du nom tronqué.
    expect(find.text('🔥'), findsOneWidget);
  });

  testWidgets('un seul badge est arboré, même si le profil en a plusieurs',
      (tester) async {
    await tester.pumpWidget(harness(width: 240, name: 'Karim'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Karim'), findsOneWidget);
    // Le premier badge s'affiche, le second n'a plus d'emplacement.
    expect(find.text('🔥'), findsOneWidget);
    expect(find.text('⚽'), findsNothing);
  });

  testWidgets('un nom court ne déborde pas (largeur normale)', (tester) async {
    await tester.pumpWidget(harness(width: 240, name: 'Karim'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Karim'), findsOneWidget);
  });

  testWidgets('un prénom court reste entier à côté de son badge',
      (tester) async {
    // Largeur représentative de la colonne « Joueurs » d'un classement sur
    // un téléphone : le prénom doit rester lisible en entier.
    await tester.pumpWidget(harness(width: 150, name: 'Samih'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Samih'), findsOneWidget);
    expect(find.text('🔥'), findsOneWidget);
  });

  testWidgets('un emblème de 48 tient dans la colonne figée', (tester) async {
    // Largeur réelle laissée au nom dans Statistiques.
    const available = grintaTablePinnedWidth -
        grintaTablePinnedRowPadding.horizontal -
        grintaTableRankWidth -
        grintaTableRankGap;
    await tester.pumpWidget(
      harness(width: available, name: 'Milan', badgeSize: 48),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Le prénom reste entier, et son emblème reste visible.
    expect(find.text('Milan'), findsOneWidget);
    expect(find.text('🔥'), findsOneWidget);

    // L'emblème occupe à l'écran toute la place demandée : sa hauteur suit
    // exactement ses proportions, sans bande vide au-dessus ni en dessous.
    final drawn = tester.getRect(find.byType(BadgeEmblem).first);
    expect(drawn.width, closeTo(48, 0.5));
    expect(
      drawn.height,
      closeTo(
        48 * badgeEmblemHeightRatio(hasValue: true, hasPeriod: true),
        0.5,
      ),
    );
  });

  testWidgets(
    'la largeur minimale garde le nom le plus large et son badge entiers',
    (tester) async {
      double? pinnedWidth;
      double? exactRequiredWidth;
      double? intrinsicNameWidth;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            statisticsBadgeEmblemsProvider.overrideWith(
              (ref) async => twoBadges,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: BadgeDisplayScope(
                showBadges: true,
                child: Builder(
                  builder: (context) {
                    const longestName = 'Stéphane F.';
                    const names = ['Milan', longestName];
                    const badgeSize = 48.0;
                    final inheritedStyle = DefaultTextStyle.of(context).style;
                    final cellStyle = grintaTableCellTextStyle(
                      context,
                      fontWeight: FontWeight.w800,
                    );
                    final style = inheritedStyle.merge(cellStyle);
                    final painter = TextPainter(
                      text: TextSpan(text: longestName, style: style),
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                      locale: Localizations.maybeLocaleOf(context),
                      maxLines: 1,
                    )..layout();
                    intrinsicNameWidth = painter.width;
                    exactRequiredWidth = grintaTablePinnedRowPadding.left +
                        grintaTableRankWidth +
                        grintaTableRankGap +
                        painter.width +
                        nameWithBadgesGap +
                        badgeSize +
                        grintaTablePinnedRowPadding.right;
                    pinnedWidth = grintaTablePinnedWidthForNames(
                      context,
                      names,
                      trailingWidth: badgeSize,
                      trailingGap: nameWithBadgesGap,
                    );

                    return SizedBox(
                      width: pinnedWidth,
                      child: Padding(
                        padding: grintaTablePinnedRowPadding,
                        child: Row(
                          children: [
                            const GrintaTableRankCell(rank: 1),
                            const Expanded(
                              child: NameWithBadges(
                                profileId: 'p1',
                                name: longestName,
                                badgeSize: badgeSize,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(pinnedWidth, greaterThanOrEqualTo(exactRequiredWidth!));
      expect(pinnedWidth! - exactRequiredWidth!, lessThan(1));
      expect(
        tester.getSize(find.text('Stéphane F.')).width,
        closeTo(intrinsicNameWidth!, 0.5),
      );
      expect(find.text('🔥'), findsOneWidget);
    },
  );

  testWidgets('un badge à étoiles réserve leur débord', (tester) async {
    const starred = <String, List<StatisticsBadgeEmblemData>>{
      'p1': [
        StatisticsBadgeEmblemData(
          emoji: '🏆',
          imageUrl: null,
          color: null,
          valueLabel: null,
          descriptor: BadgeDescriptor('BALLON D’OR', 'SAISON'),
          hasStar: true,
          stars: 2,
          category: 'palmares',
        ),
      ],
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          statisticsBadgeEmblemsProvider.overrideWith((ref) async => starred),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: BadgeDisplayScope(
              showBadges: true,
              child: NameWithBadges(
                profileId: 'p1',
                name: 'Samih',
                badgeSize: 48,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(2));

    // La moitié haute des étoiles dépasse du rectangle, et cette place est
    // comptée dans la hauteur du badge : rien n'est rogné par la ligne.
    final drawn = tester.getRect(find.byType(BadgeEmblem).first);
    expect(
      drawn.height,
      closeTo(
        48 *
            badgeEmblemHeightRatio(
              hasValue: false,
              hasPeriod: true,
              hasStar: true,
            ),
        0.5,
      ),
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
