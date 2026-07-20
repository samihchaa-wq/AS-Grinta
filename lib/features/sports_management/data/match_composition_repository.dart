import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class MatchCompositionRepository {
  Future<MatchComposition?> fetchAdminComposition(String matchId);
  Future<MatchComposition?> fetchPublishedComposition(String matchId);
  Future<Set<String>> fetchGoalkeeperSeasonPlayerIds(
    List<String> seasonPlayerIds,
  );
  Future<MatchComposition> saveComposition({
    required MatchComposition composition,
    required bool allowSquadSizeException,
    String? reason,
  });
  Future<MatchComposition> publishComposition({
    required String matchId,
    required bool allowSquadSizeException,
    String? reason,
  });
}

class SupabaseMatchCompositionRepository implements MatchCompositionRepository {
  SupabaseMatchCompositionRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<MatchComposition?> fetchAdminComposition(String matchId) async {
    final response = await _client.rpc(
      'admin_get_match_composition',
      params: {'p_match_id': matchId},
    );
    return MatchComposition.tryFromRpc(response);
  }

  @override
  Future<MatchComposition?> fetchPublishedComposition(String matchId) async {
    final response = await _client.rpc(
      'get_published_match_composition',
      params: {'p_match_id': matchId},
    );
    return MatchComposition.tryFromRpc(response);
  }

  @override
  Future<Set<String>> fetchGoalkeeperSeasonPlayerIds(
    List<String> seasonPlayerIds,
  ) async {
    final permanentIds = seasonPlayerIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (permanentIds.isEmpty) return const {};
    final rows = await _client
        .from('season_players')
        .select('id')
        .inFilter('id', permanentIds)
        .eq('is_goalkeeper', true);
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .map((row) => row['id'].toString())
        .toSet();
  }

  @override
  Future<MatchComposition> saveComposition({
    required MatchComposition composition,
    required bool allowSquadSizeException,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'admin_save_match_composition',
      params: {
        'p_match_id': composition.matchId,
        'p_formation_code': _clean(composition.formationCode),
        'p_entries': [
          for (final entry in composition.entries) entry.toRpcJson(),
        ],
        'p_allow_squad_size_exception': allowSquadSizeException,
        'p_reason': _clean(reason),
      },
    );
    final saved = MatchComposition.tryFromRpc(response);
    if (saved == null) {
      throw const FormatException('Réponse de composition invalide.');
    }
    return saved;
  }

  @override
  Future<MatchComposition> publishComposition({
    required String matchId,
    required bool allowSquadSizeException,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'admin_publish_match_composition',
      params: {
        'p_match_id': matchId,
        'p_allow_squad_size_exception': allowSquadSizeException,
        'p_reason': _clean(reason),
      },
    );
    final published = MatchComposition.tryFromRpc(response);
    if (published == null) {
      throw const FormatException('Publication de composition invalide.');
    }
    return published;
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

final matchCompositionRepositoryProvider =
    Provider<MatchCompositionRepository>((ref) {
  return SupabaseMatchCompositionRepository(ref.watch(supabaseClientProvider));
});

final publishedMatchCompositionProvider = FutureProvider.autoDispose
    .family<MatchComposition?, String>((ref, matchId) {
  return ref
      .watch(matchCompositionRepositoryProvider)
      .fetchPublishedComposition(matchId);
});
