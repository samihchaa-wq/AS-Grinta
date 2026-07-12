import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SeasonPredictionItem {
  const SeasonPredictionItem({
    required this.seasonId,
    required this.predictorId,
    required this.predictorName,
    required this.playerId,
    required this.playerName,
    required this.category,
    required this.value,
    required this.isFilled,
  });

  final String seasonId;
  final String predictorId;
  final String predictorName;
  final String playerId;
  final String playerName;
  final String category;
  final int value;
  final bool isFilled;

  SeasonPredictionItem copyWith({int? value, bool? isFilled}) {
    return SeasonPredictionItem(
      seasonId: seasonId,
      predictorId: predictorId,
      predictorName: predictorName,
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

  Future<String?> _openSeasonId() async {
    final season = await _client
        .from('seasons')
        .select('id')
        .eq('status', 'open')
        .maybeSingle();
    return season?['id']?.toString();
  }

  /// Vrai quand les pronostics de saison ont été fermés par le staff (ou
  /// qu'aucune saison n'est ouverte).
  Future<bool> isLocked() async {
    final season = await _client
        .from('seasons')
        .select('season_predictions_locked_at')
        .eq('status', 'open')
        .maybeSingle();
    if (season == null) return true;
    return season['season_predictions_locked_at'] != null;
  }

  String _displayName(Map<String, dynamic> profile, String fallback) {
    final nickname = (profile['surnom'] ?? '').toString().trim();
    if (nickname.isNotEmpty) return nickname;
    final firstName = (profile['first_name'] ?? '').toString().trim();
    if (firstName.isNotEmpty) return firstName;
    return fallback;
  }

  Future<List<SeasonPredictionItem>> fetchMine() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');
    final seasonId = await _openSeasonId();
    if (seasonId == null) return const [];

    final profile = await _client
        .from('profiles')
        .select('first_name,surnom')
        .eq('id', userId)
        .maybeSingle();
    final predictorName = _displayName(
      Map<String, dynamic>.from(profile ?? const {}),
      'Compte sans nom',
    );

    final players = await _client
        .from('season_players')
        .select(
          'profile_id,is_goalkeeper_snapshot,profiles!inner(first_name,surnom,status)',
        )
        .eq('season_id', seasonId);
    final predictions = await _client
        .from('season_predictions')
        .select('player_profile_id,category,predicted_value_30,is_filled')
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
      final playerProfile = Map<String, dynamic>.from(map['profiles'] as Map);
      if (playerProfile['status'] != 'active') continue;
      final playerId = map['profile_id'].toString();
      final playerName = _displayName(playerProfile, 'Joueur sans nom');
      final categories = map['is_goalkeeper_snapshot'] == true
          ? const ['clean_sheets', 'penalty_faults']
          : const ['buts', 'passes', 'hommes_du_match', 'penalty_faults'];
      for (final category in categories) {
        final existing = byKey['$playerId:$category'];
        result.add(
          SeasonPredictionItem(
            seasonId: seasonId,
            predictorId: userId,
            predictorName: predictorName,
            playerId: playerId,
            playerName: playerName,
            category: category,
            value: int.tryParse('${existing?['predicted_value_30'] ?? 0}') ?? 0,
            isFilled: existing?['is_filled'] == true,
          ),
        );
      }
    }
    return result;
  }

  Future<List<SeasonPredictionItem>> fetchPublic() async {
    final seasonId = await _openSeasonId();
    if (seasonId == null) return const [];

    final rows = await _client.from('season_predictions').select('''
      predictor_profile_id,
      player_profile_id,
      category,
      predicted_value_30,
      is_filled,
      predictor:profiles!season_predictions_predictor_profile_id_fkey(first_name,surnom,status),
      player:profiles!season_predictions_player_profile_id_fkey(first_name,surnom,status)
    ''').eq('season_id', seasonId).eq('is_filled', true);

    final items = <SeasonPredictionItem>[];
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row);
      final predictor = Map<String, dynamic>.from(map['predictor'] as Map);
      final player = Map<String, dynamic>.from(map['player'] as Map);
      if (predictor['status'] != 'active' || player['status'] != 'active') {
        continue;
      }
      items.add(
        SeasonPredictionItem(
          seasonId: seasonId,
          predictorId: map['predictor_profile_id'].toString(),
          predictorName: _displayName(predictor, 'Compte sans nom'),
          playerId: map['player_profile_id'].toString(),
          playerName: _displayName(player, 'Joueur sans nom'),
          category: map['category'].toString(),
          value: int.tryParse('${map['predicted_value_30']}') ?? 0,
          isFilled: true,
        ),
      );
    }
    items.sort((a, b) {
      final predictor = a.predictorName.compareTo(b.predictorName);
      if (predictor != 0) return predictor;
      final player = a.playerName.compareTo(b.playerName);
      if (player != 0) return player;
      return a.category.compareTo(b.category);
    });
    return items;
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
        'predicted_value_30': item.value,
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
