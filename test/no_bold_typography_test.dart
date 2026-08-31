import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application typography contains no bold font weights', () {
    final boldWeight = RegExp(r'FontWeight\.(?:bold|w[5-9]00)');
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final lines = entity.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        if (boldWeight.hasMatch(lines[index])) {
          offenders.add('${entity.path}:${index + 1}: ${lines[index].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Le texte de l’application doit rester en graisse normale (w400).\n'
          '${offenders.join('\n')}',
    );
  });
}
