import 'dart:math';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Modèles ──────────────────────────────────────────────────────────────────

class PlayerItem {
  const PlayerItem({
    required this.id,
    required this.firstName,
    required this.lastName,
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
  final bool isGoalkeeper;
  final bool isActive;
  final String? linkedProfileId;
  final DateTime? claimedAt;
  final String? claimToken;
  final DateTime? claimExpiresAt;

  String get fullName => '$firstName $lastName'.trim();
  bool get isClaimed => claimedAt != null;
  bool get isLinked => linkedProfileId != null;

  bool get hasActiveToken =>
      claimToken != null &&
      (claimExpiresAt == null || claimExpiresAt!.isAfter(DateTime.now()));
}

// ─── Génération d'UUID v4 en Dart ─────────────────────────────────────────────

String _generateUuidV4() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

// ─── Repository ───────────────────────────────────────────────────────────────

class PlayersRepository {
  PlayersRepository(this._client);

  final SupabaseClient _client;

  /// ID de l'utilisateur courant (auth Supabase).
  String? get currentUserId => _client.auth.currentUser?.id;

  Future<List<PlayerItem>> fetchAll() async {
    final response = await _client
        .from('players')
        .select(
          'id, first_name, last_name, is_goalkeeper, is_active, '
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

  /// Revendication : un profil connecté lie son compte à un joueur via le token.
  Future<void> claimProfile({
    required String token,
    required String profileId,
  }) async {
    // Fetch by token and filter null linked_profile_id in Dart
    // (.is_ is not available in all supabase_flutter v2 variants)
    final rows = await _client
        .from('players')
        .select('id, claim_token, claim_expires_at, linked_profile_id')
        .eq('claim_token', token)
        .limit(2);

    final unlinked = (rows as List)
        .map((r) => Map<String, dynamic>.from(r))
        .where((m) => m['linked_profile_id'] == null)
        .toList();

    if (unlinked.isEmpty) {
      throw StateError(
        'Token invalide ou déjà utilisé. '
        'Demandez un nouveau lien à votre coach.',
      );
    }

    final player = unlinked.first;
    final expires = DateTime.tryParse('${player['claim_expires_at'] ?? ''}');
    if (expires != null && expires.isBefore(DateTime.now())) {
      throw StateError(
        'Ce lien a expiré. Demandez un nouveau lien à votre coach.',
      );
    }

    await _client.from('players').update({
      'linked_profile_id': profileId,
      'claimed_at': DateTime.now().toUtc().toIso8601String(),
      'claim_token': null,
      'claim_expires_at': null,
    }).eq('id', player['id'].toString());
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final playersRepositoryProvider = Provider<PlayersRepository>((ref) {
  return PlayersRepository(ref.watch(supabaseClientProvider));
});

final playersListProvider = FutureProvider<List<PlayerItem>>((ref) async {
  return ref.watch(playersRepositoryProvider).fetchAll();
});
