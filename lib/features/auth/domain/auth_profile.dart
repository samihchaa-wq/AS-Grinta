import 'package:as_grinta/core/utils/name_validation.dart';

enum AuthRole { pronostiqueur, admin, moderateur }

extension AuthRoleX on AuthRole {
  /// Libellé utilisateur du rôle dans l’interface du profil.
  String get label {
    switch (this) {
      case AuthRole.moderateur:
        return 'Modérateur';
      case AuthRole.admin:
        return 'Admin';
      case AuthRole.pronostiqueur:
        return 'Joueur';
    }
  }

  bool get isPronostiqueur => this == AuthRole.pronostiqueur;

  /// Le modérateur est un admin qui voit en plus le module « Modérateur » des
  /// paramètres : partout ailleurs, les deux rôles ont exactement les mêmes
  /// droits, y compris côté serveur.
  bool get isModerator => this == AuthRole.moderateur;

  bool get isAdmin => this == AuthRole.admin || isModerator;

  /// Les deux rôles privilégiés. « staff » leur est synonyme.
  bool get isStaff => isAdmin;
}

class AuthProfile {
  const AuthProfile({
    this.id,
    this.username,
    required this.firstName,
    required this.lastName,
    this.surnom = '',
    this.photoUrl,
    required this.role,
    required this.isGoalkeeper,
    required this.isActive,
    required this.mustChangePassword,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? username;
  final String firstName;
  final String lastName;
  final String? photoUrl;

  /// Surnom optionnel : s'il est renseigné, il s'affiche partout à la place du
  /// prénom.
  final String surnom;
  final AuthRole role;
  final bool isGoalkeeper;
  final bool isActive;
  final bool mustChangePassword;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get fullName =>
      capitalizePersonName('${capitalizePersonName(firstName)} $lastName');

  /// Nom affiché partout : surnom s'il est renseigné, sinon prénom. L'initiale
  /// est remise en majuscule : un prénom saisi en minuscules à l'inscription
  /// ne doit pas s'afficher ainsi dans toute l'application.
  String get displayName {
    final nick = capitalizePersonName(surnom);
    if (nick.isNotEmpty) return nick;
    final first = capitalizePersonName(firstName);
    if (first.isNotEmpty) return first;
    return fullName.isEmpty ? 'Utilisateur' : fullName;
  }

  factory AuthProfile.fromJson(Map<String, dynamic> json) {
    final roleValue =
        (json['role'] ?? 'pronostiqueur').toString().toLowerCase();
    final role = switch (roleValue) {
      'moderateur' || 'moderator' => AuthRole.moderateur,
      'admin' => AuthRole.admin,
      _ => AuthRole.pronostiqueur,
    };

    final statusValue = (json['status'] ?? 'active').toString().toLowerCase();

    return AuthProfile(
      id: json['id']?.toString(),
      username: json['username']?.toString(),
      firstName: (json['first_name'] ?? '').toString(),
      lastName: (json['last_name'] ?? '').toString(),
      surnom: (json['surnom'] ?? '').toString(),
      photoUrl: (json['photo_url']?.toString().trim().isNotEmpty ?? false)
          ? json['photo_url'].toString()
          : null,
      role: role,
      isGoalkeeper: json['is_goalkeeper'] == true,
      isActive: statusValue == 'active',
      mustChangePassword: json['must_change_password'] == true,
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
      updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}'),
    );
  }
}
