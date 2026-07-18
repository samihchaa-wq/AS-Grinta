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

class AdminHistoricalPlayer {
  const AdminHistoricalPlayer({
    required this.id,
    required this.name,
    required this.matchesPlayed,
    required this.goals,
    required this.linkedProfileId,
  });

  final int id;
  final String name;
  final int matchesPlayed;
  final int goals;
  final String? linkedProfileId;
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

  /// Génère côté serveur un mot de passe temporaire à usage unique et force son
  /// remplacement à la prochaine connexion. Retourne le code temporaire généré
  /// (à afficher puis transmettre à l'utilisateur).
  ///
  /// La copie dans le presse-papiers est volontairement laissée à l'appelant,
  /// déclenchée par un geste explicite : sur le web (iOS Safari/PWA notamment),
  /// une écriture presse-papiers après un `await` est bloquée par le navigateur
  /// et ferait échouer toute l'opération alors que le mot de passe a déjà été
  /// réinitialisé côté serveur.
  Future<String> resetAccountPassword(String userId) async {
    final resetResponse = await _client.functions.invoke(
      'manage-user',
      body: {'action': 'reset-password', 'userId': userId},
    );
    final resetData = resetResponse.data;
    if (resetResponse.status < 200 ||
        resetResponse.status >= 300 ||
        resetData is! Map ||
        resetData['reset'] != true) {
      final message = resetData is Map && resetData['error'] != null
          ? resetData['error'].toString()
          : 'La réinitialisation a échoué.';
      throw StateError(message);
    }

    final temporaryPassword = (resetData['temporaryPassword'] ?? '').toString();
    if (temporaryPassword.isEmpty) {
      throw StateError('Le mot de passe temporaire n’a pas été retourné.');
    }

    return temporaryPassword;
  }

  Future<void> deleteAccount(String userId) async {
    final response = await _client.functions.invoke(
      'manage-user',
      body: {'action': 'delete', 'userId': userId},
    );
    final data = response.data;
    if (response.status < 200 ||
        response.status >= 300 ||
        data is! Map ||
        data['deleted'] != true) {
      final message = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'La suppression du compte a échoué.';
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
      'admin_update_profile_fields',
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

  Future<void> validateProfile(
    String profileId, {
    String? seasonPlayerId,
  }) async {
    final result = await _client.rpc(
      'staff_validate_profile',
      params: {
        'p_profile_id': profileId,
        'p_season_player_id': seasonPlayerId,
      },
    );
    if (result != true) {
      throw StateError('Le compte n’a pas pu être validé.');
    }
  }

  /// Liste des joueurs de l'historique importé (pour le rattachement).
  Future<List<AdminHistoricalPlayer>> fetchHistoricalPlayers() async {
    final rows = await _client.rpc('staff_list_historical_players');
    return (rows as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .map(
          (row) => AdminHistoricalPlayer(
            id: (row['id'] as num).toInt(),
            name: (row['player_name'] ?? '').toString(),
            matchesPlayed: (row['matches_played'] as num?)?.toInt() ?? 0,
            goals: (row['goals'] as num?)?.toInt() ?? 0,
            linkedProfileId: row['profile_id']?.toString(),
          ),
        )
        .toList();
  }

  /// Rattache (ou détache si [historicalId] est null) l'historique d'un joueur
  /// à un compte, par identifiant. Les badges sont recalculés côté serveur.
  Future<void> setHistoricalProfile({
    required String profileId,
    required int? historicalId,
  }) async {
    final result = await _client.rpc(
      'staff_set_historical_profile',
      params: {
        'p_profile_id': profileId,
        'p_historical_id': historicalId,
      },
    );
    if (result != true) {
      throw StateError("L'historique n'a pas pu être rattaché.");
    }
  }

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

  Future<void> setSeasonStatus(String seasonId, String status) async {
    if (!const ['open', 'terminee', 'archived'].contains(status)) {
      throw ArgumentError('Statut de saison invalide.');
    }
    final result = await _client.rpc(
      'set_season_status',
      params: {'p_season_id': seasonId, 'p_status': status},
    );
    if (result != true) {
      throw StateError('Le statut de la saison n’a pas pu être modifié.');
    }
  }

  Future<void> archiveSeason(String seasonId) =>
      setSeasonStatus(seasonId, 'archived');

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
