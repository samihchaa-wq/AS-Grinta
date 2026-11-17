import 'package:as_grinta/features/badges/presentation/badge_emblem_body.dart';
import 'package:as_grinta/features/badges/presentation/badge_descriptor.dart';
import 'package:as_grinta/features/badges/presentation/badge_premium_skins.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('les 14 teintes du catalogue choisissent 14 fonds distincts', () {
    const oldColors = [
      '#7A858D', // Gris
      '#CD7F32', // Bronze
      '#C0C0C0', // Argent
      '#D4AF37', // Or
      '#4FA9E8', // Bleu clair
      '#1E3A8A', // Bleu
      '#7C3AED', // Bleu foncé
      '#1C1C24', // Noir
      '#F1706E', // Orange
      '#E23B36', // Rubis
      '#9E1B1B', // Grenat
      '#B9F2FF', // Diamant
      '#F2811D', // Émeraude
      '#F97316', // Violet mystère
    ];
    final skins = oldColors.map(badgePremiumSkinFor).toList();
    expect(skins, hasLength(14));
    expect(skins.every((skin) => skin != null), isTrue);
    expect(skins.toSet(), hasLength(14));
    expect(skins.last, BadgePremiumSkin.violet);
    expect(skins[12], BadgePremiumSkin.emerald);
    expect(skins[6], BadgePremiumSkin.navy);
  });

  test('les anciennes variantes SQL gardent le même palier visuel', () {
    expect(badgePremiumSkinFor('#6E7A86'), BadgePremiumSkin.steel);
    expect(badgePremiumSkinFor('#B87333'), BadgePremiumSkin.bronze);
    expect(badgePremiumSkinFor('#C4CBD4'), BadgePremiumSkin.silver);
    expect(badgePremiumSkinFor('#E3B23C'), BadgePremiumSkin.gold);
    expect(badgePremiumSkinFor('#5FC9D9'), BadgePremiumSkin.diamond);
    expect(badgePremiumSkinFor('#abcdef'), isNull);
  });

  testWidgets('le socle reste dynamique avec les textures premium',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BadgeEmblemBody(
            size: 100,
            base: Color(0xFF7C3AED),
            skin: BadgePremiumSkin.navy,
            descriptor: BadgeDescriptor('MATCHS', 'SAISON'),
            value: '25',
            child: Icon(Icons.sports_soccer),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('25'), findsNWidgets(2));
    expect(find.text('MATCHS'), findsNWidgets(2));
    expect(find.text('SAISON'), findsNWidgets(2));
    final painted = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    expect(painted.any((w) => w.painter is BadgePremiumTexturePainter), isTrue);
    expect(tester.getSize(find.byType(BadgeEmblemBody)).height,
        closeTo(100 * badgeEmblemHeightRatio(), .01));
  });

  testWidgets('les titres mystères sans valeur ne débordent pas',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BadgeEmblemBody(
            size: 87,
            base: Color(0xFFF97316),
            skin: BadgePremiumSkin.violet,
            descriptor: BadgeDescriptor('AU FOUR ET AU MOULIN'),
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // Le titre est affiché via deux RichText superposés (contour + remplissage).
    final labels = tester
        .widgetList<RichText>(find.byType(RichText))
        .where((w) => w.text.toPlainText() == 'AU FOUR ET AU MOULIN');
    expect(labels.length, 2);
  });
}
