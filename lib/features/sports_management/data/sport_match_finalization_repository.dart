import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SportMatchFinalizationRepository {
  Future<SportMatchFinalization> fetchAdminContext(String matchId);

  Future<SportMatchFinalization> finalize({
    required SportMatchFinalization finalization,
    String? reason,
  });

  Future<SportMatchFinalization?> fetchPublishedResult(String matchId);
}

class SupabaseSportMatchFinalizationRepository
    implements SportMatchFinalizationRepository {
  SupabaseSportMatchFinalizationRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<SportMatchFinalization> fetchAdminContext(String matchId) async {
    final response = await _client.rpc(
      'admin_get_match_sport_finalization',
      params: {'p_match_id': matchId},
    );
    return SportMatchFinalization.fromRpc(response);
  }

  @override
  Future<SportMatchFinalization> finalize({
    required SportMatchFinalization finalization,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'admin_finalize_match_sport_postgame',
      params: {
        'p_match_id': finalization.matchId,
        'p_score_as_grinta': finalization.scoreAsGrinta,
        'p_score_adverse': finalization.scoreAdverse,
        'p_participants': [
          for (final participant in finalization.participants)
            participant.toRpcJson(),
        ],
        'p_reason': _clean(reason),
      },
    );
    return SportMatchFinalization.fromRpc(response);
  }

  @override
  Future<SportMatchFinalization?> fetchPublishedResult(String matchId) async {
    final response = await _client.rpc(
      'get_match_sport_result',
      params: {'p_match_id': matchId},
    );
    return response == null ? null : SportMatchFinalization.fromRpc(response);
  }

  String? _clean(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}

final sportMatchFinalizationRepositoryProvider =
    Provider<SportMatchFinalizationRepository>((ref) {
  return SupabaseSportMatchFinalizationRepository(
    ref.watch(supabaseClientProvider),
  );
});

final publishedSportMatchResultProvider = FutureProvider.autoDispose
    .family<SportMatchFinalization?, String>((ref, matchId) {
  return ref
      .watch(sportMatchFinalizationRepositoryProvider)
      .fetchPublishedResult(matchId);
});
