import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/internal_match_composition.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InternalMatchCompositionRepository {
  InternalMatchCompositionRepository(this._client);

  final SupabaseClient _client;

  Future<InternalMatchComposition?> fetch(String matchId) async {
    final response = await _client.rpc(
      'admin_get_internal_composition',
      params: {'p_match_id': matchId},
    );
    return InternalMatchComposition.tryFromRpc(response);
  }

  Future<InternalMatchComposition> save({
    required String matchId,
    required String team1Name,
    required String team2Name,
    required List<InternalCompositionEntry> entries,
  }) async {
    final response = await _client.rpc(
      'admin_save_internal_composition',
      params: {
        'p_match_id': matchId,
        'p_team1_name': team1Name,
        'p_team2_name': team2Name,
        'p_entries': [for (final entry in entries) entry.toRpcJson()],
      },
    );
    final saved = InternalMatchComposition.tryFromRpc(response);
    if (saved == null) {
      throw const FormatException('Composition entre nous invalide.');
    }
    return saved;
  }
}

final internalMatchCompositionRepositoryProvider =
    Provider<InternalMatchCompositionRepository>((ref) {
  return InternalMatchCompositionRepository(ref.watch(supabaseClientProvider));
});

final internalMatchCompositionProvider = FutureProvider.autoDispose
    .family<InternalMatchComposition?, String>((ref, matchId) {
  return ref.watch(internalMatchCompositionRepositoryProvider).fetch(matchId);
});
