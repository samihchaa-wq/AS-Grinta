import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double _headerHeight = 38;
const double _cardHeight = 120;
const int _cardsPerSection = 10;

class _PinnedHeader extends SliverPersistentHeaderDelegate {
  const _PinnedHeader(this.title);

  final String title;

  @override
  double get minExtent => _headerHeight;

  @override
  double get maxExtent => _headerHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return SizedBox(
      height: _headerHeight,
      child: ColoredBox(color: Colors.black, child: Text(title)),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedHeader oldDelegate) =>
      oldDelegate.title != title;
}

List<Widget> _section(String title, {Key? cardKey, int? keyedIndex}) {
  return [
    SliverPersistentHeader(pinned: true, delegate: _PinnedHeader(title)),
    SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => SizedBox(
          key: index == keyedIndex ? cardKey : null,
          height: _cardHeight,
          child: Text('$title $index'),
        ),
        childCount: _cardsPerSection,
      ),
    ),
  ];
}

Widget _group(String title, {Key? cardKey, int? keyedIndex}) {
  return SliverMainAxisGroup(
    slivers: _section(title, cardKey: cardKey, keyedIndex: keyedIndex),
  );
}

void main() {
  const cardKey = ValueKey<String>('focus-card');

  Future<ScrollController> pumpFeed(WidgetTester tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: controller,
            slivers: [
              ..._section('Terminés'),
              ..._section('À venir', cardKey: cardKey, keyedIndex: 3),
            ],
          ),
        ),
      ),
    );
    // La carte visée est construite paresseusement : on s'en approche d'abord.
    controller.jumpTo(1500);
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets(
    'viser un en-tête épinglé envoie le défilement au bout de la liste',
    (tester) async {
      final controller = await pumpFeed(tester);

      await Scrollable.ensureVisible(
        tester.element(find.text('À venir')),
        alignment: 0,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        duration: Duration.zero,
      );
      await tester.pumpAndSettle();

      expect(
        controller.position.pixels,
        controller.position.maxScrollExtent,
      );
      expect(find.byKey(cardKey), findsNothing);
    },
  );

  testWidgets(
    'viser la carte la place juste sous les en-têtes épinglés',
    (tester) async {
      await pumpFeed(tester);

      await Scrollable.ensureVisible(
        tester.element(find.byKey(cardKey)),
        alignment: 0,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        duration: Duration.zero,
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.byKey(cardKey)).dy,
        moreOrLessEquals(2 * _headerHeight, epsilon: 0.5),
      );
    },
  );

  testWidgets(
    "l'en-tête d'une phase terminée sort de l'écran quand la suivante arrive",
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              controller: controller,
              slivers: [
                _group('Terminés'),
                _group('À venir', cardKey: cardKey, keyedIndex: 3),
              ],
            ),
          ),
        ),
      );

      // Pendant la transition, le nouvel en-tête pousse l'ancien vers le haut.
      controller.jumpTo(1150);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Terminés')).dy, 0);
      expect(
        tester.getTopLeft(find.text('À venir')).dy,
        greaterThan(0),
      );

      // Une fois dans la phase suivante, l'ancien en-tête a disparu.
      controller.jumpTo(1500);
      await tester.pumpAndSettle();
      expect(find.text('Terminés'), findsNothing);
      expect(tester.getTopLeft(find.text('À venir')).dy, 0);
    },
  );

  testWidgets(
    'la carte visée se cale sous un seul en-tête une fois les phases groupées',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              controller: controller,
              slivers: [
                _group('Terminés'),
                _group('À venir', cardKey: cardKey, keyedIndex: 3),
              ],
            ),
          ),
        ),
      );

      controller.jumpTo(1500);
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.byKey(cardKey)),
        alignment: 0,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        duration: Duration.zero,
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.byKey(cardKey)).dy,
        moreOrLessEquals(_headerHeight, epsilon: 0.5),
      );
    },
  );

  // Sur le vrai calendrier, la clé de focus posée sur la carte et le groupement
  // des phases sont vérifiés par leur effet dans merged_matches_view_test.dart.
}
