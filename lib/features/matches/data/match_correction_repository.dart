import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CorrectionParticipant {
  const CorrectionParticipant({required this.id, required this.name});

  final String id;
  final String name;
}

class CorrectionGoal {
  const CorrectionGoal({
    required this.id,
    required this.team,
    required this.minute,
    required this.goalType,
    required this.scorerId,
    required this.assistType,
    required this.assisterId,
  });

  final String id;
  final String team;
  final int minute;
  final String? goalType;
  final String? scorerId;
  final String? assistType;
  final String? assisterId;
}

class MatchCorrectionData {
  const MatchCorrectionData({
    required this.status,
    required this.scoreGrinta,
    required this.scoreOpponent,
    required this.participants,
    required this.goals,
    required this.motmProfileId,
  });

  final String status;
  final int scoreGrinta;
  final int scoreOpponent;
  final List<CorrectionParticipant> participants;
  final List<CorrectionGoal> goals;
  final String? motmProfileId;
}

class MatchCorrectionRepository {
  MatchCorrectionRepository(this._client);

  final SupabaseClient _client;

  Future<MatchCorrectionData> fetch(String matchId) async {
    final match = await _client
        .from('matches')
        .select('status,score_as_grinta,score_adverse')
        .eq('id', matchId)
        .single();

    final participantsRaw = await _client
        .from('match_participants')
        .select('profile_id,profiles!inner(first_name,last_name)')
        .eq('match_id', matchId);
    final participants = (participantsRaw as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      final profile = Map<String, dynamic>.from(map['profiles'] as Map);
      final name =
          '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
      return CorrectionParticipant(
        id: map['profile_id'].toString(),
        name: name.isEmpty ? 'Joueur sans nom' : name,
      );
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final goalsRaw = await _client
        .from('goals')
        .select('id,team,minute,goal_type,scorer_profile_id,assist_type,assist_profile_id')
        .eq('match_id', matchId)
        .order('minute')
        .order('created_order');
    final goals = (goalsRaw as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      return CorrectionGoal(
        id: map['id'].toString(),
        team: map['team'].toString(),
        minute: map['minute'] as int,
        goalType: map['goal_type']?.toString(),
        scorerId: map['scorer_profile_id']?.toString(),
        assistType: map['assist_type']?.toString(),
        assisterId: map['assist_profile_id']?.toString(),
      );
    }).toList();

    final motm = await _client
        .from('match_motm')
        .select('profile_id')
        .eq('match_id', matchId)
        .maybeSingle();

    return MatchCorrectionData(
      status: match['status'].toString(),
      scoreGrinta: int.tryParse('${match['score_as_grinta'] ?? 0}') ?? 0,
      scoreOpponent: int.tryParse('${match['score_adverse'] ?? 0}') ?? 0,
      participants: participants,
      goals: goals,
      motmProfileId: motm?['profile_id']?.toString(),
    );
  }

  Future<void> addGoal({
    required String matchId,
    required String team,
    required int minute,
    required String? goalType,
    required String? scorerId,
    required String? assistType,
    required String? assisterId,
  }) async {
    await _client.rpc(
      'moderator_add_match_goal',
      params: {
        'p_match_id': matchId,
        'p_team': team,
        'p_minute': minute,
        'p_goal_type': goalType,
        'p_scorer_profile_id': scorerId,
        'p_assist_type': assistType,
        'p_assist_profile_id': assisterId,
      },
    );
  }

  Future<void> updateGoal({
    required String goalId,
    required String team,
    required int minute,
    required String? goalType,
    required String? scorerId,
    required String? assistType,
    required String? assisterId,
  }) async {
    final result = await _client.rpc(
      'moderator_update_match_goal',
      params: {
        'p_goal_id': goalId,
        'p_team': team,
        'p_minute': minute,
        'p_goal_type': goalType,
        'p_scorer_profile_id': scorerId,
        'p_assist_type': assistType,
        'p_assist_profile_id': assisterId,
      },
    );
    if (result != true) throw StateError('Le but n’a pas pu être corrigé.');
  }

  Future<void> deleteGoal(String goalId) async {
    final result = await _client.rpc(
      'moderator_delete_match_goal',
      params: {'p_goal_id': goalId},
    );
    if (result != true) throw StateError('Le but n’a pas pu être supprimé.');
  }

  Future<void> setMotm({
    required String matchId,
    required String profileId,
  }) async {
    final result = await _client.rpc(
      'moderator_set_match_motm',
      params: {
        'p_match_id': matchId,
        'p_profile_id': profileId,
      },
    );
    if (result != true) {
      throw StateError('L’homme du match n’a pas pu être corrigé.');
    }
  }
}

final matchCorrectionRepositoryProvider =
    Provider<MatchCorrectionRepository>((ref) {
  return MatchCorrectionRepository(ref.watch(supabaseClientProvider));
});

final matchCorrectionProvider =
    FutureProvider.autoDispose.family<MatchCorrectionData, String>((ref, id) {
  return ref.watch(matchCorrectionRepositoryProvider).fetch(id);
});
