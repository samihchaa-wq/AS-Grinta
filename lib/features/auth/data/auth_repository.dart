import 'dart:typed_data';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
      },
    );

    if (response.user == null) {
      throw StateError('Impossible de créer le compte.');
    }
  }

  Future<void> resetPassword({required String email}) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  Future<void> updatePassword(String password) async {
    if (password.length < 8) {
      throw ArgumentError('Le mot de passe doit contenir au moins 8 caractères.');
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
        .select()
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
    required String avatarPath,
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
      'photo_url': avatarPath.trim().isEmpty ? null : avatarPath.trim(),
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
  final client = ref.watch(supabaseClientProvider);
  return AuthRepository(client);
});
