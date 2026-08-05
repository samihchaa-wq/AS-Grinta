import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoricalMatchResult {
  const HistoricalMatchResult({
    required this.id,
    required this.date,
    required this.opponentName,
    required this.grintaScore,
    required this.opponentScore,
  });

  final String id;
  final DateTime date;
  final String opponentName;
  final int grintaScore;
  final int opponentScore;

  bool get isWin => grintaScore > opponentScore;
  bool get isDraw => grintaScore == opponentScore;
  bool get isLoss => grintaScore < opponentScore;
}

class CalendarHistoryRepository {
  CalendarHistoryRepository(this._client);

  final SupabaseClient _client;

  Future<List<HistoricalMatchResult>> fetchSeason(String seasonName) async {
    final response = await _client.rpc(
      'get_historical_match_results',
      params: {'p_season_name': seasonName},
    );

    return (response as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .map((row) {
      final rawDate = row['match_date']?.toString() ?? '';
      return HistoricalMatchResult(
        id: row['id']?.toString() ?? '',
        date: DateTime.tryParse(rawDate) ?? DateTime(1970),
        opponentName: (row['opponent_name'] ?? 'Adversaire').toString(),
        grintaScore: (row['score_as_grinta'] as num?)?.toInt() ?? 0,
        opponentScore: (row['score_adverse'] as num?)?.toInt() ?? 0,
      );
    }).toList(growable: false);
  }
}

final calendarHistoryRepositoryProvider = Provider<CalendarHistoryRepository>(
  (ref) => CalendarHistoryRepository(ref.watch(supabaseClientProvider)),
);
