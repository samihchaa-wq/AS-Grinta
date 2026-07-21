import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/sports_management/domain/match_availability_board.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class MatchAvailabilityBoardRepository {
  Future<MatchAvailabilityBoard> fetchBoard(String matchId);
}

class SupabaseMatchAvailabilityBoardRepository
    implements MatchAvailabilityBoardRepository {
  SupabaseMatchAvailabilityBoardRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<MatchAvailabilityBoard> fetchBoard(String matchId) async {
    final response = await _client.rpc(
      'get_match_availability_board',
      params: {'p_match_id': matchId},
    );
    return MatchAvailabilityBoard.fromRpc(response);
  }
}

final matchAvailabilityBoardRepositoryProvider =
    Provider<MatchAvailabilityBoardRepository>((ref) {
  return SupabaseMatchAvailabilityBoardRepository(
    ref.watch(supabaseClientProvider),
  );
});

final matchAvailabilityBoardProvider = FutureProvider.autoDispose
    .family<MatchAvailabilityBoard?, String>((ref, matchId) async {
  if (!ref.watch(sportsManagementEnabledProvider)) return null;
  return ref
      .watch(matchAvailabilityBoardRepositoryProvider)
      .fetchBoard(matchId);
});
