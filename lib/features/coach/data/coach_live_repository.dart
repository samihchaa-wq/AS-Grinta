import 'dart:async';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CoachLiveSession {
  const CoachLiveSession({
    required this.matchId,
    required this.formationCode,
    required this.lineup,
    required this.bench,
    required this.scoreUs,
    required this.scoreThem,
    required this.elapsedSeconds,
    required this.plannedDurationMinutes,
    required this.isRunning,
  });

  final String matchId;
  final String formationCode;
  final Map<String, String> lineup;
  final List<String> bench;
  final int scoreUs;
  final int scoreThem;
  final int elapsedSeconds;
  final int plannedDurationMinutes;
  final bool isRunning;

  factory CoachLiveSession.fromJson(Map<String, dynamic> json) {
    final rawLineup = json['lineup'];
    final rawBench = json['bench'];
    return CoachLiveSession(
      matchId: json['match_id'].toString(),
      formationCode: (json['formation_code'] ?? '4-3-3').toString(),
      lineup: rawLineup is Map
          ? rawLineup.map((key, value) => MapEntry('$key', '$value'))
          : const {},
      bench: rawBench is List ? rawBench.map((e) => '$e').toList() : const [],
      scoreUs: int.tryParse('${json['score_as_grinta'] ?? 0}') ?? 0,
      scoreThem: int.tryParse('${json['score_adverse'] ?? 0}') ?? 0,
      elapsedSeconds: int.tryParse('${json['elapsed_seconds'] ?? 0}') ?? 0,
      plannedDurationMinutes:
          int.tryParse('${json['planned_duration_minutes'] ?? 90}') ?? 90,
      isRunning: json['is_running'] == true,
    );
  }
}

class CoachLiveEventRecord {
  const CoachLiveEventRecord({
    required this.id,
    required this.type,
    required this.minute,
    this.scorerId,
    this.assistId,
    this.playerInId,
    this.playerOutId,
  });

  final String id;
  final String type;
  final int minute;
  final String? scorerId;
  final String? assistId;
  final String? playerInId;
  final String? playerOutId;

  factory CoachLiveEventRecord.fromJson(Map<String, dynamic> json) {
    return CoachLiveEventRecord(
      id: json['id'].toString(),
      type: json['event_type'].toString(),
      minute: int.tryParse('${json['minute'] ?? 0}') ?? 0,
      scorerId: json['scorer_profile_id']?.toString(),
      assistId: json['assist_profile_id']?.toString(),
      playerInId: json['player_in_profile_id']?.toString(),
      playerOutId: json['player_out_profile_id']?.toString(),
    );
  }
}

class CoachLiveRepository {
  CoachLiveRepository(this._client);

  final SupabaseClient _client;

  Future<String?> findCurrentMatchId() async {
    final rows = await _client
        .from('matches')
        .select('id,status,match_date,match_time')
        .inFilter('status', const ['a_venir', 'en_cours'])
        .order('match_date')
        .order('match_time')
        .limit(1);
    if ((rows as List).isEmpty) return null;
    return (rows.first as Map)['id']?.toString();
  }

  Stream<CoachLiveSession?> watchSession(String matchId) {
    return _client
        .from('coach_match_sessions')
        .stream(primaryKey: const ['match_id'])
        .eq('match_id', matchId)
        .map((rows) => rows.isEmpty
            ? null
            : CoachLiveSession.fromJson(
                Map<String, dynamic>.from(rows.first),
              ));
  }

  Stream<List<CoachLiveEventRecord>> watchEvents(String matchId) {
    return _client
        .from('coach_match_events')
        .stream(primaryKey: const ['id'])
        .eq('match_id', matchId)
        .order('created_at')
        .map(
          (rows) => rows
              .map(
                (row) => CoachLiveEventRecord.fromJson(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList(growable: false),
        );
  }

  Future<void> saveSession(CoachLiveSession session) async {
    await _client.from('coach_match_sessions').upsert(
      {
        'match_id': session.matchId,
        'formation_code': session.formationCode,
        'lineup': session.lineup,
        'bench': session.bench,
        'score_as_grinta': session.scoreUs,
        'score_adverse': session.scoreThem,
        'elapsed_seconds': session.elapsedSeconds,
        'planned_duration_minutes': session.plannedDurationMinutes,
        'is_running': session.isRunning,
        'updated_by': _client.auth.currentUser?.id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'match_id',
    );
  }

  Future<void> addGoal({
    required String matchId,
    required int minute,
    required bool isForUs,
    String? scorerId,
    String? assistId,
  }) async {
    await _client.from('coach_match_events').insert({
      'match_id': matchId,
      'event_type': isForUs ? 'goal_us' : 'goal_them',
      'minute': minute,
      'scorer_profile_id': scorerId,
      'assist_profile_id': assistId,
      'created_by': _client.auth.currentUser?.id,
    });
  }

  Future<void> addSubstitution({
    required String matchId,
    required int minute,
    String? playerInId,
    String? playerOutId,
  }) async {
    if (playerInId == null && playerOutId == null) return;
    await _client.from('coach_match_events').insert({
      'match_id': matchId,
      'event_type': 'substitution',
      'minute': minute,
      'player_in_profile_id': playerInId,
      'player_out_profile_id': playerOutId,
      'created_by': _client.auth.currentUser?.id,
    });
  }

  Future<void> deleteEvent(String eventId) async {
    await _client.from('coach_match_events').delete().eq('id', eventId);
  }
}

final coachLiveRepositoryProvider = Provider<CoachLiveRepository>((ref) {
  return CoachLiveRepository(ref.watch(supabaseClientProvider));
});
