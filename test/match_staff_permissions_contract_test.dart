import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('match management honors moderator admin rights', () async {
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
    expect(
      form,
      isNot(contains('final canManage = role == AuthRole.admin;')),
    );
    expect(
      controller,
      isNot(contains('bool get _isAdmin => _role == AuthRole.admin;')),
    );
  });
}
