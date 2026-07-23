import 'dart:typed_data';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/storage/image_mime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RosterPlayer {
  const RosterPlayer({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.isGoalkeeper,
    required this.isActive,
    required this.linkedProfileId,
    required this.linkedProfileName,
    required this.linkedProfileUsername,
    this.photoUrl,
  });

  final String id;
  final String firstName;
  final String lastName;
  final bool isGoalkeeper;
  final bool isActive;
  final String? linkedProfileId;
  final String? linkedProfileName;
  final String? linkedProfileUsername;
  final String? photoUrl;

  String get displayName {
    final first = firstName.trim();
    if (first.isNotEmpty) return first;
    return lastName.trim().isEmpty ? 'Joueur' : lastName.trim();
  }

  String get fullName => '$firstName $lastName'.trim();

  String? get linkedProfileLabel {
    final name = linkedProfileName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    final username = linkedProfileUsername?.trim() ?? '';
    return username.isEmpty ? null : username;
  }
}

class LinkableProfile {
  const LinkableProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.username,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String username;

  String get displayName {
    final first = firstName.trim();
    if (first.isNotEmpty) return first;
    final full = '$firstName $lastName'.trim();
    if (full.isNotEmpty) return full;
    final login = username.trim();
    return login.isEmpty ? 'Compte sans nom' : login;
  }
}

class RosterRepository {
  RosterRepository(this._client);

  final SupabaseClient _client;

  Future<String?> openSeasonId() async {
    final row = await _client
        .from('seasons')
        .select('id')
        .eq('status', 'open')
        .maybeSingle();
    return row?['id']?.toString();
  }

  Future<List<RosterPlayer>> fetchRoster(String seasonId) async {
    final rows = await _client.from('season_players').select('''
      id,
      first_name,
      last_name,
      is_goalkeeper,
      is_active,
      profile_id,
      photo_url,
      profiles!season_players_profile_id_fkey(
        id,
        first_name,
        status,
        photo_url
      )
    ''').eq('season_id', seasonId);
    final players = (rows as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      final profileRaw = map['profiles'];
      final profile =
          profileRaw is Map ? Map<String, dynamic>.from(profileRaw) : null;
      final profilePhoto = profile?['photo_url']?.toString();
      final seasonPhoto = map['photo_url']?.toString();
      final photo = (profilePhoto != null && profilePhoto.trim().isNotEmpty)
          ? profilePhoto
          : (seasonPhoto != null && seasonPhoto.trim().isNotEmpty)
              ? seasonPhoto
              : null;
      return RosterPlayer(
        id: map['id'].toString(),
        firstName: (map['first_name'] ?? '').toString(),
        lastName: (map['last_name'] ?? '').toString(),
        isGoalkeeper: map['is_goalkeeper'] == true,
        isActive: map['is_active'] != false,
        linkedProfileId: map['profile_id']?.toString(),
        linkedProfileName: profile?['first_name']?.toString(),
        linkedProfileUsername: null,
        photoUrl: photo,
      );
    }).toList();
    players.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return players;
  }

  Future<List<LinkableProfile>> fetchLinkableProfiles() async {
    final rows = await _client
        .from('profiles')
        .select('id,first_name,status')
        .eq('status', 'active')
        .neq('id', '00000000-0000-0000-0000-000000000001')
        .order('first_name');
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row))
        .map(
          (row) => LinkableProfile(
            id: row['id'].toString(),
            firstName: (row['first_name'] ?? '').toString(),
            lastName: '',
            username: '',
          ),
        )
        .toList();
  }

  Future<void> setProfileLink({
    required String seasonPlayerId,
    String? profileId,
  }) async {
    final result = await _client.rpc(
      'staff_set_season_player_profile',
      params: {
        'p_season_player_id': seasonPlayerId,
        'p_profile_id': profileId,
      },
    );
    if (result != true) {
      throw StateError('La liaison n’a pas pu être enregistrée.');
    }
  }

  Future<void> addPlayer({
    required String seasonId,
    required String firstName,
    required bool isGoalkeeper,
  }) async {
    final f = firstName.trim();
    if (f.isEmpty) {
      throw ArgumentError('Le prénom est obligatoire.');
    }
    final maxRows = await _client
        .from('season_players')
        .select('position')
        .eq('season_id', seasonId)
        .order('position', ascending: false)
        .limit(1);
    final maxPos = (maxRows as List).isEmpty
        ? 0
        : ((maxRows.first['position'] as num?)?.toInt() ?? 0);
    await _client.from('season_players').insert({
      'season_id': seasonId,
      'first_name': f,
      'last_name': '',
      'is_goalkeeper': isGoalkeeper,
      'is_active': true,
      'position': maxPos + 1,
    });
  }

  Future<void> updatePlayer({
    required String id,
    required String firstName,
    required bool isGoalkeeper,
  }) async {
    final f = firstName.trim();
    if (f.isEmpty) {
      throw ArgumentError('Le prénom est obligatoire.');
    }
    await _client.from('season_players').update({
      'first_name': f,
      'is_goalkeeper': isGoalkeeper,
    }).eq('id', id);
  }

  /// Téléverse la photo d'un joueur de l'effectif (utile pour les joueurs
  /// sans compte) et met à jour `season_players.photo_url`.
  Future<void> uploadPlayerPhoto({
    required String seasonPlayerId,
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final ext = fileExt.isEmpty ? 'jpg' : fileExt.toLowerCase();
    final path =
        'season/$seasonPlayerId/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('profile-photos').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: imageMimeForExt(ext),
            upsert: true,
          ),
        );
    final url = _client.storage.from('profile-photos').getPublicUrl(path);
    await _client
        .from('season_players')
        .update({'photo_url': url}).eq('id', seasonPlayerId);
  }

  Future<void> setActive({required String id, required bool active}) async {
    await _client
        .from('season_players')
        .update({'is_active': active}).eq('id', id);
  }

  Future<void> deletePlayer(String id) async {
    await _client.from('season_players').delete().eq('id', id);
  }
}

final rosterRepositoryProvider = Provider<RosterRepository>((ref) {
  return RosterRepository(ref.watch(supabaseClientProvider));
});

final openSeasonIdProvider = FutureProvider<String?>((ref) {
  return ref.watch(rosterRepositoryProvider).openSeasonId();
});

final rosterProvider =
    FutureProvider.family<List<RosterPlayer>, String>((ref, seasonId) {
  return ref.watch(rosterRepositoryProvider).fetchRoster(seasonId);
});
