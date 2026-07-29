import 'dart:async';
import 'dart:typed_data';

import 'package:as_grinta/core/config/app_config.dart';
import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/security/password_policy.dart';
import 'package:as_grinta/core/storage/image_mime.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signInWithUsername({
    required String username,
    required String password,
  }) async {
    final normalized = username.trim().toLowerCase();
    final email = normalized.contains('@')
        ? normalized
        : '$normalized@${AppConfig.usernameDomain}';
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (response.session == null || response.user == null) {
      throw const AuthException('Session non créée après authentification.');
    }
  }

  /// Crée un compte via l'inscription publique (prénom + nom, sans e-mail).
  /// Retourne l'identifiant généré par le serveur, à communiquer au joueur.
  Future<String> registerAccount({
    required String firstName,
    required String lastName,
    required String password,
  }) async {
    final passwordError = PasswordPolicy.validate(password);
    if (passwordError != null) throw ArgumentError(passwordError);

    final response = await _client.functions.invoke(
      'register-account',
      body: {
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'password': password,
      },
    );
    final data = response.data;
    final username = data is Map ? data['username'] as String? : null;
    if (response.status != 200 || username == null || username.isEmpty) {
      final message = data is Map ? data['error'] as String? : null;
      throw StateError(message ?? 'La création du compte a échoué.');
    }
    return username;
  }

  Future<void> updatePassword(String password) async {
    final passwordError = PasswordPolicy.validate(password);
    if (passwordError != null) throw ArgumentError(passwordError);

    await _client.auth.updateUser(UserAttributes(password: password));

    final profile = await fetchProfile();
    if (profile?.mustChangePassword == true) {
      final result = await _client.rpc('complete_password_change');
      if (result != true) {
        throw StateError('Le changement de mot de passe n’a pas été finalisé.');
      }
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
        final response = await _client
            .rpc('get_my_profile')
            .timeout(const Duration(seconds: 12));
        if (response == null) return null;
        return AuthProfile.fromJson(
          Map<String, dynamic>.from(response as Map),
        );
      } catch (error) {
        lastError = error;
        if (attempt + 1 < attempts) {
          await Future<void>.delayed(
            Duration(milliseconds: 150 * (attempt + 1)),
          );
        }
      }
    }
    throw lastError ?? StateError('Le profil n’a pas pu être chargé.');
  }

  Future<AuthProfile> updateProfile({
    required String firstName,
    required String lastName,
    String? surnom,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');

    await _client.from('profiles').update({
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'surnom': (surnom ?? '').trim(),
    }).eq('id', userId);

    await _client.auth.updateUser(
      UserAttributes(
        data: {
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
        },
      ),
    );

    final profile = await fetchProfile();
    if (profile == null) {
      throw StateError('Le profil mis à jour est introuvable.');
    }
    return profile;
  }

  Future<AuthProfile> uploadProfilePhoto({
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');

    final image = validateImageUpload(bytes, fileExt: fileExt);
    final path =
        '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.${image.extension}';
    final bucket = _client.storage.from('profile-photos');
    await bucket.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        contentType: image.mimeType,
        upsert: false,
      ),
    );
    final publicUrl = bucket.getPublicUrl(path);

    try {
      await _client.from('profiles').update({
        'photo_url': publicUrl,
      }).eq('id', userId);
    } catch (_) {
      await bucket.remove([path]);
      rethrow;
    }

    final profile = await fetchProfile();
    if (profile == null) {
      throw StateError('Le profil mis à jour est introuvable.');
    }
    return profile;
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});
