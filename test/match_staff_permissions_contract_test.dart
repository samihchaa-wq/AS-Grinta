import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Les droits de gestion des matchs sont vérifiés par leur comportement dans
  // match_form_page_test.dart et matches_controller_permissions_test.dart.
  // Reste ici une règle d'écriture du code, valable pour tout lib/.

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
