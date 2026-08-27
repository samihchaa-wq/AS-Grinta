import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les huit en-têtes de la table des statistiques joueurs, dans l'ordre réel.
const _labels = ['J', 'B', 'PD', 'CS', 'HDM', 'G', 'N', 'P'];

/// Doit rester aligné sur `_playerColumnWidth` de la page Statistiques.
const _columnWidth = 64.0;

void main() {
  testWidgets(
    'les huit colonnes de stats tiennent dans la largeur réservée',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: _labels.length * _columnWidth,
              child: Row(
                children: [
                  for (final label in _labels)
                    SortableHeaderCell(
                      label: label,
                      flex: 1,
                      active: label == 'HDM',
                      descending: true,
                      onTap: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      // Une colonne trop étroite ne fait pas planter la page : le libellé se
      // fait simplement tronquer en « H… ». C'est donc la troncature qu'il
      // faut surveiller, pas une exception de mise en page.
      for (final label in _labels) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: 'l’en-tête « $label » est tronqué',
        );
      }
    },
  );
}
