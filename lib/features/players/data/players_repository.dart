import 'dart:math';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlayerItem {
  const PlayerItem({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.surnom,
    required this.isGoalkeeper,
    required this.isActive,
    this.linkedProfileId,
    this.claimedAt,
    this.claimToken,
    this.claimExpiresAt,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String? surnom;
  final bool isGoalkeeper;
  final bool isActive;
  final String? linkedProfileId;
  final DateTime? claimedAt;
  final String? claimToken;
  final DateTime? claimExpiresAt;

  String get fullName => '$firstName $lastName'.trim();
  String get displayName {
    final nickname = surnom?.trim() ?? '';
    if (nickname.isNotEmpty) return nickname;
    final first = firstName.trim();
    if (first.isNotEmpty) return first;
    return fullName.isEmpty ? 'Joueur sans nom' : fullName;
  }

  bool get isClaimed => linkedProfileId != null;
  bool get hasToken => claimToken != null;
  bool get hasActiveToken => hasToken && !isTokenExpired;
  bool get isTokenExpired =>
      claimExpiresAt != null && claimExpiresAt!.isBefore(DateTime.now());
}

class PlayersRepository {
  PlayersRepository(this._client);

  final SupabaseClient _client;

  Future<List<PlayerItem>> fetchAll() async {
    final response = await _client.rpc('staff_list_players');
    return (response as List).map(_fromPlayerRow).toList();
  }

  PlayerItem _fromPlayerRow(dynamic row) {
    final map = Map<String, dynamic>.from(row as Map);
    return PlayerItem(
      id: map['id'].toString(),
      firstName: (map['first_name'] ?? '').toString(),
      lastName: (map['last_name'] ?? '').toString(),
      surnom: map['surnom']?.toString(),
      isGoalkeeper: map['is_goalkeeper'] == true,
      isActive: map['is_active'] != false,
      linkedProfileId: map['linked_profile_id']?.toString(),
      claimedAt: DateTime.tryParse('${map['claimed_at'] ?? ''}'),
      claimToken: map['claim_token']?.toString(),
      claimExpiresAt: DateTime.tryParse('${map['claim_expires_at'] ?? ''}'),
    );
  }

  Future<String> createPlayer({
    required String firstName,
    required String lastName,
    String? surnom,
    required bool isGoalkeeper,
  }) async {
    final f = firstName.trim();
    final l = lastName.trim();
    if (f.isEmpty || l.isEmpty) {
      throw ArgumentError('Le prénom et le nom sont obligatoires.');
    }
    final row = await _client
        .from('players')
        .insert({
          'first_name': f,
          'last_name': l,
          if (surnom != null && surnom.trim().isNotEmpty)
            'surnom': surnom.trim(),
          'is_goalkeeper': isGoalkeeper,
          'is_active': true,
        })
        .select('id')
        .single();
    return row['id'].toString();
  }

  Future<String> createPlayerInvitation({
    required String firstName,
    required String lastName,
    String? surnom,
    required bool isGoalkeeper,
  }) async {
    final playerId = await createPlayer(
      firstName: firstName,
      lastName: lastName,
      surnom: surnom,
      isGoalkeeper: isGoalkeeper,
    );
    return generateClaimToken(playerId);
  }

  Future<String> generateClaimToken(String playerId) async {
    final token = _generateUuidV4();
    final expiresAt = DateTime.now().add(const Duration(days: 7)).toUtc();
    await _client.from('players').update({
      'claim_token': token,
      'claim_expires_at': expiresAt.toIso8601String(),
    }).eq('id', playerId);
    return token;
  }

  Future<void> revokeClaimToken(String playerId) async {
    await _client.from('players').update({
      'claim_token': null,
      'claim_expires_at': null,
    }).eq('id', playerId);
  }

  Future<void> archivePlayer(String playerId) async {
    await _client.from('players').update({
      'is_active': false,
      'archived_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', playerId);
  }

  /// Supprime définitivement la fiche du registre. Les statistiques des
  /// matchs restent intactes : elles sont rattachées au profil, pas à la
  /// fiche du registre.
  Future<void> deletePlayer(String playerId) async {
    await _client.from('players').delete().eq('id', playerId);
  }

  Future<void> restorePlayer(String playerId) async {
    await _client.from('players').update({
      'is_active': true,
      'archived_at': null,
    }).eq('id', playerId);
  }

  Future<void> claimProfile({required String token}) async {
    try {
      await _client.rpc('claim_player_profile', params: {'claim': token});
    } on PostgrestException catch (error) {
      throw StateError(error.message);
    }
  }

  static String _generateUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(hex).toList();
    return '${b[0]}${b[1]}${b[2]}${b[3]}-${b[4]}${b[5]}-${b[6]}${b[7]}-${b[8]}${b[9]}-${b[10]}${b[11]}${b[12]}${b[13]}${b[14]}${b[15]}';
  }
}

final playersRepositoryProvider = Provider<PlayersRepository>((ref) {
  return PlayersRepository(ref.watch(supabaseClientProvider));
});

final playersListProvider = FutureProvider<List<PlayerItem>>((ref) {
  return ref.watch(playersRepositoryProvider).fetchAll();
});
