import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveHandoffAdmin {
  const LiveHandoffAdmin({required this.id, required this.name});

  final String id;
  final String name;
}

class PendingLiveHandoff {
  const PendingLiveHandoff({
    required this.matchId,
    required this.fromProfileId,
    required this.toProfileId,
    required this.fromName,
    required this.toName,
    required this.expiresAt,
  });

  final String matchId;
  final String fromProfileId;
  final String toProfileId;
  final String fromName;
  final String toName;
  final DateTime expiresAt;
}

class LiveHandoffRepository {
  LiveHandoffRepository(this._client);

  final SupabaseClient _client;

  Future<List<LiveHandoffAdmin>> fetchAvailableAdmins() async {
    final currentUserId = _client.auth.currentUser?.id;
    final rows = await _client
        .from('profiles')
        .select('id,first_name,last_name')
        .eq('role', 'admin')
        .eq('status', 'active')
        .order('first_name')
        .order('last_name');

    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => row['id'].toString() != currentUserId)
        .map((row) {
      final name =
          '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim();
      return LiveHandoffAdmin(
        id: row['id'].toString(),
        name: name.isEmpty ? 'Admin sans nom' : name,
      );
    }).toList();
  }

  Future<PendingLiveHandoff?> fetchPending(String matchId) async {
    final response = await _client.from('live_control_handoffs').select('''
      match_id,
      from_profile_id,
      to_profile_id,
      expires_at,
      from_profile:profiles!live_control_handoffs_from_profile_id_fkey(first_name,last_name),
      to_profile:profiles!live_control_handoffs_to_profile_id_fkey(first_name,last_name)
    ''').eq('match_id', matchId).maybeSingle();
    if (response == null) return null;

    final row = Map<String, dynamic>.from(response);
    final expiresAt = DateTime.tryParse(row['expires_at'].toString());
    if (expiresAt == null || expiresAt.isBefore(DateTime.now().toUtc())) {
      return null;
    }
    final from = Map<String, dynamic>.from(row['from_profile'] as Map);
    final to = Map<String, dynamic>.from(row['to_profile'] as Map);
    String fullName(Map<String, dynamic> profile) {
      final value =
          '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
      return value.isEmpty ? 'Admin sans nom' : value;
    }

    return PendingLiveHandoff(
      matchId: row['match_id'].toString(),
      fromProfileId: row['from_profile_id'].toString(),
      toProfileId: row['to_profile_id'].toString(),
      fromName: fullName(from),
      toName: fullName(to),
      expiresAt: expiresAt,
    );
  }

  Future<bool> offer({
    required String matchId,
    required String controllerSessionId,
    required String targetProfileId,
  }) async {
    final result = await _client.rpc(
      'offer_live_control',
      params: {
        'p_match_id': matchId,
        'p_controller_session_id': controllerSessionId,
        'p_target_profile_id': targetProfileId,
      },
    );
    return result == true;
  }

  Future<bool> accept({
    required String matchId,
    required String controllerSessionId,
  }) async {
    final result = await _client.rpc(
      'accept_live_control',
      params: {
        'p_match_id': matchId,
        'p_controller_session_id': controllerSessionId,
      },
    );
    return result == true;
  }

  Future<bool> cancel({
    required String matchId,
    required String controllerSessionId,
  }) async {
    final result = await _client.rpc(
      'cancel_live_control_offer',
      params: {
        'p_match_id': matchId,
        'p_controller_session_id': controllerSessionId,
      },
    );
    return result == true;
  }
}

final liveHandoffRepositoryProvider = Provider<LiveHandoffRepository>((ref) {
  return LiveHandoffRepository(ref.watch(supabaseClientProvider));
});

final liveHandoffAdminsProvider =
    FutureProvider.autoDispose<List<LiveHandoffAdmin>>((ref) {
  return ref.watch(liveHandoffRepositoryProvider).fetchAvailableAdmins();
});

final pendingLiveHandoffProvider = FutureProvider.autoDispose
    .family<PendingLiveHandoff?, String>((ref, matchId) {
  return ref.watch(liveHandoffRepositoryProvider).fetchPending(matchId);
});
