import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/sport_motm_vote.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SportMotmVoteRepository {
  SportMotmVoteRepository(this._client);

  final SupabaseClient _client;

  Future<SportMotmVote?> fetch(String matchId) async {
    final response = await _client.rpc(
      'get_match_motm_vote',
      params: {'p_match_id': matchId},
    );
    if (response == null) return null;
    if (response is! Map) {
      throw const FormatException('Scrutin Homme du match invalide.');
    }
    return SportMotmVote.fromJson(Map<String, dynamic>.from(response));
  }

  Future<void> castVote({
    required String matchId,
    required String candidateParticipantId,
  }) async {
    final response = await _client.rpc(
      'cast_match_motm_vote',
      params: {
        'p_match_id': matchId,
        'p_candidate_participant_id': candidateParticipantId,
      },
    );
    if (response is! Map || response['accepted'] != true) {
      throw StateError('Le vote n’a pas pu être enregistré.');
    }
  }

  Future<void> cancel({
    required String matchId,
    required String reason,
  }) async {
    final response = await _client.rpc(
      'admin_cancel_match_motm_vote',
      params: {'p_match_id': matchId, 'p_reason': reason.trim()},
    );
    if (response is! Map || response['state'] != 'cancelled') {
      throw StateError('Le scrutin n’a pas pu être annulé.');
    }
  }

  Future<void> restart({
    required String matchId,
    required String reason,
  }) async {
    final response = await _client.rpc(
      'admin_restart_match_motm_vote',
      params: {'p_match_id': matchId, 'p_reason': reason.trim()},
    );
    if (response is! Map || response['state'] != 'open') {
      throw StateError('Le scrutin n’a pas pu être relancé.');
    }
  }
}

final sportMotmVoteRepositoryProvider =
    Provider<SportMotmVoteRepository>((ref) {
  return SportMotmVoteRepository(ref.watch(supabaseClientProvider));
});

final sportMotmVoteProvider =
    FutureProvider.autoDispose.family<SportMotmVote?, String>((ref, matchId) {
  return ref.watch(sportMotmVoteRepositoryProvider).fetch(matchId);
});
