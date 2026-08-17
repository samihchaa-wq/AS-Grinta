import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the sign-in screen keeps AuthState errors in an accessible error banner',
    () {
      final source = File(
        'lib/features/auth/presentation/auth_sign_in_page.dart',
      ).readAsStringSync();

      expect(source, contains('final error = authState.error;'));
      expect(source, contains('GrintaStatusBanner('));
      expect(source, contains('tone: GrintaStatusTone.error'));
      expect(source, contains("'Accès refusé'"));
      expect(source, contains("'Ce compte n’est pas actif.'"));
    },
  );
}
