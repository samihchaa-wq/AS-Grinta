import 'dart:io';

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

  test(
      'le calendrier pose la clé de focus sur la carte, pas sur '
      "l'en-tête épinglé", () async {
    final source = await File(
      'lib/features/predictions/presentation/merged_matches_view.dart',
    ).readAsString();

    expect(source, contains('key: isFocusCard ? focusMatchKey : null'));
    expect(source, isNot(contains('headerIsFocus')));
  });
}
