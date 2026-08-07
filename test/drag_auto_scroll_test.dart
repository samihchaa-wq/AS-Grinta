import 'package:as_grinta/core/widgets/drag_auto_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('auto-scrolls from the visible top edge of a Scrollable',
      (tester) async {
    final controller = ScrollController();
    late BuildContext itemContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(toolbarHeight: 140),
          body: ListView(
            controller: controller,
            children: [
              Builder(
                builder: (context) {
                  itemContext = context;
                  return const SizedBox(height: 2000);
                },
              ),
            ],
          ),
        ),
      ),
    );

    controller.jumpTo(400);
    await tester.pump();

    final scrollable = Scrollable.of(itemContext);
    final renderBox = scrollable.context.findRenderObject()! as RenderBox;
    final viewportTop = renderBox.localToGlobal(Offset.zero).dy;

    // Le bord visible du contenu est sous l'AppBar, donc bien plus bas que
    // l'ancienne zone fixe de 90 px calculée depuis le haut de l'écran.
    expect(viewportTop, greaterThan(90));

    final autoScroller = DragAutoScroller(itemContext);
    autoScroller.update(Offset(20, viewportTop + 20));
    await tester.pump(const Duration(milliseconds: 48));

    expect(controller.offset, lessThan(400));
    autoScroller.stop();
  });
}
