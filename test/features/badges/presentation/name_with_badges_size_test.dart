import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Récupère la taille réellement appliquée au nom rendu.
Future<double?> _renderedFontSize(
  WidgetTester tester, {
  TextStyle? style,
  TextStyle? ambient,
}) async {
  Widget name = NameWithBadges(profileId: null, name: 'Clara', style: style);
  if (ambient != null) {
    name = DefaultTextStyle(style: ambient, child: name);
  }
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: Scaffold(body: name)),
    ),
  );
  return tester.widget<Text>(find.text('Clara')).style?.fontSize;
}

void main() {
  group('Taille des noms de joueurs', () {
    testWidgets('sans style, le nom prend la taille de référence', (
      tester,
    ) async {
      expect(await _renderedFontSize(tester), grintaTableCellFontSize);
    });

    testWidgets('un style sans taille garde la taille de référence', (
      tester,
    ) async {
      // Le cas des listes qui ne fixent que la couleur ou la graisse : elles
      // dérivaient vers la taille ambiante du contexte.
      final size = await _renderedFontSize(
        tester,
        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900),
      );
      expect(size, grintaTableCellFontSize);
    });

    testWidgets('la taille ambiante du contexte ne déteint pas', (
      tester,
    ) async {
      final size = await _renderedFontSize(
        tester,
        ambient: const TextStyle(fontSize: 28),
      );
      expect(size, grintaTableCellFontSize);
    });

    testWidgets('une taille explicite reste respectée', (tester) async {
      final size = await _renderedFontSize(
        tester,
        style: const TextStyle(fontSize: 22),
      );
      expect(size, 22);
    });
  });
}
