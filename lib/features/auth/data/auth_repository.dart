import 'dart:async';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Domaine technique : l'identifiant (prénom + initiale) sert de partie
  /// locale à une adresse jamais montrée aux utilisateurs.
  static const usernameDomain = 'pronos.as-grinta.local';

  static String usernameToEmail(String username) =>
      '${username.trim().toLowerCase()}@$usernameDomain';

  Future<void> signInWithUsername({
    required String username,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: usernameToEmail(username),
      password: password,
    );
    if (response.session == null || response.user == null) {
      throw const AuthException('Session non créée après authentification.');
    }
  }

  Future<String> registerAccount({
    required String firstName,
    required String lastName,
    required String password,
  }) async {
    final response = await _client.functions.invoke(
      'register-account',
      body: {
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'password': password,
      },
    );
    final data = response.data;
    final username = data is Map ? data['username']?.toString() : null;
    if (username != null && username.isNotEmpty) return username;
    final message = data is Map ? data['error']?.toString() : null;
    throw StateError(message ?? 'La création du compte a échoué.');
  }

  Future<void> updatePassword(String password) async {
    if (password.length < 8) {
      throw ArgumentError(
        'Le mot de passe doit contenir au moins 8 caractères.',
      );
    }
    await _client.auth.updateUser(UserAttributes(password: password));

    final result = await _client.rpc('complete_password_change');
    if (result != true) {
      throw StateError('Le changement de mot de passe n’a pas été finalisé.');
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<AuthProfile?> fetchProfile({bool retryAfterSignIn = false}) async {
    if (_client.auth.currentUser == null) return null;

    final attempts = retryAfterSignIn ? 5 : 1;
    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final response = await _client.rpc('get_my_profile');
        if (response is Map) {
          return AuthProfile.fromJson(Map<String, dynamic>.from(response));
        }
        lastError = StateError('Réponse de profil invalide.');
      } catch (error) {
        lastError = error;
      }

      if (attempt + 1 < attempts) {
        await Future<void>.delayed(
          Duration(milliseconds: 200 * (attempt + 1)),
        );
      }
    }

    if (lastError != null) throw lastError;
    return null;
  }

  Future<AuthProfile> updateProfile({
    required String firstName,
    required String lastName,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }

    final cleanFirstName = firstName.trim();
    final cleanLastName = lastName.trim();
    if (cleanFirstName.isEmpty || cleanLastName.isEmpty) {
      throw ArgumentError('Le prénom et le nom sont obligatoires.');
    }

    await _client.from('profiles').update({
      'first_name': cleanFirstName,
      'last_name': cleanLastName,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', user.id);

    await _client.auth.updateUser(
      UserAttributes(
        data: {
          'first_name': cleanFirstName,
          'last_name': cleanLastName,
        },
      ),
    );

    final profile = await fetchProfile();
    if (profile == null) {
      throw StateError('Profil introuvable après la mise à jour.');
    }
    return profile;
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});
