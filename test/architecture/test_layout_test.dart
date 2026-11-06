import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dossiers de test qui ne reflètent pas un dossier de lib/ : les règles
/// vérifiées sur tout le code, et les contrats sur web/.
const _transverseRoots = {'architecture', 'web'};

/// Dossiers de lib/ dont test/ reprend l'arborescence.
const _mirroredRoots = {'app', 'core', 'features'};

void main() {
  // Les tests ont été rangés le 6 novembre 2026 : 172 fichiers s'étaient
  // accumulés à la racine de test/. Ce contrôle empêche le retour du vrac.
  test('chaque test est rangé à l’image du code qu’il vérifie', () {
    final offenders = <String>[];
    final files = Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.path.replaceAll('\\', '/'))
        .toList()
      ..sort();

    for (final path in files) {
      final segments = path.split('/')..removeAt(0); // « test »
      if (segments.length == 1) {
        offenders.add('$path : à la racine de test/');
        continue;
      }
      final root = segments.first;
      if (_transverseRoots.contains(root)) continue;
      if (!_mirroredRoots.contains(root)) {
        offenders.add('$path : dossier « $root » inconnu');
        continue;
      }
      final mirroredDirectory =
          'lib/${segments.sublist(0, segments.length - 1).join('/')}';
      if (!Directory(mirroredDirectory).existsSync()) {
        offenders.add('$path : $mirroredDirectory n’existe pas');
      }
    }

    expect(
      files,
      isNotEmpty,
      reason: 'Le contrôle doit réellement parcourir les tests.',
    );
    expect(
      offenders,
      isEmpty,
      reason: 'Un test se range dans le dossier de test/ qui reflète celui du '
          'code vérifié dans lib/ (par exemple test/features/matches/domain/ '
          'pour lib/features/matches/domain/). Les règles sur tout le code '
          'vont dans test/architecture/, les contrats sur web/ dans '
          'test/web/. Fichiers mal rangés :\n${offenders.join('\n')}',
    );
  });
}
