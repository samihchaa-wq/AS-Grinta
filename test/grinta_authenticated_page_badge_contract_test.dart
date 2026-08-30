import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every authenticated presentation scaffold exposes the club home badge',
      () {
    final featureRoot = Directory('lib/features');
    expect(featureRoot.existsSync(), isTrue);

    final offenders = <String>[];
    final checked = <String>[];

    final dartFiles = featureRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in dartFiles) {
      final path = file.path.replaceAll('\\', '/');

      // Authentication screens deliberately stay outside this contract:
      // /matches is not a usable home destination before authentication.
      if (path.contains('/features/auth/')) continue;

      // Only presentation-layer widgets that own a Scaffold are full-screen
      // surfaces. Embedded tabs/panels inherit the parent page header.
      if (!path.contains('/presentation/')) continue;

      final source = file.readAsStringSync();
      if (!source.contains('Scaffold(')) continue;

      checked.add(path);
      final hasSharedHeader = source.contains('GrintaAppBar(');
      final hasExplicitHomeBadge = source.contains('GrintaClubHomeButton(');
      if (!hasSharedHeader && !hasExplicitHomeBadge) {
        offenders.add(path);
      }
    }

    expect(
      checked,
      isNotEmpty,
      reason: 'Le contrat doit réellement inspecter les pages de présentation.',
    );
    expect(
      offenders,
      isEmpty,
      reason: 'Toute page authentifiée qui possède son propre Scaffold doit '
          'afficher GrintaAppBar ou GrintaClubHomeButton. Pages non conformes: '
          '${offenders.join(', ')}',
    );
  });
}
