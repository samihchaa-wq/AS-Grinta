import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoricalFieldPlayer {
  const HistoricalFieldPlayer({
    required this.name,
    required this.positionLabel,
    required this.xPct,
    required this.yPct,
    required this.isGoalkeeper,
  });

  final String name;
  final String positionLabel;
  final double xPct;
  final double yPct;
  final bool isGoalkeeper;
}

class HistoricalScorer {
  const HistoricalScorer({required this.name, required this.goals});

  final String name;
  final int goals;
}

class HistoricalMatchDetail {
  const HistoricalMatchDetail({
    required this.formation,
    required this.fieldPlayers,
    required this.benchPlayers,
    required this.presentNames,
    required this.scorers,
    required this.motmNames,
  });

  final String? formation;
  final List<HistoricalFieldPlayer> fieldPlayers;
  final List<String> benchPlayers;
  final List<String> presentNames;
  final List<HistoricalScorer> scorers;
  final List<String> motmNames;

  bool get hasComposition => fieldPlayers.isNotEmpty;
  bool get isEmpty =>
      formation == null &&
      fieldPlayers.isEmpty &&
      benchPlayers.isEmpty &&
      presentNames.isEmpty &&
      scorers.isEmpty &&
      motmNames.isEmpty;
}

class HistoricalMatchDetailRepository {
  HistoricalMatchDetailRepository(this._client);

  final SupabaseClient _client;

  Future<HistoricalMatchDetail?> fetch(String matchId) async {
    final response = await _client.rpc(
      'get_historical_match_detail',
      params: {'p_match_id': matchId},
    );
    final rows = (response as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    if (rows.isEmpty) return null;
    final row = rows.first;

    final fieldPlayers = (row['field_players'] as List? ?? const [])
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .map(
          (entry) => HistoricalFieldPlayer(
            name: (entry['name'] ?? '').toString(),
            positionLabel: (entry['position_label'] ?? '').toString(),
            xPct: (entry['x_pct'] as num?)?.toDouble() ?? 50,
            yPct: (entry['y_pct'] as num?)?.toDouble() ?? 50,
            isGoalkeeper: entry['is_gk'] as bool? ?? false,
          ),
        )
        .toList(growable: false);

    final scorers = (row['scorers'] as List? ?? const [])
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .map(
          (entry) => HistoricalScorer(
            name: (entry['name'] ?? '').toString(),
            goals: (entry['goals'] as num?)?.toInt() ?? 1,
          ),
        )
        .toList(growable: false);

    List<String> stringList(Object? value) => (value as List? ?? const [])
        .map((e) => e.toString())
        .toList(growable: false);

    return HistoricalMatchDetail(
      formation: (row['formation'] as String?),
      fieldPlayers: fieldPlayers,
      benchPlayers: stringList(row['bench_players']),
      presentNames: stringList(row['present_names']),
      scorers: scorers,
      motmNames: stringList(row['motm_names']),
    );
  }
}

final historicalMatchDetailRepositoryProvider =
    Provider<HistoricalMatchDetailRepository>(
  (ref) => HistoricalMatchDetailRepository(ref.watch(supabaseClientProvider)),
);

final historicalMatchDetailProvider =
    FutureProvider.family<HistoricalMatchDetail?, String>((ref, matchId) {
  return ref.watch(historicalMatchDetailRepositoryProvider).fetch(matchId);
});
