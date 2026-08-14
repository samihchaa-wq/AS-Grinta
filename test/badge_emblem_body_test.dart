import 'package:as_grinta/features/badges/presentation/badge_descriptor.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem_body.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la taille commune des badges Statistiques reste celle de Prono Matchs',
      () {
    expect(statisticsBadgeSize, 36);
    expect(nameWithBadgesMinimumSize, statisticsBadgeSize);
  });

  testWidgets('les bandes basses reprennent toutes la couleur principale',
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

    final coloredBands = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(BadgeEmblemBody),
            matching: find.byType(Container),
          ),
        )
        .where((container) => container.color != null)
        .toList();

    expect(coloredBands, hasLength(3));
    for (final band in coloredBands) {
      expect(band.color, base);
    }
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
}
