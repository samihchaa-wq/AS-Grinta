import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/internal_match_composition.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InternalMatchCompositionRepository {
  InternalMatchCompositionRepository(this._client);

  final SupabaseClient _client;

  Future<InternalMatchComposition?> fetch(String matchId) async {
    final response = await _client.rpc(
      'get_internal_composition',
      params: {'p_match_id': matchId},
    );
    return InternalMatchComposition.tryFromRpc(response);
  }

  /// Ancien chemin de sauvegarde, conservé pour les clients déjà ouverts au
  /// moment du déploiement de la composition visuelle.
  Future<InternalMatchComposition> save({
    required String matchId,
    required String team1Name,
    required String team2Name,
    required List<InternalCompositionEntry> entries,
    String team1JerseyId = 'orange',
    String team2JerseyId = 'blue',
  }) async {
    final response = await _client.rpc(
      'admin_save_internal_composition_v2',
      params: {
        'p_match_id': matchId,
        'p_team1_name': team1Name,
        'p_team2_name': team2Name,
        'p_team1_jersey': team1JerseyId,
        'p_team2_jersey': team2JerseyId,
        'p_entries': [for (final entry in entries) entry.toRpcJson()],
      },
    );
    return _parseSaved(response);
  }

  /// Sauvegarde stricte de la nouvelle composition visuelle.
  Future<InternalMatchComposition> saveVisual({
    required String matchId,
    required String team1Name,
    required String team2Name,
    required String team1FormationCode,
    required String team2FormationCode,
    required List<InternalCompositionEntry> entries,
    String team1JerseyId = 'orange',
    String team2JerseyId = 'blue',
  }) async {
    final response = await _client.rpc(
      'admin_save_internal_composition_v3',
      params: {
        'p_match_id': matchId,
        'p_team1_name': team1Name,
        'p_team2_name': team2Name,
        'p_team1_jersey': team1JerseyId,
        'p_team2_jersey': team2JerseyId,
        'p_team1_formation': team1FormationCode,
        'p_team2_formation': team2FormationCode,
        'p_entries': [for (final entry in entries) entry.toRpcJson()],
      },
    );
    return _parseSaved(response);
  }

  /// Réinitialise explicitement les deux terrains sans affaiblir la validation
  /// de [saveVisual]. Les noms et maillots sont conservés côté serveur.
  Future<InternalMatchComposition> resetVisual(String matchId) async {
    final response = await _client.rpc(
      'admin_reset_internal_composition',
      params: {'p_match_id': matchId},
    );
    return _parseSaved(response);
  }

  InternalMatchComposition _parseSaved(Object? response) {
    final saved = InternalMatchComposition.tryFromRpc(response);
    if (saved == null) {
      throw const FormatException('Composition entre nous invalide.');
    }
    return saved;
  }
}

final internalMatchCompositionRepositoryProvider =
    Provider<InternalMatchCompositionRepository>((ref) {
  return InternalMatchCompositionRepository(
    ref.watch(supabaseClientProvider),
  );
});

final internalMatchCompositionProvider = FutureProvider.autoDispose
    .family<InternalMatchComposition?, String>((ref, matchId) {
  return ref.watch(internalMatchCompositionRepositoryProvider).fetch(matchId);
});
