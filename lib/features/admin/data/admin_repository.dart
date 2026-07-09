import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminProfileItem {
  const AdminProfileItem({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    required this.status,
    required this.isGoalkeeper,
    required this.inOpenSeason,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String role;
  final String status;
  final bool isGoalkeeper;
  final bool inOpenSeason;

  String get fullName => '$firstName $lastName'.trim();
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
        (membershipRows as List)
            .map((row) => Map<String, dynamic>.from(row)['profile_id'].toString()),
      );
    }

    final profilesRaw = await _client
        .from('profiles')
        .select('id, first_name, last_name, email, role, status, is_goalkeeper')
        .order('first_name')
        .order('last_name');
    final profiles = (profilesRaw as List)
        .map((row) => Map<String, dynamic>.from(row))
        .map(
          (row) => AdminProfileItem(
            id: row['id'].toString(),
            firstName: (row['first_name'] ?? '').toString(),
            lastName: (row['last_name'] ?? '').toString(),
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

  Future<void> inviteUser({
    required String email,
    required String firstName,
    required String lastName,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (!cleanEmail.contains('@') || firstName.trim().isEmpty || lastName.trim().isEmpty) {
      throw ArgumentError('Email, prénom et nom sont obligatoires.');
    }

    final response = await _client.functions.invoke(
      'manage-user',
      body: {
        'action': 'invite',
        'email': cleanEmail,
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(_functionError(response.data));
    }
  }

  Future<void> permanentlyDeleteUser(String userId) async {
    final response = await _client.functions.invoke(
      'manage-user',
      body: {'action': 'delete', 'userId': userId},
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(_functionError(response.data));
    }
  }

  String _functionError(dynamic data) {
    if (data is Map && data['error'] != null) return data['error'].toString();
    return 'L’opération d’administration a échoué.';
  }

  Future<void> updateProfileRole(String profileId, String role) async {
    if (!const ['pronostiqueur', 'admin', 'moderateur'].contains(role)) {
      throw ArgumentError('Rôle invalide.');
    }
    await _client.from('profiles').update({'role': role}).eq('id', profileId);
  }

  Future<void> updateProfileStatus(String profileId, String status) async {
    if (!const ['active', 'archived'].contains(status)) {
      throw ArgumentError('Statut invalide.');
    }
    await _client.from('profiles').update({'status': status}).eq('id', profileId);
  }

  Future<void> updateGoalkeeper(String profileId, bool value) async {
    await _client
        .from('profiles')
        .update({'is_goalkeeper': value})
        .eq('id', profileId);
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
        .update({'status': 'archived'})
        .eq('id', seasonId);
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
