import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminProfileItem {
  const AdminProfileItem({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.surnom,
    required this.email,
    required this.role,
    required this.status,
    required this.isGoalkeeper,
    required this.inOpenSeason,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String? surnom;
  final String email;
  final String role;
  final String status;
  final bool isGoalkeeper;
  final bool inOpenSeason;

  String get fullName => '$firstName $lastName'.trim();

  String get displayName {
    final nickname = surnom?.trim() ?? '';
    if (nickname.isNotEmpty) return nickname;
    if (firstName.trim().isNotEmpty) return firstName.trim();
    return fullName.isEmpty ? 'Compte sans nom' : fullName;
  }
}

class AdminSeasonItem {
  const AdminSeasonItem({
    required this.id,
    required this.name,
    required this.status,
  });

  final String id;
  final String name;
  final String status;
}

class AdminDashboardData {
  const AdminDashboardData({
    required this.profiles,
    required this.seasons,
    required this.openSeasonId,
  });

  final List<AdminProfileItem> profiles;
  final List<AdminSeasonItem> seasons;
  final String? openSeasonId;
}

class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  Future<AdminDashboardData> fetchDashboard() async {
    final seasonsRaw = await _client
        .from('seasons')
        .select('id, name, status')
        .order('name', ascending: false);
    final seasons = (seasonsRaw as List)
        .map((row) => Map<String, dynamic>.from(row))
        .map(
          (row) => AdminSeasonItem(
            id: row['id'].toString(),
            name: row['name'].toString(),
            status: row['status'].toString(),
          ),
        )
        .toList();
    final openSeason = seasons.where((season) => season.status == 'open');
    final openSeasonId = openSeason.isEmpty ? null : openSeason.first.id;

    final memberships = <String>{};
    if (openSeasonId != null) {
      final membershipRows = await _client
          .from('season_players')
          .select('profile_id')
          .eq('season_id', openSeasonId);
      memberships.addAll(
        (membershipRows as List).map(
          (row) => Map<String, dynamic>.from(row)['profile_id'].toString(),
        ),
      );
    }

    final profilesRaw = await _client.rpc('staff_list_profiles');
    final profiles = (profilesRaw as List)
        .map((row) => Map<String, dynamic>.from(row))
        .map(
          (row) => AdminProfileItem(
            id: row['id'].toString(),
            firstName: (row['first_name'] ?? '').toString(),
            lastName: (row['last_name'] ?? '').toString(),
            surnom: row['surnom']?.toString(),
            email: (row['email'] ?? '').toString(),
            role: (row['role'] ?? 'pronostiqueur').toString(),
            status: (row['status'] ?? 'active').toString(),
            isGoalkeeper: row['is_goalkeeper'] == true,
            inOpenSeason: memberships.contains(row['id'].toString()),
          ),
        )
        .toList();

    return AdminDashboardData(
      profiles: profiles,
      seasons: seasons,
      openSeasonId: openSeasonId,
    );
  }

  Future<void> inviteAccount({
    required String email,
    required String firstName,
    required String lastName,
    String? surnom,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(cleanEmail)) {
      throw ArgumentError('Adresse email invalide.');
    }
    final response = await _client.functions.invoke(
      'manage-user',
      body: {
        'action': 'invite',
        'email': cleanEmail,
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        if ((surnom ?? '').trim().isNotEmpty) 'surnom': surnom!.trim(),
        'redirectTo': Uri.base.resolve('auth/sign-in').toString(),
      },
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'L’invitation du compte a échoué.';
      throw StateError(message);
    }
  }

  Future<void> _updatePrivilegedProfileFields({
    required String profileId,
    String? role,
    String? status,
    bool? isGoalkeeper,
  }) async {
    final result = await _client.rpc(
      'moderator_update_profile_admin_fields',
      params: {
        'p_profile_id': profileId,
        'p_role': role,
        'p_status': status,
        'p_is_goalkeeper': isGoalkeeper,
      },
    );
    if (result != true) {
      throw StateError("Le profil n'a pas pu être mis à jour.");
    }
  }

  Future<void> updateProfileRole(String profileId, String role) async {
    if (!const ['pronostiqueur', 'admin', 'moderateur'].contains(role)) {
      throw ArgumentError('Rôle invalide.');
    }
    await _updatePrivilegedProfileFields(profileId: profileId, role: role);
  }

  Future<void> updateProfileStatus(String profileId, String status) async {
    if (!const ['active', 'archived'].contains(status)) {
      throw ArgumentError('Statut invalide.');
    }
    await _updatePrivilegedProfileFields(profileId: profileId, status: status);
  }

  Future<void> updateGoalkeeper(String profileId, bool value) async {
    await _updatePrivilegedProfileFields(
      profileId: profileId,
      isGoalkeeper: value,
    );
  }

  Future<void> createSeason(String name) async {
    final trimmed = name.trim();
    if (!RegExp(r'^\d{4}-\d{4}$').hasMatch(trimmed)) {
      throw ArgumentError('Le nom doit respecter le format 2026-2027.');
    }
    final startYear = int.parse(trimmed.substring(0, 4));
    final endYear = int.parse(trimmed.substring(5));
    if (endYear != startYear + 1) {
      throw ArgumentError('La saison doit couvrir deux années consécutives.');
    }
    await _client.from('seasons').insert({'name': trimmed, 'status': 'open'});
  }

  Future<void> archiveSeason(String seasonId) async {
    await _client
        .from('seasons')
        .update({'status': 'archived'}).eq('id', seasonId);
  }

  Future<void> setSeasonMembership({
    required String seasonId,
    required AdminProfileItem profile,
    required bool selected,
  }) async {
    if (selected) {
      await _client.from('season_players').upsert(
        {
          'season_id': seasonId,
          'profile_id': profile.id,
          'is_goalkeeper_snapshot': profile.isGoalkeeper,
        },
        onConflict: 'season_id,profile_id',
      );
    } else {
      await _client
          .from('season_players')
          .delete()
          .eq('season_id', seasonId)
          .eq('profile_id', profile.id);
    }
  }
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.watch(supabaseClientProvider));
});

final adminDashboardProvider = FutureProvider<AdminDashboardData>((ref) {
  return ref.watch(adminRepositoryProvider).fetchDashboard();
});
