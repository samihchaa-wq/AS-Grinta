import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _methodBlock(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start);
  expect(start, isNonNegative, reason: 'Méthode attendue introuvable.');
  expect(end, greaterThan(start),
      reason: 'Fin de méthode attendue introuvable.');
  return source.substring(start, end);
}

void main() {
  // Empêche le retour à deux écritures serveur successives pour un même match.
  test('un match entre nous est sauvegardé avec une seule RPC', () {
    final repositorySource = File(
      'lib/features/matches/data/matches_repository.dart',
    ).readAsStringSync();
    final repositoryBlock = _methodBlock(
      repositorySource,
      'Future<void> updateInternalMatch({',
      '/// Cotes suggérées',
    );

    expect(repositoryBlock, contains("'p_address': address"));

    final controllerSource = File(
      'lib/features/matches/presentation/matches_controller.dart',
    ).readAsStringSync();
    final controllerBlock = _methodBlock(
      controllerSource,
      'Future<void> updateInternalMatch({',
      'bool _validOdds',
    );

    expect(controllerBlock, contains('_repository.updateInternalMatch('));
    expect(controllerBlock, contains('address: address'));
    expect(controllerBlock, isNot(contains('_repository.setMatchAddress(')));
  });
}
