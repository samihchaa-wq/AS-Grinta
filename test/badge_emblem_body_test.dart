import 'package:as_grinta/features/badges/presentation/badge_descriptor.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem_body.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la taille commune des badges Statistiques reste celle de Prono Matchs',
      () {
    expect(statisticsBadgeSize, 36);
    expect(nameWithBadgesMinimumSize, statisticsBadgeSize);
  });

  testWidgets(
      'illustration et socle gardent la même teinte avec un contraste très net',
      (tester) async {
    const base = Color(0xFF57C785);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BadgeEmblemBody(
            size: 100,
            base: base,
            descriptor: BadgeDescriptor('BUTS', 'SAISON'),
            value: '12',
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );

    final coloredZones = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(BadgeEmblemBody),
            matching: find.byType(Container),
          ),
        )
        .where((container) => container.color != null)
        .toList();

    expect(coloredZones, hasLength(4));

    final illustrationTone = coloredZones.first.color!;
    final textTone = coloredZones[1].color!;
    final illustrationHsl = HSLColor.fromColor(illustrationTone);
    final textHsl = HSLColor.fromColor(textTone);

    expect(illustrationTone, isNot(textTone));
    expect(illustrationHsl.hue, closeTo(textHsl.hue, 1.0));
    expect(illustrationHsl.lightness, greaterThan(textHsl.lightness));
    expect(
      illustrationHsl.lightness - textHsl.lightness,
      greaterThan(0.20),
    );

    for (final band in coloredZones.skip(1)) {
      expect(band.color, textTone);
    }
  });

  testWidgets('critère et temporalité ont exactement la même taille',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BadgeEmblemBody(
            size: 100,
            base: Color(0xFF57C785),
            descriptor: BadgeDescriptor('BUTS', 'SAISON'),
            value: '12',
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );

    final labelStyle = tester
        .widgetList<Text>(find.text('BUTS'))
        .singleWhere((text) => text.style?.foreground == null)
        .style!;
    final periodStyle = tester
        .widgetList<Text>(find.text('SAISON'))
        .singleWhere((text) => text.style?.foreground == null)
        .style!;

    expect(labelStyle.fontSize, periodStyle.fontSize);

    final coloredZones = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(BadgeEmblemBody),
            matching: find.byType(Container),
          ),
        )
        .where((container) => container.color != null)
        .toList();

    final labelHeight = coloredZones[2].constraints?.maxHeight;
    final periodHeight = coloredZones[3].constraints?.maxHeight;
    expect(labelHeight, periodHeight);
  });

  testWidgets('chiffres et lettres ont un contour noir et un remplissage blanc',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BadgeEmblemBody(
            size: 100,
            base: Color(0xFFFFD54F),
            descriptor: BadgeDescriptor('BUTS', 'SAISON'),
            value: '12',
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );

    for (final label in const ['12', 'BUTS', 'SAISON']) {
      final texts = tester.widgetList<Text>(find.text(label)).toList();
      expect(texts, hasLength(2), reason: label);

      final outlineText = texts.singleWhere(
        (text) => text.style?.foreground != null,
      );
      final fillText = texts.singleWhere(
        (text) => text.style?.foreground == null,
      );
      final outline = outlineText.style!.foreground!;

      expect(outline.style, PaintingStyle.stroke, reason: label);
      expect(outline.color, Colors.black, reason: label);
      expect(outline.strokeWidth, greaterThan(0), reason: label);
      expect(fillText.style?.color, Colors.white, reason: label);
    }
  });

  testWidgets(
      'avec ou sans nombre, tous les emblèmes ont exactement la même hauteur',
      (tester) async {
    const keys = [Key('complet'), Key('titre'), Key('palmares')];
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              BadgeEmblemBody(
                key: Key('complet'),
                size: 100,
                base: Color(0xFF57C785),
                descriptor: BadgeDescriptor('MATCHS', 'CARRIÈRE'),
                value: '268',
                child: SizedBox.shrink(),
              ),
              BadgeEmblemBody(
                key: Key('titre'),
                size: 100,
                base: Color(0xFF57C785),
                descriptor: BadgeDescriptor('QUINTUPLÉ'),
                child: SizedBox.shrink(),
              ),
              BadgeEmblemBody(
                key: Key('palmares'),
                size: 100,
                base: Color(0xFF57C785),
                descriptor: BadgeDescriptor('SOULIER D’OR', 'SAISON'),
                child: SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    for (final key in keys) {
      expect(
        tester.getSize(find.byKey(key)).height,
        closeTo(100 * badgeEmblemHeightRatio(), 0.01),
        reason: '$key',
      );
    }
  });

  testWidgets('un titre long passe à la ligne au lieu d’être rétréci',
      (tester) async {
    const title = 'AU FOUR ET AU MOULIN';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: BadgeEmblemBody(
              size: 200,
              base: Color(0xFFF97316),
              descriptor: BadgeDescriptor(title),
              child: SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final fill = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText() == title &&
          widget.text.style?.foreground == null,
    );
    final paragraph = tester.renderObject<RenderParagraph>(fill);
    final fontSize = tester.widget<RichText>(fill).text.style!.fontSize!;

    // Plusieurs lignes, sans dépasser le socle ni couper le titre.
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.height, greaterThan(fontSize * 1.5));
    expect(paragraph.size.width, lessThanOrEqualTo(200));
    // Le titre garde une taille lisible, bien au-dessus du critère d’un badge
    // chiffré (9,5 % de la largeur).
    expect(fontSize, greaterThan(200 * 0.095));
  });

  testWidgets('un mot trop large pour le badge est réduit, jamais coupé',
      (tester) async {
    const title = 'ANTICONSTITUTIONNELLEMENT';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: BadgeEmblemBody(
              size: 100,
              base: Color(0xFFF97316),
              descriptor: BadgeDescriptor(title),
              child: SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final fill = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText() == title &&
          widget.text.style?.foreground == null,
    );
    final paragraph = tester.renderObject<RenderParagraph>(fill);
    final fontSize = tester.widget<RichText>(fill).text.style!.fontSize!;

    // Une seule ligne : le mot tient entier dans la largeur du badge.
    expect(paragraph.size.height, lessThan(fontSize * 1.5));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(fontSize, lessThan(100 * 0.14));
  });
}
