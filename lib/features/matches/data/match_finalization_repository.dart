import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/matches/domain/match_finalization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MatchFinalizationParticipant {
  const MatchFinalizationParticipant({required this.id, required this.name});

  final String id;
  final String name;
}

class MatchFinalizationContext {
  const MatchFinalizationContext({
    required this.goals,
    required this.substitutions,
    required this.participants,
  });

  final List<MatchGoal> goals;
  final List<MatchSubstitution> substitutions;
  final List<MatchFinalizationParticipant> participants;
}

class MatchFinalizationRepository {
  MatchFinalizationRepository(this._client);

  final SupabaseClient _client;

  Future<MatchFinalizationContext> fetch(String matchId) async {
    final participantRows = await _client
        .from('match_participants')
        .select('profile_id, profiles!inner(first_name, last_name)')
        .eq('match_id', matchId);
    final participants = (participantRows as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      final profile = Map<String, dynamic>.from(map['profiles'] as Map);
      final name =
          '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
      return MatchFinalizationParticipant(
        id: map['profile_id'].toString(),
        name: name.isEmpty ? 'Joueur sans nom' : name,
      );
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final goalRows = await _client
        .from('goals')
        .select('team, minute, scorer_profile_id, assist_profile_id')
        .eq('match_id', matchId)
        .order('created_order');
    final goals = (goalRows as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      return MatchGoal(
        team: map['team'] == 'as_grinta' ? 'grinta' : 'adversaire',
        minute: map['minute'] as int,
        scorerId: map['scorer_profile_id']?.toString(),
        assisterId: map['assist_profile_id']?.toString(),
      );
    }).toList();

    final liveSession = await _client
        .from('live_sessions')
        .select('id')
        .eq('match_id', matchId)
        .maybeSingle();
    final substitutions = <MatchSubstitution>[];
    if (liveSession != null) {
      final rows = await _client
          .from('substitutions')
          .select('profile_id, action, minute, created_at')
          .eq('live_session_id', liveSession['id'])
          .order('created_at');
      final data =
          (rows as List).map((row) => Map<String, dynamic>.from(row)).toList();
      for (var index = 0; index < data.length; index++) {
        final outRow = data[index];
        if (outRow['action'] != 'out') continue;
        for (var candidate = index + 1; candidate < data.length; candidate++) {
          final inRow = data[candidate];
          if (inRow['action'] == 'in' && inRow['minute'] == outRow['minute']) {
            substitutions.add(
              MatchSubstitution(
                minute: outRow['minute'] as int,
                inPlayerId: inRow['profile_id'].toString(),
                outPlayerId: outRow['profile_id'].toString(),
              ),
            );
            break;
          }
        }
      }
    }

    return MatchFinalizationContext(
      goals: goals,
      substitutions: substitutions,
      participants: participants,
    );
  }
}

final matchFinalizationRepositoryProvider =
    Provider<MatchFinalizationRepository>((ref) {
  return MatchFinalizationRepository(ref.watch(supabaseClientProvider));
});

final matchFinalizationContextProvider =
    FutureProvider.family<MatchFinalizationContext, String>((ref, matchId) {
  return ref.watch(matchFinalizationRepositoryProvider).fetch(matchId);
});
