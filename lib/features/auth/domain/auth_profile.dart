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
  final String role;
  final bool isGoalkeeper;
  final bool isActive;

  String get fullName => '$firstName $lastName'.trim();

  factory AuthProfile.fromJson(Map<String, dynamic> json) {
    return AuthProfile(
      firstName: (json['first_name'] ?? '').toString(),
      lastName: (json['last_name'] ?? '').toString(),
      avatarPath: json['avatar_path']?.toString(),
      role: (json['role'] ?? 'pronostiqueur').toString(),
      isGoalkeeper: json['is_goalkeeper'] == true,
      isActive: json['is_active'] != false,
    );
  }
}
