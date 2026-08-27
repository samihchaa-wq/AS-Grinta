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

    expect(form, contains('final canManage = role?.isAdmin ?? false;'));
    expect(
      controller,
      contains('bool get _isAdmin => _role?.isAdmin ?? false;'),
    );
  });

  // La finalisation de match n'apparaît volontairement pas ci-dessus : l'écran
  // réellement utilisé (module sportif) s'appuie sur le contrôle de rôle des
  // RPC Supabase, pas sur une vérification côté client. L'assertion retirée ici
  // visait un ancien écran devenu inaccessible, et passait au vert sans plus
  // rien garantir.

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
