import 'dart:async';
import 'dart:typed_data';

import 'package:as_grinta/core/config/app_config.dart';
import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/storage/image_mime.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  static String usernameToEmail(String username) =>
      '${username.trim().toLowerCase()}@${AppConfig.usernameDomain}';

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
        // Timeout de sécurité : si l'appel réseau reste en attente (blip
        // réseau…), on échoue proprement au lieu de bloquer l'écran de
        // chargement indéfiniment.
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

  /// Téléverse la photo de profil de l'utilisateur courant et met à jour
  /// `profiles.photo_url`. Renvoie le profil rafraîchi.
  Future<AuthProfile> uploadProfilePhoto({
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');

    final ext = fileExt.isEmpty ? 'jpg' : fileExt.toLowerCase();
    final path = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('profile-photos').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: imageMimeForExt(ext),
            upsert: true,
          ),
        );
    final publicUrl = _client.storage.from('profile-photos').getPublicUrl(path);

    await _client.from('profiles').update({
      'photo_url': publicUrl,
    }).eq('id', userId);

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
