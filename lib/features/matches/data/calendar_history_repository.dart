import 'dart:convert';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static const _persistentKey = 'calendar_history_all_v1';

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

  Stream<List<HistoricalMatchResult>> watchAllLocalFirst() async* {
    final local = await _readPersistent();
    if (local != null) {
      _allCache = local;
      _allCacheAt = DateTime.now();
      yield local;
    }

    try {
      final fresh = await fetchAll(forceRefresh: true);
      if (local == null || !_sameSnapshot(local, fresh)) {
        yield fresh;
      }
    } catch (_) {
      if (local == null) rethrow;
    }
  }

  bool _sameSnapshot(
    List<HistoricalMatchResult> first,
    List<HistoricalMatchResult> second,
  ) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index += 1) {
      final a = first[index];
      final b = second[index];
      if (a.id != b.id ||
          a.date != b.date ||
          a.opponentName != b.opponentName ||
          a.grintaScore != b.grintaScore ||
          a.opponentScore != b.opponentScore ||
          a.isHome != b.isHome) {
        return false;
      }
    }
    return true;
  }

  Future<List<HistoricalMatchResult>> _fetchAllFromServer() async {
    final response = await _client.rpc('get_all_historical_match_results');
    final parsed = _parseRows(response);
    _allCache = parsed;
    _allCacheAt = DateTime.now();
    await _writePersistent(parsed);
    return parsed;
  }

  Future<List<HistoricalMatchResult>?> _readPersistent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_persistentKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map(
            (row) => HistoricalMatchResult(
              id: row['id']?.toString() ?? '',
              date: DateTime.tryParse(row['date']?.toString() ?? '') ??
                  DateTime(1970),
              opponentName: (row['opponent_name'] ?? 'Adversaire').toString(),
              grintaScore: (row['grinta_score'] as num?)?.toInt() ?? 0,
              opponentScore: (row['opponent_score'] as num?)?.toInt() ?? 0,
              isHome: row['is_home'] as bool? ?? true,
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePersistent(List<HistoricalMatchResult> matches) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _persistentKey,
        jsonEncode(
          matches
              .map(
                (match) => {
                  'id': match.id,
                  'date': match.date.toIso8601String(),
                  'opponent_name': match.opponentName,
                  'grinta_score': match.grintaScore,
                  'opponent_score': match.opponentScore,
                  'is_home': match.isHome,
                },
              )
              .toList(growable: false),
        ),
      );
    } catch (_) {
      // Le stockage local est une optimisation : Supabase reste la source.
    }
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
    StreamProvider<List<HistoricalMatchResult>>((ref) {
  return ref.watch(calendarHistoryRepositoryProvider).watchAllLocalFirst();
});
