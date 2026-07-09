import 'dart:math';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Modèle ──────────────────────────────────────────────────────────────────

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

  /// Surnom d'affichage. Si null, on replie sur prénom + nom.
  final String? surnom;
  final bool isGoalkeeper;
  final bool isActive;
  final String? linkedProfileId;
  final DateTime? claimedAt;
  final String? claimToken;
  final DateTime? claimExpiresAt;

  String get fullName => '$firstName $lastName'.trim();
  String get displayName {
    final s = surnom?.trim() ?? '';
    return s.isNotEmpty ? s : (fullName.isEmpty ? 'Joueur sans nom' : fullName);
  }

  bool get isClaimed => linkedProfileId != null;
  bool get hasToken => claimToken != null;
  bool get hasActiveToken => hasToken && !isTokenExpired;
  bool get isTokenExpired =>
      claimExpiresAt != null && claimExpiresAt!.isBefore(DateTime.now());
}

// ─── Repository ──────────────────────────────────────────────────────────────

class PlayersRepository {
  PlayersRepository(this._client);

  final SupabaseClient _client;

  /// ID de l'utilisateur courant (auth Supabase).
  String? get currentUserId => _client.auth.currentUser?.id;

  Future<List<PlayerItem>> fetchAll() async {
    final response = await _client
        .from('players')
        .select(
          'id, first_name, last_name, surnom, is_goalkeeper, is_active, '
          'linked_profile_id, claimed_at, claim_token, claim_expires_at',
        )
        .order('first_name')
        .order('last_name');

    return (response as List).map((row) {
      final map = Map<String, dynamic>.from(row);
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
    }).toList();
  }

  Future<void> createPlayer({
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
    await _client.from('players').insert({
      'first_name': f,
      'last_name': l,
      if (surnom != null && surnom.trim().isNotEmpty) 'surnom': surnom.trim(),
      'is_goalkeeper': isGoalkeeper,
      'is_active': true,
    });
  }

  /// Génère un token de revendication valable 7 jours.
  /// Retourne le token généré pour pouvoir l'afficher.
  Future<String> generateClaimToken(String playerId) async {
    final token = _generateUuidV4();
    final expiresAt = DateTime.now().add(const Duration(days: 7)).toUtc();
    await _client.from('players').update({
      'claim_token': token,
      'claim_expires_at': expiresAt.toIso8601String(),
    }).eq('id', playerId);
    return token;
  }

  /// Invalide le token de revendication sans archiver le joueur.
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

  Future<void> restorePlayer(String playerId) async {
    await _client.from('players').update({
      'is_active': true,
      'archived_at': null,
    }).eq('id', playerId);
  }

  /// Revendication atomique via le RPC `claim_player_profile`.
  /// Le RPC utilise un row lock (FOR UPDATE) pour éviter les conditions de course.
  /// L'argument `token` doit être un UUID valide.
  Future<void> claimProfile({
    required String token,
    required String profileId, // ignoré — le RPC utilise auth.uid() côté serveur
  }) async {
    try {
      await _client.rpc(
        'claim_player_profile',
        params: {'claim': token},
      );
    } on PostgrestException catch (e) {
      throw StateError(e.message);
    }
  }

  // ─── UUID v4 en Dart pur (pas de dépendance externe) ──────────────────────

  static String _generateUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    // Version 4
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Variant 10xx
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(hex).toList();
    return '${b[0]}${b[1]}${b[2]}${b[3]}'
        '-${b[4]}${b[5]}'
        '-${b[6]}${b[7]}'
        '-${b[8]}${b[9]}'
        '-${b[10]}${b[11]}${b[12]}${b[13]}${b[14]}${b[15]}';
  }
}

// ─── Providers ───────────────────────────────────────────────────────────────

final playersRepositoryProvider = Provider<PlayersRepository>((ref) {
  return PlayersRepository(ref.watch(supabaseClientProvider));
});

final playersListProvider = FutureProvider<List<PlayerItem>>((ref) {
  return ref.watch(playersRepositoryProvider).fetchAll();
});
