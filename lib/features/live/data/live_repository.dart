import 'dart:async';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/live/domain/live_gameplay.dart';
import 'package:as_grinta/features/live/domain/live_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveRepository {
  LiveRepository(this._client);

  final SupabaseClient _client;

  Stream<List<Map<String, dynamic>>> subscribeToLive(String matchId) {
    return _client
        .from('live_sessions')
        .stream(primaryKey: ['id'])
        .eq('match_id', matchId);
  }

  Future<LiveSessionState?> fetchLiveSession(String matchId) async {
    final response = await _client
        .from('live_sessions')
        .select()
        .eq('match_id', matchId)
        .maybeSingle();
    if (response == null) return null;
    return LiveSessionState.fromJson(Map<String, dynamic>.from(response));
  }

  Future<Map<String, dynamic>> _requireSession(String matchId) async {
    final response = await _client
        .from('live_sessions')
        .select('id, formation')
        .eq('match_id', matchId)
        .maybeSingle();
    if (response == null) {
      throw StateError('Aucune session live trouvée pour ce match.');
    }
    return Map<String, dynamic>.from(response);
  }

  Future<void> createLiveSession({required String matchId}) async {
    await _client.from('live_sessions').insert({
      'match_id': matchId,
      'status': 'not_started',
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
      'clock_started_at': status == 'running'
          ? DateTime.now().toUtc().toIso8601String()
          : null,
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
      'controller_disconnected_at': null,
    }).eq('match_id', matchId);
  }

  Future<LiveGameplayState> fetchGameplay({
    required String matchId,
    required List<LivePlayer> players,
    String fallbackFormation = '4-4-2',
  }) async {
    final session = await _requireSession(matchId);
    final liveSessionId = session['id'].toString();
    final formation = (session['formation'] ?? fallbackFormation).toString();

    final positionsResponse = await _client
        .from('live_positions')
        .select('profile_id, slot_code')
        .eq('live_session_id', liveSessionId);
    final goalsResponse = await _client
        .from('goals')
        .select()
        .eq('match_id', matchId)
        .order('created_order');
    final substitutionsResponse = await _client
        .from('substitutions')
        .select()
        .eq('live_session_id', liveSessionId)
        .order('created_at');

    final lineup = <String, String>{};
    for (final row in positionsResponse as List) {
      final map = Map<String, dynamic>.from(row);
      final slot = map['slot_code']?.toString();
      final profileId = map['profile_id']?.toString();
      if (slot != null && profileId != null) lineup[slot] = profileId;
    }

    final lineupIds = lineup.values.toSet();
    final bench = players
        .map((player) => player.id)
        .where((id) => !lineupIds.contains(id))
        .toList();

    final goals = (goalsResponse as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      return LiveGoal(
        id: map['id'].toString(),
        team: map['team'] == 'as_grinta' ? 'grinta' : 'adversaire',
        minute: map['minute'] as int,
        type: _goalTypeFromDatabase(map['goal_type']?.toString()),
        scorerId: map['scorer_profile_id']?.toString(),
        assisterId: map['assist_profile_id']?.toString(),
      );
    }).toList();

    final substitutions = <LiveSubstitution>[];
    final rows = (substitutionsResponse as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final consumedInRows = <int>{};

    for (var index = 0; index < rows.length; index++) {
      final outRow = rows[index];
      if (outRow['action'] != 'out') continue;
      final minute = outRow['minute'] as int;

      var inIndex = -1;
      for (var candidate = index + 1; candidate < rows.length; candidate++) {
        final row = rows[candidate];
        if (consumedInRows.contains(candidate)) continue;
        if (row['action'] == 'in' && row['minute'] == minute) {
          inIndex = candidate;
          break;
        }
      }

      if (inIndex == -1) continue;
      consumedInRows.add(inIndex);
      final inRow = rows[inIndex];
      substitutions.add(
        LiveSubstitution(
          id: '${outRow['id']}:${inRow['id']}',
          minute: minute,
          inPlayerId: inRow['profile_id'].toString(),
          outPlayerId: outRow['profile_id'].toString(),
        ),
      );
    }

    return LiveGameplayState(
      players: players,
      formationKey: formation,
      lineup: lineup,
      bench: bench,
      goals: goals,
      substitutions: substitutions,
    );
  }

  Stream<LiveGameplayState> subscribeToGameplay({
    required String matchId,
    required List<LivePlayer> players,
    String fallbackFormation = '4-4-2',
  }) async* {
    yield await fetchGameplay(
      matchId: matchId,
      players: players,
      fallbackFormation: fallbackFormation,
    );

    final session = await _requireSession(matchId);
    final liveSessionId = session['id'].toString();
    final controller = StreamController<LiveGameplayState>();
    final subscriptions = <StreamSubscription<dynamic>>[];

    Future<void> reload() async {
      if (controller.isClosed) return;
      try {
        controller.add(
          await fetchGameplay(
            matchId: matchId,
            players: players,
            fallbackFormation: fallbackFormation,
          ),
        );
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      }
    }

    subscriptions.add(
      _client
          .from('live_positions')
          .stream(primaryKey: ['id'])
          .eq('live_session_id', liveSessionId)
          .listen((_) => reload()),
    );
    subscriptions.add(
      _client
          .from('goals')
          .stream(primaryKey: ['id'])
          .eq('match_id', matchId)
          .listen((_) => reload()),
    );
    subscriptions.add(
      _client
          .from('substitutions')
          .stream(primaryKey: ['id'])
          .eq('live_session_id', liveSessionId)
          .listen((_) => reload()),
    );
    subscriptions.add(
      _client
          .from('live_sessions')
          .stream(primaryKey: ['id'])
          .eq('id', liveSessionId)
          .listen((_) => reload()),
    );

    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await controller.close();
    };

    yield* controller.stream;
  }

  Future<void> setFormation(String matchId, String formation) async {
    await _client
        .from('live_sessions')
        .update({'formation': formation})
        .eq('match_id', matchId);
  }

  Future<void> movePlayer({
    required String matchId,
    required String playerId,
    required String slotKey,
  }) async {
    final session = await _requireSession(matchId);
    final liveSessionId = session['id'].toString();
    await _client
        .from('live_positions')
        .delete()
        .eq('live_session_id', liveSessionId)
        .eq('profile_id', playerId);
    if (slotKey != 'bench') {
      await _client.from('live_positions').insert({
        'live_session_id': liveSessionId,
        'profile_id': playerId,
        'slot_code': slotKey,
      });
    }
  }

  Future<void> addGoal({
    required String matchId,
    required String team,
    required int minute,
    required GoalType type,
    required String? scorerId,
    required String? assisterId,
  }) async {
    final hidesPlayers = team != 'grinta' || type == GoalType.ownGoal;
    await _client.from('goals').insert({
      'match_id': matchId,
      'team': team == 'grinta' ? 'as_grinta' : 'adverse',
      'minute': minute,
      'goal_type': _goalTypeToDatabase(type),
      'scorer_profile_id': hidesPlayers ? null : scorerId,
      'assist_type': hidesPlayers
          ? null
          : (assisterId == null ? 'sans_passe' : 'connu'),
      'assist_profile_id': hidesPlayers ? null : assisterId,
    });
  }

  Future<void> updateGoal({
    required String goalId,
    required String team,
    required int minute,
    required GoalType type,
    required String? scorerId,
    required String? assisterId,
  }) async {
    final hidesPlayers = team != 'grinta' || type == GoalType.ownGoal;
    await _client.from('goals').update({
      'team': team == 'grinta' ? 'as_grinta' : 'adverse',
      'minute': minute,
      'goal_type': _goalTypeToDatabase(type),
      'scorer_profile_id': hidesPlayers ? null : scorerId,
      'assist_type': hidesPlayers
          ? null
          : (assisterId == null ? 'sans_passe' : 'connu'),
      'assist_profile_id': hidesPlayers ? null : assisterId,
    }).eq('id', goalId);
  }

  Future<void> removeGoal(String goalId) async {
    await _client.from('goals').delete().eq('id', goalId);
  }

  Future<void> addSubstitution({
    required String matchId,
    required int minute,
    required String inPlayerId,
    required String outPlayerId,
  }) async {
    final session = await _requireSession(matchId);
    final liveSessionId = session['id'].toString();
    await _client.from('substitutions').insert([
      {
        'live_session_id': liveSessionId,
        'profile_id': outPlayerId,
        'action': 'out',
        'minute': minute,
      },
      {
        'live_session_id': liveSessionId,
        'profile_id': inPlayerId,
        'action': 'in',
        'minute': minute,
      },
    ]);
  }

  GoalType _goalTypeFromDatabase(String? value) {
    return switch (value) {
      'penalty' => GoalType.penalty,
      'coup_franc' => GoalType.freeKick,
      'csc_adverse' => GoalType.ownGoal,
      _ => GoalType.openPlay,
    };
  }

  String _goalTypeToDatabase(GoalType value) {
    return switch (value) {
      GoalType.openPlay => 'jeu',
      GoalType.penalty => 'penalty',
      GoalType.freeKick => 'coup_franc',
      GoalType.ownGoal => 'csc_adverse',
    };
  }
}

final liveRepositoryProvider = Provider<LiveRepository>((ref) {
  return LiveRepository(ref.watch(supabaseClientProvider));
});

final liveGameplayRepositoryProvider = Provider<LiveRepository>((ref) {
  return ref.watch(liveRepositoryProvider);
});
