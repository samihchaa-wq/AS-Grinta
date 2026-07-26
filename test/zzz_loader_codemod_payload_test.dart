import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('génère et valide le correctif global du loader rebondissant', () {
    const loaderPath = 'lib/core/widgets/grinta_loader.dart';
    const loaderImport =
        "import 'package:as_grinta/core/widgets/grinta_loader.dart';";
    final circularPattern = RegExp(r'(?<![.\w])CircularProgressIndicator\b');
    final linearPattern = RegExp(r'(?<![.\w])LinearProgressIndicator\b');

    final loaderTemplate =
        File('tool/bouncing_loader_template.dart.txt').readAsStringSync();
    File(loaderPath).writeAsStringSync(loaderTemplate);

    final changedPaths = <String>{loaderPath};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (path == loaderPath) continue;

      final source = entity.readAsStringSync();
      if (!circularPattern.hasMatch(source) &&
          !linearPattern.hasMatch(source)) {
        continue;
      }

      var updated = source
          .replaceAll(circularPattern, 'GrintaProgressIndicator')
          .replaceAll(linearPattern, 'GrintaLinearProgressIndicator');

      if (!updated.contains(loaderImport)) {
        final lines = updated.split('\n');
        var lastImport = -1;
        for (var index = 0; index < lines.length; index++) {
          if (lines[index].startsWith('import ')) lastImport = index;
        }
        if (lastImport >= 0) {
          lines.insert(lastImport + 1, loaderImport);
          updated = lines.join('\n');
        } else if (!updated.trimLeft().startsWith('part of ')) {
          fail('Aucun import trouvé dans $path');
        }
      }

      entity.writeAsStringSync(updated);
      changedPaths.add(path);
    }

    final sortedPaths = changedPaths.toList()..sort();
    final formatResult = Process.runSync(
      'dart',
      ['format', ...sortedPaths],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (formatResult.exitCode != 0) {
      fail('dart format a échoué : ${formatResult.stderr}');
    }

    final encodedFiles = <String, String>{};
    for (final path in sortedPaths) {
      final content = File(path).readAsStringSync();
      encodedFiles[path] = base64Encode(utf8.encode(content));
    }

    final payload = base64Encode(utf8.encode(jsonEncode(encodedFiles)));
    const chunkSize = 4000;
    stdout.writeln('GRINTA_CODEMOD_PAYLOAD_BEGIN');
    for (var offset = 0; offset < payload.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, payload.length);
      stdout.writeln(payload.substring(offset, end));
    }
    stdout.writeln('GRINTA_CODEMOD_PAYLOAD_END');

    final treeResult = Process.runSync(
      'git',
      ['rev-parse', r'origin/main^{tree}'],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (treeResult.exitCode != 0) {
      fail('Impossible de lire l’arbre Git : ${treeResult.stderr}');
    }
    stdout
        .writeln('GRINTA_BASE_TREE_SHA:${treeResult.stdout.toString().trim()}');

    fail('Arrêt temporaire après extraction de l’arbre Git.');
  });
}
