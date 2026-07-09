enum AuthRole { pronostiqueur, admin, moderateur }

extension AuthRoleX on AuthRole {
  String get label {
    switch (this) {
      case AuthRole.admin:
        return 'Admin';
      case AuthRole.moderateur:
        return 'Modérateur';
      case AuthRole.pronostiqueur:
        return 'Pronostiqueur';
    }
  }

  bool get isAdmin => this == AuthRole.admin;
  bool get isModerator => this == AuthRole.moderateur;
  bool get isPronostiqueur => this == AuthRole.pronostiqueur;
}

class AuthProfile {
  const AuthProfile({
    required this.firstName,
    required this.lastName,
    this.avatarPath,
    required this.role,
    required this.isGoalkeeper,
    required this.isActive,
  });

  final String firstName;
  final String lastName;
  final String? avatarPath;
  final AuthRole role;
  final bool isGoalkeeper;
  final bool isActive;

  String get fullName => '$firstName $lastName'.trim();

  factory AuthProfile.fromJson(Map<String, dynamic> json) {
    final roleValue = (json['role'] ?? 'pronostiqueur').toString().toLowerCase();
    final role = switch (roleValue) {
      'admin' => AuthRole.admin,
      'moderateur' || 'moderator' => AuthRole.moderateur,
      _ => AuthRole.pronostiqueur,
    };

    final status = (json['status'] ?? 'active').toString().toLowerCase();

    return AuthProfile(
      firstName: (json['first_name'] ?? '').toString(),
      lastName: (json['last_name'] ?? '').toString(),
      avatarPath: json['photo_url']?.toString(),
      role: role,
      isGoalkeeper: json['is_goalkeeper'] == true,
      isActive: status == 'active',
    );
  }
}
