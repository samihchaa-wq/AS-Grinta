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

class GaugeMarker {
  const GaugeMarker({required this.value, required this.predictorNames});

  final int value;
  final List<String> predictorNames;
}

class PlayerGauge {
  const PlayerGauge({
    required this.playerId,
    required this.playerName,
    required this.isGoalkeeper,
    required this.actual,
    required this.markers,
    required this.maxValue,
  });

  final String playerId;
  final String playerName;
  final bool isGoalkeeper;
  final int actual;
  final List<GaugeMarker> markers;
  final int maxValue;
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
        .select('first_name')
        .eq('id', userId)
        .maybeSingle();
    final predictorName = _displayName(
      Map<String, dynamic>.from(profile ?? const {}),
      'Compte sans nom',
    );

    final players = await _client
        .from('season_players')
        .select('id,first_name,is_goalkeeper')
        .eq('season_id', seasonId)
        .eq('is_active', true);
    final predictions = await _client
        .from('season_predictions')
        .select('season_player_id,category,predicted_value_30,is_filled')
        .eq('season_id', seasonId)
        .eq('predictor_profile_id', userId);

    final byKey = <String, Map<String, dynamic>>{};
    for (final row in predictions as List) {
      final map = Map<String, dynamic>.from(row);
      byKey['${map['season_player_id']}:${map['category']}'] = map;
    }

    final result = <SeasonPredictionItem>[];
    for (final row in players as List) {
      final map = Map<String, dynamic>.from(row);
      final playerId = map['id'].toString();
      final playerName = _displayName(map, 'Joueur');
      final category = map['is_goalkeeper'] == true ? 'clean_sheets' : 'buts';
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
    return result;
  }

  /// Données de la jauge vivante : pour chaque joueur de l'effectif, la valeur
  /// réelle actuelle (buts, ou clean sheets pour le gardien) et tous les
  /// pronostics enregistrés, regroupés par valeur.
  Future<List<PlayerGauge>> fetchGauges() async {
    final seasonId = await _openSeasonId();
    if (seasonId == null) return const [];

    final standings = await _client
        .from('v_scorer_standings')
        .select('season_player_id,first_name,is_goalkeeper,goals,clean_sheets')
        .eq('season_id', seasonId);

    final predictions = await _client.from('season_predictions').select('''
      season_player_id, category, predicted_value_30, is_filled,
      predictor:profiles!season_predictions_predictor_profile_id_fkey(first_name,status)
    ''').eq('season_id', seasonId).eq('is_filled', true);

    final predictionsByPlayer = <String, List<Map<String, dynamic>>>{};
    for (final row in predictions as List) {
      final map = Map<String, dynamic>.from(row);
      final predictor = map['predictor'] is Map
          ? Map<String, dynamic>.from(map['predictor'] as Map)
          : const <String, dynamic>{};
      if (predictor['status'] != 'active') continue;
      predictionsByPlayer
          .putIfAbsent(map['season_player_id'].toString(), () => [])
          .add({
        'value': int.tryParse('${map['predicted_value_30']}') ?? 0,
        'name': _displayName(predictor, 'Compte sans nom'),
      });
    }

    final gauges = <PlayerGauge>[];
    for (final row in standings as List) {
      final map = Map<String, dynamic>.from(row);
      final playerId = map['season_player_id'].toString();
      final isGoalkeeper = map['is_goalkeeper'] == true;
      final actual = isGoalkeeper
          ? (int.tryParse('${map['clean_sheets'] ?? 0}') ?? 0)
          : (int.tryParse('${map['goals'] ?? 0}') ?? 0);

      final markersByValue = <int, List<String>>{};
      for (final pred in predictionsByPlayer[playerId] ?? const []) {
        markersByValue
            .putIfAbsent(pred['value'] as int, () => [])
            .add(pred['name'] as String);
      }
      final markers = markersByValue.entries
          .map((e) => GaugeMarker(value: e.key, predictorNames: e.value))
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final maxMarker =
          markers.isEmpty ? 0 : markers.map((m) => m.value).reduce((a, b) => a > b ? a : b);
      final maxValue = [actual, maxMarker, 1].reduce((a, b) => a > b ? a : b);

      gauges.add(PlayerGauge(
        playerId: playerId,
        playerName: _displayName(map, 'Joueur sans nom'),
        isGoalkeeper: isGoalkeeper,
        actual: actual,
        markers: markers,
        maxValue: maxValue,
      ));
    }

    gauges.sort((a, b) {
      final byActual = b.actual.compareTo(a.actual);
      if (byActual != 0) return byActual;
      return a.playerName.toLowerCase().compareTo(b.playerName.toLowerCase());
    });
    return gauges;
  }

  Future<void> save(SeasonPredictionItem item) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');
    if (item.value < 0) throw ArgumentError('La valeur doit être positive.');

    await _client.from('season_predictions').upsert(
      {
        'season_id': item.seasonId,
        'predictor_profile_id': userId,
        'season_player_id': item.playerId,
        'category': item.category,
        'predicted_value_30': item.value,
        'is_filled': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'season_id,predictor_profile_id,season_player_id,category',
    );
  }
}

final seasonPredictionsRepositoryProvider =
    Provider<SeasonPredictionsRepository>((ref) {
  return SeasonPredictionsRepository(ref.watch(supabaseClientProvider));
});
