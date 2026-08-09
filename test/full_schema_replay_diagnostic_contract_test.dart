import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('full schema replay remains diagnostic while historical repair is deferred', () {
    final source = File(
      '.github/workflows/full_schema_replay_diagnostic.yml',
    ).readAsStringSync();

    expect(source, contains('schedule:'));
    expect(source, contains('exit 0'));
    expect(source, contains('reconstruction historique complète est volontairement différée'));
  });
}
