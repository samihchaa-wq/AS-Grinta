import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('match management honors admin rights', () async {
    final form = await File(
      'lib/features/matches/presentation/match_form_page.dart',
    ).readAsString();
    final controller = await File(
      'lib/features/matches/presentation/matches_controller.dart',
    ).readAsString();
    final finalization = await File(
      'lib/features/matches/presentation/match_finalization_controller.dart',
    ).readAsString();

    expect(form, contains('final canManage = role?.isAdmin ?? false;'));
    expect(
      controller,
      contains('bool get _isAdmin => _role?.isAdmin ?? false;'),
    );
    expect(finalization, contains('if (!(role?.isAdmin ?? false))'));
  });

  test('runtime code never compares directly against AuthRole.admin', () async {
    final directAdminComparison = RegExp(
      r'(?:==|!=)\s*AuthRole\.admin|AuthRole\.admin\s*(?:==|!=)',
    );
    final offenders = <String>[];

    await for (final entity in Directory('lib').list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // La définition centrale du rôle doit naturellement comparer l'enum afin
      // d'implémenter isAdmin. Partout ailleurs, le code passe par les
      // capacités isAdmin/isStaff pour éviter les divergences.
      if (entity.path.replaceAll('\\', '/').endsWith(
            'features/auth/domain/auth_profile.dart',
          )) {
        continue;
      }
      final source = await entity.readAsString();
      if (directAdminComparison.hasMatch(source)) offenders.add(entity.path);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Utiliser role.isAdmin/isStaff au lieu de comparer directement '
          'AuthRole.admin : ${offenders.join(', ')}',
    );
  });
}
