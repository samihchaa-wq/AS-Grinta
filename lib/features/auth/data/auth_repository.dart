import 'dart:async';
import 'dart:typed_data';

import 'package:as_grinta/core/config/app_config.dart';
import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/security/password_policy.dart';
import 'package:as_grinta/core/storage/image_mime.dart';
import 'package:as_grinta/core/storage/profile_photo_urls.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _profilePhotoUploadTimeout = Duration(seconds: 15);
const _profilePhotoWriteTimeout = Duration(seconds: 12);
const _profilePhotoReadTimeout = Duration(seconds: 8);
const _profilePhotoCleanupTimeout = Duration(seconds: 8);

class ProfilePhotoUploadOutcomeUnknown implements Exception {
  const ProfilePhotoUploadOutcomeUnknown();

  @override
  String toString() => 'Profile photo upload outcome is unknown.';
}

class ProfilePhotoWriteOutcomeUnknown implements Exception {
  const ProfilePhotoWriteOutcomeUnknown();

  @override
  String toString() => 'Profile photo reference write outcome is unknown.';
}

class ProfilePhotoWriteConfirmedButRefreshFailed implements Exception {
  const ProfilePhotoWriteConfirmedButRefreshFailed();

  @override
  String toString() =>
      'Profile photo was saved but the refreshed profile could not be read.';
}

Future<void> uploadProfilePhotoObjectWithRetry({
  required Future<void> Function() upload,
  Duration timeout = _profilePhotoUploadTimeout,
  int maxAttempts = 2,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      await upload().timeout(timeout);
      return;
    } on StorageException {
      // Le serveur Storage a répondu explicitement : ce n'est pas un accusé
      // réseau perdu et l'appelant doit conserver cette erreur certaine.
      rethrow;
    } catch (_) {
      // Le chemin est stable et l'upload est en upsert : un second essai ne
      // crée pas un nouvel objet si le premier accusé réseau s'est perdu.
    }
  }
  throw const ProfilePhotoUploadOutcomeUnknown();
}

Future<void> confirmProfilePhotoReferenceWrite({
  required Future<void> Function() submit,
  required Future<String?> Function() readBack,
  required Future<void> Function() cleanup,
  required String expectedPath,
  Duration writeTimeout = _profilePhotoWriteTimeout,
  Duration readTimeout = _profilePhotoReadTimeout,
  Duration cleanupTimeout = _profilePhotoCleanupTimeout,
}) async {
  Future<void> bestEffortCleanup() async {
    try {
      await cleanup().timeout(cleanupTimeout);
    } catch (_) {
      // La suppression est compensatoire : elle ne doit jamais masquer la
      // cause originale de l'échec de sauvegarde.
    }
  }

  try {
    await submit().timeout(writeTimeout);
    return;
  } on PostgrestException {
    await bestEffortCleanup();
    rethrow;
  } on StateError {
    await bestEffortCleanup();
    rethrow;
  } catch (_) {
    // Réponse réseau perdue : la base peut avoir validé photo_url. Il serait
    // dangereux de supprimer le fichier avant d'avoir relu la source de vérité.
  }

  try {
    final currentPath = await readBack().timeout(readTimeout);
    if (currentPath == expectedPath) {
      return;
    }
    await bestEffortCleanup();
    throw StateError('La photo du profil n’a pas pu être enregistrée.');
  } on StateError {
    rethrow;
  } catch (_) {
    // Impossible de savoir si la référence a été écrite : on conserve le
    // fichier. Le supprimer pourrait casser un profil déjà mis à jour.
    throw const ProfilePhotoWriteOutcomeUnknown();
  }
}

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;
  final Map<bool, Future<AuthProfile?>> _profileFetchesInFlight = {};

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  bool get hasSession =>
      _client.auth.currentSession != null || _client.auth.currentUser != null;

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
    _profileFetchesInFlight.clear();
    // Les URLs signées des photos appartiennent au compte qui se déconnecte :
    // elles ne doivent pas survivre à la session suivante.
    await ProfilePhotoUrlCache.instance.clear();
    await _client.auth.signOut();
  }

  Future<AuthProfile?> fetchProfile({bool retryAfterSignIn = false}) {
    if (_client.auth.currentUser == null) return Future.value(null);

    final existing = _profileFetchesInFlight[retryAfterSignIn];
    if (existing != null) return existing;

    final request = _fetchProfileFromServer(
      retryAfterSignIn: retryAfterSignIn,
    );
    _profileFetchesInFlight[retryAfterSignIn] = request;
    return request.whenComplete(() {
      if (identical(_profileFetchesInFlight[retryAfterSignIn], request)) {
        _profileFetchesInFlight.remove(retryAfterSignIn);
      }
    });
  }

  Future<AuthProfile?> _fetchProfileFromServer({
    required bool retryAfterSignIn,
  }) async {
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

    final updated = await _client
        .from('profiles')
        .update({
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
          'surnom': (surnom ?? '').trim(),
        })
        .eq('id', userId)
        .select('id')
        .maybeSingle();
    if (updated == null) {
      throw StateError('Le profil n’a pas pu être modifié.');
    }

    // `profiles` est la source de vérité de l'identité affichée dans l'app.
    // Les métadonnées Auth ne servent qu'au bootstrap initial d'un compte ;
    // les réécrire ici créerait une seconde étape susceptible d'échouer après
    // une sauvegarde de profil déjà réussie.
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

    // Un retry reprend exactement le même chemin avec upsert=true : si le
    // premier upload a réussi mais que son accusé s'est perdu, la seconde
    // tentative ne crée pas un second objet.
    await uploadProfilePhotoObjectWithRetry(
      upload: () async {
        await bucket.uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: image.mimeType,
            upsert: true,
          ),
        );
      },
    );

    // Le bucket profile-photos est privé : une URL publique y renvoie
    // systématiquement « Bucket not found ». On stocke le chemin relatif, que
    // PlayerAvatar resigne à l'affichage.
    await confirmProfilePhotoReferenceWrite(
      expectedPath: path,
      submit: () async {
        final updated = await _client
            .from('profiles')
            .update({'photo_url': path})
            .eq('id', userId)
            .select('id')
            .maybeSingle();
        if (updated == null) {
          throw StateError('La photo du profil n’a pas pu être enregistrée.');
        }
      },
      readBack: () async {
        final current = await _client
            .from('profiles')
            .select('photo_url')
            .eq('id', userId)
            .maybeSingle();
        return current?['photo_url']?.toString();
      },
      cleanup: () async {
        await bucket.remove([path]);
      },
    );

    _profileFetchesInFlight.clear();
    try {
      final profile = await fetchProfile();
      if (profile == null) {
        throw StateError('Le profil mis à jour est introuvable.');
      }
      return profile;
    } catch (_) {
      // La référence photo_url est déjà confirmée. Ne surtout pas compenser
      // en supprimant le fichier parce qu'un simple refresh du profil échoue.
      throw const ProfilePhotoWriteConfirmedButRefreshFailed();
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});
