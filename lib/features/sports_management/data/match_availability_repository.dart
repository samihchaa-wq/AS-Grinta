import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/match_availability.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class MatchAvailabilityRepository {
  Future<MatchAvailability> fetchMyAvailability(String matchId);

  Future<MatchAvailability> setMyAvailability({
    required String matchId,
    required MatchAvailabilityStatus status,
    String? privateComment,
  });
}

class SupabaseMatchAvailabilityRepository
    implements MatchAvailabilityRepository {
  SupabaseMatchAvailabilityRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<MatchAvailability> fetchMyAvailability(String matchId) async {
    final response = await _client.rpc(
      'get_my_match_availability',
      params: {'p_match_id': matchId},
    );
    return MatchAvailability.fromRpc(response);
  }

  @override
  Future<MatchAvailability> setMyAvailability({
    required String matchId,
    required MatchAvailabilityStatus status,
    String? privateComment,
  }) async {
    if (status != MatchAvailabilityStatus.available &&
        status != MatchAvailabilityStatus.absent) {
      throw ArgumentError.value(
        status,
        'status',
        'Only available or absent can be submitted',
      );
    }

    await _client.rpc(
      'set_my_match_availability',
      params: {
        'p_match_id': matchId,
        'p_status': status.wireValue,
        'p_private_comment': _cleanComment(privateComment),
      },
    );

    return fetchMyAvailability(matchId);
  }

  String? _cleanComment(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

final matchAvailabilityRepositoryProvider =
    Provider<MatchAvailabilityRepository>((ref) {
  return SupabaseMatchAvailabilityRepository(
    ref.watch(supabaseClientProvider),
  );
});
