import 'dart:async';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/live/domain/live_gameplay.dart';
import 'package:as_grinta/features/live/domain/live_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveRepository {
  LiveRepository(this._client);

  final SupabaseClient _client;
  final Map<String, LiveGameplayState> _gameplayStates = <String, LiveGameplayState>{};
  final Map<String, StreamController<LiveGameplayState>> _gameplayStreams = <String, StreamController<LiveGameplayState>>{};

  Stream<List<Map<String, dynamic>>> subscribeToLive(String matchId) {
    return _client.from('live_sessions').stream(primaryKey: ['id']).eq('match_id', matchId);
  }

  Future<LiveSessionState?> fetchLiveSession(String matchId) async {
    final response = await _client.from('live_sessions').select().eq('match_id', matchId).maybeSingle();
    if (response == null) {
      return null;
    }
    return LiveSessionState.fromJson(Map<String, dynamic>.from(response));
  }

  Future<void> createLiveSession({required String matchId}) async {
    await _client.from('live_sessions').insert({
      'match_id': matchId,
      'status': 'not_started',
      'started_at': DateTime.now().toIso8601String(),
      'last_updated_at': DateTime.now().toIso8601String(),
      'elapsed_seconds': 0,
    });
  }

  Future<void> updateLiveSession({
    required String matchId,
    required String status,
    required int elapsedSeconds,
    required String? controllerProfileId,
    required String? controllerSessionId,
  }) async {
    await _client.from('live_sessions').update({
      'status': status,
      'elapsed_seconds': elapsedSeconds,
      'controller_profile_id': controllerProfileId,
      'controller_session_id': controllerSessionId,
      'last_updated_at': DateTime.now().toIso8601String(),
    }).eq('match_id', matchId);
  }

  Future<void> claimControl({
    required String matchId,
    required String profileId,
    required String sessionId,
  }) async {
    await _client.from('live_sessions').update({
      'controller_profile_id': profileId,
      'controller_session_id': sessionId,
      'last_updated_at': DateTime.now().toIso8601String(),
    }).eq('match_id', matchId);
  }

  LiveGameplayState? loadGameplay(String matchId) {
    return _gameplayStates[matchId];
  }

  Stream<LiveGameplayState> subscribeToGameplay(String matchId) {
    final controller = _gameplayStreams.putIfAbsent(matchId, () => StreamController<LiveGameplayState>.broadcast());
    final existing = _gameplayStates[matchId];
    if (existing != null) {
      controller.add(existing);
    }
    return controller.stream;
  }

  void saveGameplay(String matchId, LiveGameplayState state) {
    _gameplayStates[matchId] = state;
    _gameplayStreams[matchId]?.add(state);
  }
}

final liveRepositoryProvider = Provider<LiveRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return LiveRepository(client);
});

final liveGameplayRepositoryProvider = Provider<LiveRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return LiveRepository(client);
});
