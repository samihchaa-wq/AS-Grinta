import 'dart:convert';
import 'dart:typed_data';

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
    await _client.auth.signInWithPassword(
      email: usernameToEmail(username),
      password: password,
    );
  }

  /// Auto-inscription via le lien partagé dans la conversation du club :
  /// crée un compte « en attente de validation » et retourne l'identifiant
  /// généré (prénom + initiale).
  Future<String> registerAccount({
    required String firstName,
    required String lastName,
    required String surnom,
    required String password,
    Uint8List? photoJpegBytes,
  }) async {
    final response = await _client.functions.invoke(
      'register-account',
      body: {
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'surnom': surnom.trim(),
        'password': password,
        if (photoJpegBytes != null && photoJpegBytes.isNotEmpty)
          'photoBase64': base64Encode(photoJpegBytes),
      },
    );
    final data = response.data;
    final username = data is Map ? data['username']?.toString() : null;
    if (username != null && username.isNotEmpty) return username;
    final message = data is Map ? data['error']?.toString() : null;
    throw StateError(message ?? 'La création du compte a échoué.');
  }

  /// Première connexion d'un compte invité : le joueur choisit son mot de
  /// passe via l'Edge Function claim-account (appelée sans session).
  Future<void> claimAccount({
    required String username,
    required String password,
  }) async {
    final response = await _client.functions.invoke(
      'claim-account',
      body: {
        'username': username.trim().toLowerCase(),
        'password': password,
      },
    );
    final data = response.data;
    if (data is Map && data['activated'] == true) return;
    final message = data is Map ? data['error']?.toString() : null;
    throw StateError(message ?? 'L’activation du compte a échoué.');
  }

  Future<void> updatePassword(String password) async {
    if (password.length < 8) {
      throw ArgumentError(
        'Le mot de passe doit contenir au moins 8 caractères.',
      );
    }
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<AuthProfile?> fetchProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final response = await _client
        .from('profiles')
        .select(
          'id,first_name,last_name,surnom,username,photo_url,role,is_goalkeeper,status,created_at,updated_at',
        )
        .eq('id', user.id)
        .maybeSingle();
    if (response == null) return null;

    return AuthProfile.fromJson(Map<String, dynamic>.from(response));
  }

  Future<String> uploadAvatar(Uint8List jpegBytes) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }
    if (jpegBytes.isEmpty) {
      throw ArgumentError('Image vide.');
    }

    final path = '${user.id}/avatar.jpg';
    await _client.storage.from('profile-photos').uploadBinary(
          path,
          jpegBytes,
          fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    final publicUrl = _client.storage.from('profile-photos').getPublicUrl(path);
    return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<AuthProfile> updateProfile({
    required String firstName,
    required String lastName,
    required String surnom,
    required String avatarPath,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }

    final cleanFirstName = firstName.trim();
    final cleanLastName = lastName.trim();
    final cleanNickname = surnom.trim();
    if (cleanFirstName.isEmpty || cleanLastName.isEmpty) {
      throw ArgumentError('Le prénom et le nom sont obligatoires.');
    }

    await _client.from('profiles').update({
      'first_name': cleanFirstName,
      'last_name': cleanLastName,
      'surnom': cleanNickname.isEmpty ? null : cleanNickname,
      'photo_url': avatarPath.trim().isEmpty ? null : avatarPath.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', user.id);

    await _client.auth.updateUser(
      UserAttributes(
        data: {
          'first_name': cleanFirstName,
          'last_name': cleanLastName,
          'surnom': cleanNickname.isEmpty ? null : cleanNickname,
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
  final client = ref.watch(supabaseClientProvider);
  return AuthRepository(client);
});
