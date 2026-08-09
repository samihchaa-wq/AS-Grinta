import 'dart:async';

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
    required this.isHome,
  });

  final String id;
  final DateTime date;
  final String opponentName;
  final int grintaScore;
  final int opponentScore;
  final bool isHome;

  bool get isWin => grintaScore > opponentScore;
  bool get isDraw => grintaScore == opponentScore;
  bool get isLoss => grintaScore < opponentScore;
}

class CalendarHistoryRepository {
  CalendarHistoryRepository(this._client);

  final SupabaseClient _client;
  Future<List<HistoricalMatchResult>>? _allInFlight;
  List<HistoricalMatchResult>? _allCache;
  DateTime? _allCacheAt;

  static const _allCacheTtl = Duration(minutes: 10);

  List<HistoricalMatchResult> _parseRows(Object? response) {
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
        isHome: row['is_home'] as bool? ?? true,
      );
    }).toList(growable: false);
  }

  Future<List<HistoricalMatchResult>> fetchSeason(String seasonName) async {
    final response = await _client.rpc(
      'get_historical_match_results',
      params: {'p_season_name': seasonName},
    );
    return _parseRows(response);
  }

  Future<List<HistoricalMatchResult>> fetchAll({bool forceRefresh = false}) {
    final now = DateTime.now();
    final cached = _allCache;
    final cachedAt = _allCacheAt;
    if (!forceRefresh &&
        cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _allCacheTtl) {
      return Future.value(cached);
    }

    final existing = _allInFlight;
    if (!forceRefresh && existing != null) return existing;

    final request = _fetchAllFromServer();
    _allInFlight = request;
    return request.whenComplete(() {
      if (identical(_allInFlight, request)) _allInFlight = null;
    });
  }

  Future<List<HistoricalMatchResult>> _fetchAllFromServer() async {
    final response = await _client.rpc('get_all_historical_match_results');
    final parsed = _parseRows(response);
    _allCache = parsed;
    _allCacheAt = DateTime.now();
    return parsed;
  }

  void invalidateAllCache() {
    _allCache = null;
    _allCacheAt = null;
  }
}

final calendarHistoryRepositoryProvider = Provider<CalendarHistoryRepository>(
  (ref) => CalendarHistoryRepository(ref.watch(supabaseClientProvider)),
);

final allHistoricalMatchesProvider =
    FutureProvider<List<HistoricalMatchResult>>((ref) async {
  return ref.watch(calendarHistoryRepositoryProvider).fetchAll();
});
