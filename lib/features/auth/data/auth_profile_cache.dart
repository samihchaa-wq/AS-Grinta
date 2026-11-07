import 'dart:convert';

import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dernier profil confirmé par le serveur, gardé sur l'appareil.
///
/// À chaque ouverture, l'application attendait la réponse du serveur sur le
/// profil (0,3 à 0,5 s, davantage sur un réseau faible) avant d'afficher le
/// calendrier. Avec cette copie, elle affiche tout de suite le dernier profil
/// connu et le serveur confirme juste après.
///
/// Garde-fous :
/// - seule une copie d'un compte actif, sans changement de mot de passe en
///   attente, est gardée ; tout autre état efface la copie ;
/// - la copie est liée au compte de la session restaurée : un autre compte
///   connecté sur le même appareil ne la lit jamais ;
/// - elle ne donne aucun droit : le serveur continue de vérifier chaque
///   lecture et chaque écriture, et sa réponse sur le profil remplace la copie
///   dès qu'elle arrive (déconnexion d'un compte devenu inactif comprise).
class AuthProfileCache {
  AuthProfileCache({required String? Function() currentUserId})
      : _currentUserId = currentUserId;

  final String? Function() _currentUserId;

  String? _userId() {
    try {
      final id = _currentUserId();
      return id == null || id.isEmpty ? null : id;
    } catch (_) {
      // Client indisponible (démarrage échoué, tests) : pas de copie.
      return null;
    }
  }

  static const _keyPrefix = 'auth_profile_v1_';

  /// Copie du compte de la session courante, ou `null`.
  Future<AuthProfile?> read() async {
    final userId = _userId();
    if (userId == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_keyPrefix$userId');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final profile = AuthProfile.fromJson(Map<String, dynamic>.from(decoded));
      if (profile.id != userId || !_isKeepable(profile)) return null;
      return profile;
    } catch (_) {
      return null;
    }
  }

  /// Enregistre la réponse du serveur, ou efface la copie si ce profil ne
  /// doit pas être gardé.
  Future<void> remember(AuthProfile? profile) async {
    final userId = _userId();
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (profile == null || profile.id != userId || !_isKeepable(profile)) {
        await prefs.remove('$_keyPrefix$userId');
        return;
      }
      await prefs.setString('$_keyPrefix$userId', jsonEncode(_toJson(profile)));
    } catch (_) {
      // Au mieux : sans copie, l'ouverture attend simplement le serveur.
    }
  }

  /// Efface toutes les copies de l'appareil (déconnexion).
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith(_keyPrefix)) await prefs.remove(key);
      }
    } catch (_) {}
  }

  static bool _isKeepable(AuthProfile profile) =>
      profile.isActive && !profile.mustChangePassword;

  static Map<String, Object?> _toJson(AuthProfile profile) => {
        'id': profile.id,
        'username': profile.username,
        'first_name': profile.firstName,
        'last_name': profile.lastName,
        'surnom': profile.surnom,
        'photo_url': profile.photoUrl,
        'role': profile.role.isAdmin ? 'admin' : 'pronostiqueur',
        'is_goalkeeper': profile.isGoalkeeper,
        'status': profile.status,
        'must_change_password': profile.mustChangePassword,
        'created_at': profile.createdAt?.toIso8601String(),
        'updated_at': profile.updatedAt?.toIso8601String(),
      };
}
