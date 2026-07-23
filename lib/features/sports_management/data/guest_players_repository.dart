import 'dart:typed_data';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/storage/image_mime.dart';
import 'package:as_grinta/features/sports_management/domain/guest_player_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class GuestPlayersRepository {
  Future<GuestCatalog> fetchCatalog({bool includeArchived = true});

  Future<MatchGuests> fetchMatchGuests(String matchId);

  Future<MatchGuests> addExistingGuest({
    required String matchId,
    required String guestPlayerId,
    String? reason,
  });

  Future<MatchGuests> createAndAddGuest({
    required String matchId,
    required String firstName,
    String? lastName,
    bool isGoalkeeper = false,
    String? reason,
  });

  Future<MatchGuests> removeGuest({
    required String matchId,
    required String participantId,
    String? reason,
  });

  Future<GuestCatalog> setArchived({
    required String guestPlayerId,
    required bool archived,
    String? reason,
  });

  Future<void> uploadGuestPhoto({
    required String guestPlayerId,
    required Uint8List bytes,
    required String fileExt,
  });
}

class SupabaseGuestPlayersRepository implements GuestPlayersRepository {
  SupabaseGuestPlayersRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<GuestCatalog> fetchCatalog({bool includeArchived = true}) async {
    final response = await _client.rpc(
      'admin_get_guest_players',
      params: {'p_include_archived': includeArchived},
    );
    return GuestCatalog.fromRpc(response);
  }

  @override
  Future<MatchGuests> fetchMatchGuests(String matchId) async {
    final response = await _client.rpc(
      'admin_get_match_guests',
      params: {'p_match_id': matchId},
    );
    return MatchGuests.fromRpc(response);
  }

  @override
  Future<MatchGuests> addExistingGuest({
    required String matchId,
    required String guestPlayerId,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'admin_add_or_reuse_match_guest',
      params: {
        'p_match_id': matchId,
        'p_guest_player_id': guestPlayerId,
        'p_first_name': null,
        'p_last_name': null,
        'p_is_goalkeeper': false,
        'p_reason': _clean(reason),
      },
    );
    return MatchGuests.fromRpc(_map(response)['match_guests']);
  }

  @override
  Future<MatchGuests> createAndAddGuest({
    required String matchId,
    required String firstName,
    String? lastName,
    bool isGoalkeeper = false,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'admin_add_or_reuse_match_guest',
      params: {
        'p_match_id': matchId,
        'p_guest_player_id': null,
        'p_first_name': firstName.trim(),
        'p_last_name': _clean(lastName),
        'p_is_goalkeeper': isGoalkeeper,
        'p_reason': _clean(reason),
      },
    );
    return MatchGuests.fromRpc(_map(response)['match_guests']);
  }

  @override
  Future<MatchGuests> removeGuest({
    required String matchId,
    required String participantId,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'admin_remove_match_guest',
      params: {
        'p_match_id': matchId,
        'p_participant_id': participantId,
        'p_reason': _clean(reason),
      },
    );
    return MatchGuests.fromRpc(response);
  }

  @override
  Future<GuestCatalog> setArchived({
    required String guestPlayerId,
    required bool archived,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'admin_set_guest_archived',
      params: {
        'p_guest_player_id': guestPlayerId,
        'p_archived': archived,
        'p_reason': _clean(reason),
      },
    );
    return GuestCatalog.fromRpc(response);
  }

  @override
  Future<void> uploadGuestPhoto({
    required String guestPlayerId,
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final ext = fileExt.isEmpty ? 'jpg' : fileExt.toLowerCase();
    final path =
        'guest/$guestPlayerId/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('profile-photos').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: imageMimeForExt(ext),
            upsert: true,
          ),
        );
    final url = _client.storage.from('profile-photos').getPublicUrl(path);
    await _client.rpc(
      'admin_set_guest_photo',
      params: {'p_guest_player_id': guestPlayerId, 'p_photo_url': url},
    );
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

final guestPlayersRepositoryProvider = Provider<GuestPlayersRepository>((ref) {
  return SupabaseGuestPlayersRepository(ref.watch(supabaseClientProvider));
});

Map<String, dynamic> _map(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const {};
}
