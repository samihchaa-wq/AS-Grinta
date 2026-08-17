import 'dart:async';

import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

void main() {
  test('invalid_credentials code keeps the credential-specific message', () {
    expect(
      authSignInErrorMessage(
        const supabase.AuthException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        ),
      ),
      'Connexion impossible. Vérifie ton identifiant et ton mot de passe.',
    );
  });

  test('legacy invalid-login message is recognized even without a code', () {
    expect(
      authSignInErrorMessage(
        const supabase.AuthException(
          'Invalid login credentials',
          statusCode: '400',
        ),
      ),
      'Connexion impossible. Vérifie ton identifiant et ton mot de passe.',
    );
  });

  test('timeout is reported as a temporary connection problem', () {
    expect(
      authSignInErrorMessage(TimeoutException('auth timed out')),
      'Connexion temporairement indisponible. Vérifie ta connexion et réessaie.',
    );
  });
}
