import 'package:as_grinta/features/sports_management/presentation/widgets/composition_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fait avancer la vidéo jusqu'à l'instant où le terrain est posé, puis
/// vérifie que chaque joueur de la vidéo couvre exactement le même joueur de
/// la page (même place, même taille, à deux pixels près : invisible pendant
/// le fondu de l'une vers l'autre).
Future<void> expectLandsOnPage(WidgetTester tester) async {
  final page = tester.widget<CompositionPresentationPage>(
    find.byType(CompositionPresentationPage),
  );
  final names = [
    for (final entry in page.data.field)
      if (!entry.isVacant) entry.displayName,
  ];
  // « Passer » disparaît quand la page commence à apparaître : c'est la
  // phase finale, où le terrain descend se poser. Avant le départ, le bouton
  // s'appelle « Fermer » : on attend d'avoir vu « Passer », puis sa
  // disparition.
  var started = false;
  for (var step = 0; step < 2000; step++) {
    await tester.pump(const Duration(milliseconds: 20));
    final shown = find.text('Passer').evaluate().isNotEmpty;
    if (shown) started = true;
    if (started && !shown) break;
  }
  expect(started, isTrue, reason: 'la vidéo doit démarrer');
  // « Passer » disparaît à moveStart + 1,0 s ; le terrain est posé à
  // flatAt = moveStart + 1,6 s, et la vidéo s'efface jusqu'à flatAt + 0,5 s.
  // The landing transition takes twice the wall-clock time now.
  for (var step = 0; step < 64; step++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(find.byType(CompositionPresentationPage), findsOneWidget,
      reason: 'la vidéo doit encore être là au moment de la mesure');
  for (final name in names) {
    final found = find.text(name);
    expect(found, findsNWidgets(2), reason: '$name : vidéo + page');
    final rects = [
      for (final element in found.evaluate())
        tester.getRect(find.byWidget(element.widget).first),
    ];
    final a = rects[0];
    final b = rects[1];
    expect((a.center - b.center).distance, lessThan(2.5),
        reason: '$name : ${a.center} / ${b.center}');
    expect((a.width - b.width).abs(), lessThan(2.5),
        reason: '$name : largeur ${a.width} / ${b.width}');
  }
}
