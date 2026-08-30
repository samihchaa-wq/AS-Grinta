import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secondary Navigator routes only open badge-compliant pages', () {
    final presentationRoot = Directory('lib/features');
    final pageClasses = <String, String>{};

    final files = presentationRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    final classPattern = RegExp(
      r'class\s+([A-Za-z0-9_]*Page)\s+extends\s+',
    );

    for (final file in files) {
      final path = file.path.replaceAll('\\', '/');
      if (path.contains('/features/auth/')) continue;
      if (!path.contains('/presentation/')) continue;
      final source = file.readAsStringSync();
      if (!source.contains('Scaffold(')) continue;
      for (final match in classPattern.allMatches(source)) {
        pageClasses[match.group(1)!] = path;
      }
    }

    final routeTargetPattern = RegExp(
      r'MaterialPageRoute(?:<[^>]+>)?\s*\([^)]*?builder\s*:\s*\([^)]*\)\s*=>\s*(?:const\s+)?([A-Za-z0-9_]*Page)\s*\(',
      dotAll: true,
    );
    final unresolvedTargets = <String>[];
    final nonCompliantTargets = <String>[];

    for (final file in files) {
      final path = file.path.replaceAll('\\', '/');
      if (!path.contains('/presentation/')) continue;
      final source = file.readAsStringSync();
      for (final match in routeTargetPattern.allMatches(source)) {
        final targetClass = match.group(1)!;
        final targetPath = pageClasses[targetClass];
        if (targetPath == null) {
          unresolvedTargets.add('$path -> $targetClass');
          continue;
        }
        final targetSource = File(targetPath).readAsStringSync();
        final compliant = targetSource.contains('GrintaAppBar(') ||
            targetSource.contains('GrintaClubHomeButton(');
        if (!compliant) {
          nonCompliantTargets.add('$path -> $targetPath');
        }
      }
    }

    expect(
      unresolvedTargets,
      isEmpty,
      reason: 'Toute cible MaterialPageRoute doit être résolue par le contrat: '
          '${unresolvedTargets.join(', ')}',
    );
    expect(
      nonCompliantTargets,
      isEmpty,
      reason: 'Toute page ouverte hors GoRouter doit aussi porter le badge: '
          '${nonCompliantTargets.join(', ')}',
    );
  });
}
