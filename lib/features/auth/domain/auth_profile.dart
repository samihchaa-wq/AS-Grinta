enum AuthRole { pronostiqueur, admin, moderateur, coach }

enum ProfileStatus { active, archived }

extension AuthRoleX on AuthRole {
  String get label {
    switch (this) {
      case AuthRole.admin:
        return 'Admin';
      case AuthRole.moderateur:
        return 'Modérateur';
      case AuthRole.coach:
        return 'Coach';
      case AuthRole.pronostiqueur:
        return 'Joueur';
    }
  }

  bool get isAdmin => this == AuthRole.admin;
  bool get isModerator => this == AuthRole.moderateur;
  bool get isCoach => this == AuthRole.coach;
  bool get isPronostiqueur => this == AuthRole.pronostiqueur;
  bool get isStaff => isAdmin || isModerator || isCoach;
}

class AuthProfile {
  const AuthProfile({
    this.id,
    this.email,
    required this.firstName,
    required this.lastName,
    this.surnom,
    this.avatarPath,
    required this.role,
    required this.isGoalkeeper,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? email;
  final String firstName;
  final String lastName;
  final String? surnom;
  final String? avatarPath;
  final AuthRole role;
  final bool isGoalkeeper;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get fullName => '$firstName $lastName'.trim();

  String get displayName {
    final nickname = surnom?.trim() ?? '';
    if (nickname.isNotEmpty) return nickname;
    final first = firstName.trim();
    if (first.isNotEmpty) return first;
    return fullName.isEmpty ? 'Utilisateur' : fullName;
  }

  String? get photoUrl => avatarPath;
  ProfileStatus get status =>
      isActive ? ProfileStatus.active : ProfileStatus.archived;

  factory AuthProfile.fromJson(Map<String, dynamic> json) {
    final roleValue =
        (json['role'] ?? 'pronostiqueur').toString().toLowerCase();
    final role = switch (roleValue) {
      'admin' => AuthRole.admin,
      'moderateur' || 'moderator' => AuthRole.moderateur,
      'coach' => AuthRole.coach,
      _ => AuthRole.pronostiqueur,
    };

    final statusValue = (json['status'] ?? 'active').toString().toLowerCase();

    return AuthProfile(
      id: json['id']?.toString(),
      email: json['email']?.toString(),
      firstName: (json['first_name'] ?? '').toString(),
      lastName: (json['last_name'] ?? '').toString(),
      surnom: json['surnom']?.toString(),
      avatarPath: json['photo_url']?.toString(),
      role: role,
      isGoalkeeper: json['is_goalkeeper'] == true,
      isActive: statusValue == 'active',
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
      updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}'),
    );
  }
}
