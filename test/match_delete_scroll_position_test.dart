import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la suppression d’un match préserve la position du calendrier', () async {
    final source = await File(
      'lib/features/matches/presentation/widgets/admin_match_options_button.dart',
    ).readAsString();

    expect(
      source,
      contains('final scrollPosition = Scrollable.maybeOf(context)?.position;'),
    );
    expect(
      source,
      contains('_restoreScrollPosition(scrollPosition, scrollOffset)'),
    );
    expect(source, contains('position.jumpTo(target)'));
  });
}
