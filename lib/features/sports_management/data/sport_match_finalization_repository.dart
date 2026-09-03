import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SportMatchFinalizationRepository {
  Future<SportMatchFinalization> fetchAdminContext(String matchId);

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
  Future<SportMatchFinalization?> fetchPublishedResult(String matchId) async {
    final response = await _client.rpc(
      'get_match_sport_result',
      params: {'p_match_id': matchId},
    );
    return response == null ? null : SportMatchFinalization.fromRpc(response);
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
