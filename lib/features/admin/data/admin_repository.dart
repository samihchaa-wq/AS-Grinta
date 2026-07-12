import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminProfileItem {
  const AdminProfileItem({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.passwordSet,
    required this.role,
    required this.status,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String username;
  final bool passwordSet;
  final String role;
  final String status;

  String get fullName => '$firstName $lastName'.trim();

  String get displayName {
    if (firstName.trim().isNotEmpty) return firstName.trim();
    return fullName.isEmpty ? 'Compte sans nom' : fullName;
  }
}

class AdminSeasonItem {
  const AdminSeasonItem({
    required this.id,
    required this.name,
    required this.status,
    required this.predictionsLocked,
  });

  final String id;
  final String name;
  final String status;

  /// Pronostics de saison fermés manuellement par le staff.
  final bool predictionsLocked;
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
        .select('id, name, status, season_predictions_locked_at')
        .order('name', ascending: false);
    final seasons = (seasonsRaw as List)
        .map((row) => Map<String, dynamic>.from(row))
        .map(
          (row) => AdminSeasonItem(
            id: row['id'].toString(),
            name: row['name'].toString(),
            status: row['status'].toString(),
            predictionsLocked: row['season_predictions_locked_at'] != null,
          ),
        )
        .toList();
    final openSeason = seasons.where((season) => season.status == 'open');
    final openSeasonId = openSeason.isEmpty ? null : openSeason.first.id;

    final profilesRaw = await _client.rpc('staff_list_profiles');
    final profiles = (profilesRaw as List)
        .map((row) => Map<String, dynamic>.from(row))
        .map(
          (row) => AdminProfileItem(
            id: row['id'].toString(),
            firstName: (row['first_name'] ?? '').toString(),
            lastName: (row['last_name'] ?? '').toString(),
            username: (row['username'] ?? '').toString(),
            passwordSet: row['password_set'] != false,
            role: (row['role'] ?? 'pronostiqueur').toString(),
            status: (row['status'] ?? 'active').toString(),
          ),
        )
        .toList();

    return AdminDashboardData(
      profiles: profiles,
      seasons: seasons,
      openSeasonId: openSeasonId,
    );
  }

  /// Réinitialise le mot de passe d'un compte : le joueur devra refaire une
  /// « première connexion » et choisir un nouveau mot de passe.
  Future<void> resetAccountPassword(String userId) async {
    final response = await _client.functions.invoke(
      'manage-user',
      body: {'action': 'reset-password', 'userId': userId},
    );
    final data = response.data;
    if (response.status < 200 ||
        response.status >= 300 ||
        data is! Map ||
        data['reset'] != true) {
      final message = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'La réinitialisation a échoué.';
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

  Future<void> updateProfileStatus(String profileId, String status) async {
    if (!const ['active', 'archived'].contains(status)) {
      throw ArgumentError('Statut invalide.');
    }
    await _updatePrivilegedProfileFields(profileId: profileId, status: status);
  }

  /// Ouvre (ou ré-ouvre) une saison et garantit qu'une seule reste ouverte.
  /// Retourne l'identifiant de la saison ouverte.
  Future<String> createSeason(String name) async {
    final trimmed = name.trim();
    if (!RegExp(r'^\d{4}-\d{4}$').hasMatch(trimmed)) {
      throw ArgumentError('Le nom doit respecter le format 2026-2027.');
    }
    final startYear = int.parse(trimmed.substring(0, 4));
    final endYear = int.parse(trimmed.substring(5));
    if (endYear != startYear + 1) {
      throw ArgumentError('La saison doit couvrir deux années consécutives.');
    }
    final result = await _client.rpc(
      'open_or_create_season',
      params: {'p_name': trimmed},
    );
    final id = result?.toString() ?? '';
    if (id.isEmpty) {
      throw StateError('La saison n’a pas pu être ouverte.');
    }
    return id;
  }

  Future<void> archiveSeason(String seasonId) async {
    await _client
        .from('seasons')
        .update({'status': 'archived'}).eq('id', seasonId);
  }

  /// Ouvre ou ferme les pronostics de saison (réservé au staff).
  Future<void> setSeasonPredictionsLock({
    required String seasonId,
    required bool locked,
  }) async {
    final result = await _client.rpc(
      'set_season_predictions_lock',
      params: {'p_season_id': seasonId, 'p_locked': locked},
    );
    if (result != true) {
      throw StateError('Le verrou des pronostics n’a pas pu être modifié.');
    }
  }
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.watch(supabaseClientProvider));
});

final adminDashboardProvider = FutureProvider<AdminDashboardData>((ref) {
  return ref.watch(adminRepositoryProvider).fetchDashboard();
});
