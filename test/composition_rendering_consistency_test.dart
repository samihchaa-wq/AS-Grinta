import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formation editor renders saved player coordinates like match pitch', () {
    final source = File(
      'lib/features/sports_management/presentation/widgets/'
      'formation_pitch_editor.dart',
    ).readAsStringSync();

    expect(source, contains('Offset(entry.x ?? slot.position.dx'));
    expect(source, contains('entry.y ?? slot.position.dy'));
    expect(source, contains('visualPosition.dx.clamp(0.08, 0.92)'));
    expect(source, contains('visualPosition.dy.clamp(0.06, 0.94)'));
  });
}
