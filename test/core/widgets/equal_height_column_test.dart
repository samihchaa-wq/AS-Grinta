import 'package:as_grinta/core/widgets/equal_height_column.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _long = 'Terminer une saison avec le meilleur total de points sur les '
    'pronostics de résultats et de scores des matchs.';

Widget _card(Key key, String text) => Card(
      key: key,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const SizedBox(width: 60, height: 60),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );

void main() {
  testWidgets('toutes les cartes prennent la hauteur de la plus grande',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              EqualHeightColumn(
                spacing: 8,
                children: [
                  _card(const Key('court'), 'Court.'),
                  _card(const Key('long'), _long),
                  _card(
                      const Key('moyen'), 'Un texte sur deux lignes au plus.'),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final short = tester.getRect(find.byKey(const Key('court')));
    final long = tester.getRect(find.byKey(const Key('long')));
    final medium = tester.getRect(find.byKey(const Key('moyen')));

    // Le texte long, en entier, dépasse la hauteur de l'illustration.
    expect(long.height, greaterThan(60 + 24));
    expect(short.height, long.height);
    expect(medium.height, long.height);
    expect(long.top - short.bottom, 8);
    expect(medium.top - long.bottom, 8);

    // Rien n'est coupé : le texte long tient entièrement dans sa carte.
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text(_long),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      tester.getRect(find.text(_long)).bottom,
      lessThanOrEqualTo(long.bottom),
    );
  });

  testWidgets('la hauteur commune suit un texte qui s’allonge', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final text = ValueNotifier('Court.');
    addTearDown(text.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              EqualHeightColumn(
                children: [
                  _card(const Key('fixe'), 'Court.'),
                  ValueListenableBuilder<String>(
                    valueListenable: text,
                    builder: (_, value, __) =>
                        _card(const Key('variable'), value),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final before = tester.getSize(find.byKey(const Key('fixe'))).height;

    text.value = _long;
    await tester.pump();

    expect(tester.takeException(), isNull);
    final after = tester.getSize(find.byKey(const Key('fixe'))).height;
    expect(after, greaterThan(before));
    expect(tester.getSize(find.byKey(const Key('variable'))).height, after);
  });
}
