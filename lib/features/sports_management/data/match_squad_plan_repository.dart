import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class MatchSquadPlanRepository {
  Future<MatchComposition> savePlan({
    required MatchComposition composition,
    String? reason,
  });

  Future<MatchComposition> publishPlan({
    required MatchComposition composition,
    String? reason,
  });
}

class SupabaseMatchSquadPlanRepository implements MatchSquadPlanRepository {
  SupabaseMatchSquadPlanRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<MatchComposition> savePlan({
    required MatchComposition composition,
    String? reason,
  }) async {
    return _run(
      'admin_save_match_squad_plan',
      composition: composition,
      reason: reason,
    );
  }

  @override
  Future<MatchComposition> publishPlan({
    required MatchComposition composition,
    String? reason,
  }) async {
    return _run(
      'admin_publish_match_squad_plan',
      composition: composition,
      reason: reason,
    );
  }

  Future<MatchComposition> _run(
    String rpc, {
    required MatchComposition composition,
    String? reason,
  }) async {
    final response = await _client.rpc(
      rpc,
      params: {
        'p_match_id': composition.matchId,
        'p_formation_code': _clean(composition.formationCode),
        'p_entries': [
          for (final entry in composition.entries) entry.toRpcJson(),
        ],
        'p_reason': _clean(reason),
      },
    );
    final result = MatchComposition.tryFromRpc(response);
    if (result == null) {
      throw const FormatException('Réponse du plan de sélection invalide.');
    }
    return result;
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

final matchSquadPlanRepositoryProvider = Provider<MatchSquadPlanRepository>((
  ref,
) {
  return SupabaseMatchSquadPlanRepository(ref.watch(supabaseClientProvider));
});
