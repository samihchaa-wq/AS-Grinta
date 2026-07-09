import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SeasonPredictionItem {
  const SeasonPredictionItem({
    required this.seasonId,
    required this.playerId,
    required this.playerName,
    required this.category,
    required this.value,
    required this.isFilled,
  });

  final String seasonId;
  final String playerId;
  final String playerName;
  final String category;
  final int value;
  final bool isFilled;

  SeasonPredictionItem copyWith({int? value, bool? isFilled}) {
    return SeasonPredictionItem(
      seasonId: seasonId,
      playerId: playerId,
      playerName: playerName,
      category: category,
      value: value ?? this.value,
      isFilled: isFilled ?? this.isFilled,
    );
  }
}

class SeasonPredictionsRepository {
  SeasonPredictionsRepository(this._client);

  final SupabaseClient _client;

  Future<List<SeasonPredictionItem>> fetchMine() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');

    final season = await _client
        .from('seasons')
        .select('id')
        .eq('status', 'open')
        .maybeSingle();
    if (season == null) return const [];
    final seasonId = season['id'].toString();

    final players = await _client
        .from('season_players')
        .select('profile_id, is_goalkeeper_snapshot, profiles!inner(first_name, last_name, status)')
        .eq('season_id', seasonId);
    final predictions = await _client
        .from('season_predictions')
        .select('player_profile_id, category, predicted_value_20, is_filled')
        .eq('season_id', seasonId)
        .eq('predictor_profile_id', userId);

    final byKey = <String, Map<String, dynamic>>{};
    for (final row in predictions as List) {
      final map = Map<String, dynamic>.from(row);
      byKey['${map['player_profile_id']}:${map['category']}'] = map;
    }

    final result = <SeasonPredictionItem>[];
    for (final row in players as List) {
      final map = Map<String, dynamic>.from(row);
      final profile = Map<String, dynamic>.from(map['profiles'] as Map);
      if (profile['status'] != 'active') continue;
      final playerId = map['profile_id'].toString();
      final name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
      final isGoalkeeper = map['is_goalkeeper_snapshot'] == true;
      final categories = isGoalkeeper
          ? const ['clean_sheets']
          : const ['buts', 'passes', 'hommes_du_match'];
      for (final category in categories) {
        final existing = byKey['$playerId:$category'];
        result.add(
          SeasonPredictionItem(
            seasonId: seasonId,
            playerId: playerId,
            playerName: name.isEmpty ? 'Joueur sans nom' : name,
            category: category,
            value: int.tryParse('${existing?['predicted_value_20'] ?? 0}') ?? 0,
            isFilled: existing?['is_filled'] == true,
          ),
        );
      }
    }
    return result;
  }

  Future<void> save(SeasonPredictionItem item) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');
    if (item.value < 0) throw ArgumentError('La valeur doit être positive.');

    await _client.from('season_predictions').upsert(
      {
        'season_id': item.seasonId,
        'predictor_profile_id': userId,
        'player_profile_id': item.playerId,
        'category': item.category,
        'predicted_value_20': item.value,
        'is_filled': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'season_id,predictor_profile_id,player_profile_id,category',
    );
  }
}

final seasonPredictionsRepositoryProvider =
    Provider<SeasonPredictionsRepository>((ref) {
  return SeasonPredictionsRepository(ref.watch(supabaseClientProvider));
});
