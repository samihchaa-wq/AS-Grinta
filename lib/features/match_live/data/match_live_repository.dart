import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/match_live/domain/match_live_add_player_options.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/domain/match_live_timeline.dart';
import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class MatchLiveRepository {
  Future<MatchLiveStateBundle> fetchLiveState(String matchId);
  Future<MatchLiveTimeline?> fetchTimeline(String matchId);
  Future<MatchLiveAddPlayerOptions> fetchAddPlayerOptions(String matchId);

  Future<MatchLiveStateBundle> openWorkspace({
    required String matchId,
    int? plannedDurationMinutes,
  });
  Future<MatchLiveStateBundle> confirmStart({
    required String matchId,
    String? reason,
  });
  Future<MatchLiveStateBundle> setClockState({
    required String matchId,
    required String action,
    String? reason,
  });
  Future<MatchLiveStateBundle> adjustScore({
    required String matchId,
    required String team,
    required int delta,
    String? scorerParticipantId,
  });

  Future<MatchLiveStateBundle> addLivePlayers({
    required String matchId,
    required List<MatchLiveAddPlayerRequest> players,
    String? reason,
  });

  /// [substitutions] peut contenir plusieurs changements : ils sont alors
  /// enregistrés en une seule salve, tous à la même minute.
  Future<MatchLiveStateBundle> saveLiveLineup({
    required String matchId,
    required List<Map<String, dynamic>> entries,
    List<({String playerIn, String playerOut})> substitutions,
  });

  /// Supprime un but ou un remplacement saisi par erreur. Un but retire
  /// aussi l'unité correspondante au score.
  Future<MatchLiveStateBundle> deleteEvent({
    required String matchId,
    required String eventId,
  });

  /// Attribue un but déjà enregistré : à un joueur, ou à un contre-son-camp
  /// adverse. Les deux paramètres nuls/faux remettent le but « à attribuer ».
  Future<MatchLiveStateBundle> setEventScorer({
    required String matchId,
    required String eventId,
    String? scorerParticipantId,
    bool isOpponentOwnGoal,
  });
  Future<MatchLiveStateBundle> endMatch({
    required String matchId,
    String? reason,
  });
  Future<MatchLiveStateBundle> reopen({
    required String matchId,
    String? reason,
  });

  /// Efface tout ce qui a été saisi en direct (buts, remplacements, chrono,
  /// score) et remet la composition du coup d'envoi. Le match repasse à
  /// l'écran de préparation. Impossible sur un match déjà exporté.
  Future<MatchLiveStateBundle> restartSession({
    required String matchId,
    String? reason,
  });
  Future<SportMatchFinalization> publishRecap({
    required String matchId,
    required int scoreAsGrinta,
    required int scoreAdverse,
    required List<SportFinalParticipant> participants,
    String? reason,
  });

  /// Signal "quelque chose a changé" — pas de charge utile : les abonnés
  /// rappellent [fetchLiveState] pour obtenir l'état complet à jour. Même
  /// approche que feature_flags_repository.dart (signal, pas de flux de
  /// données brutes), plus robuste pour un premier écran temps réel.
  Stream<void> watchChanges(String matchId);
}

class SupabaseMatchLiveRepository implements MatchLiveRepository {
  SupabaseMatchLiveRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<MatchLiveStateBundle> fetchLiveState(String matchId) async {
    final response = await _client.rpc(
      'get_match_live_state',
      params: {'p_match_id': matchId},
    );
    return MatchLiveStateBundle.fromRpc(response);
  }

  @override
  Future<MatchLiveTimeline?> fetchTimeline(String matchId) async {
    final response = await _client.rpc(
      'get_match_live_timeline',
      params: {'p_match_id': matchId},
    );
    return MatchLiveTimeline.tryFromRpc(response);
  }

  @override
  Future<MatchLiveAddPlayerOptions> fetchAddPlayerOptions(
    String matchId,
  ) async {
    final response = await _client.rpc(
      'get_match_live_add_player_options',
      params: {'p_match_id': matchId},
    );
    return MatchLiveAddPlayerOptions.fromRpc(response);
  }

  @override
  Future<MatchLiveStateBundle> openWorkspace({
    required String matchId,
    int? plannedDurationMinutes,
  }) async {
    final response = await _client.rpc(
      'open_match_live_workspace',
      params: {
        'p_match_id': matchId,
        'p_planned_duration_minutes': plannedDurationMinutes,
      },
    );
    return MatchLiveStateBundle.fromRpc(response);
  }

  @override
  Future<MatchLiveStateBundle> confirmStart({
    required String matchId,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'confirm_start_match_live',
      params: {'p_match_id': matchId, 'p_reason': _clean(reason)},
    );
    return MatchLiveStateBundle.fromRpc(response);
  }

  @override
  Future<MatchLiveStateBundle> setClockState({
    required String matchId,
    required String action,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'coach_set_match_live_clock_state',
      params: {
        'p_match_id': matchId,
        'p_action': action,
        'p_reason': _clean(reason),
      },
    );
    return MatchLiveStateBundle.fromRpc(response);
  }

  @override
  Future<MatchLiveStateBundle> adjustScore({
    required String matchId,
    required String team,
    required int delta,
    String? scorerParticipantId,
  }) async {
    final response = await _client.rpc(
      'coach_adjust_match_live_score',
      params: {
        'p_match_id': matchId,
        'p_team': team,
        'p_delta': delta,
        'p_scorer_participant_id': scorerParticipantId,
      },
    );
    return MatchLiveStateBundle.fromRpc(response);
  }

  @override
  Future<MatchLiveStateBundle> addLivePlayers({
    required String matchId,
    required List<MatchLiveAddPlayerRequest> players,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'coach_add_match_live_players',
      params: {
        'p_match_id': matchId,
        'p_players': [for (final player in players) player.toRpcJson()],
        'p_reason': _clean(reason),
      },
    );
    return MatchLiveStateBundle.fromRpc(response);
  }

  @override
  Future<MatchLiveStateBundle> saveLiveLineup({
    required String matchId,
    required List<Map<String, dynamic>> entries,
    List<({String playerIn, String playerOut})> substitutions = const [],
  }) async {
    final response = await _client.rpc(
      'coach_save_match_live_lineup',
      params: {
        'p_match_id': matchId,
        'p_entries': entries,
        'p_substitution': substitutions.isEmpty
            ? null
            : [
                for (final substitution in substitutions)
                  {
                    'player_in': substitution.playerIn,
                    'player_out': substitution.playerOut,
                  },
              ],
      },
    );
    return MatchLiveStateBundle.fromRpc(response);
  }

  @override
  Future<MatchLiveStateBundle> deleteEvent({
    required String matchId,
    required String eventId,
  }) async {
    final response = await _client.rpc(
      'coach_delete_match_live_event',
      params: {'p_match_id': matchId, 'p_event_id': eventId},
    );
    return MatchLiveStateBundle.fromRpc(response);
  }

  @override
  Future<MatchLiveStateBundle> setEventScorer({
    required String matchId,
    required String eventId,
    String? scorerParticipantId,
    bool isOpponentOwnGoal = false,
  }) async {
    final response = await _client.rpc(
      'coach_set_match_live_event_scorer',
      params: {
        'p_match_id': matchId,
        'p_event_id': eventId,
        'p_scorer_participant_id': scorerParticipantId,
        'p_is_opponent_own_goal': isOpponentOwnGoal,
      },
    );
    return MatchLiveStateBundle.fromRpc(response);
  }

  @override
  Future<MatchLiveStateBundle> endMatch({
    required String matchId,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'coach_end_match_live',
      params: {'p_match_id': matchId, 'p_reason': _clean(reason)},
    );
    return MatchLiveStateBundle.fromRpc(response);
  }

  @override
  Future<MatchLiveStateBundle> reopen({
    required String matchId,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'coach_reopen_match_live',
      params: {'p_match_id': matchId, 'p_reason': _clean(reason)},
    );
    return MatchLiveStateBundle.fromRpc(response);
  }

  @override
  Future<MatchLiveStateBundle> restartSession({
    required String matchId,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'coach_restart_match_live_session',
      params: {'p_match_id': matchId, 'p_reason': _clean(reason)},
    );
    return MatchLiveStateBundle.fromRpc(response);
  }

  @override
  Future<SportMatchFinalization> publishRecap({
    required String matchId,
    required int scoreAsGrinta,
    required int scoreAdverse,
    required List<SportFinalParticipant> participants,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'coach_publish_match_live_recap',
      params: {
        'p_match_id': matchId,
        'p_score_as_grinta': scoreAsGrinta,
        'p_score_adverse': scoreAdverse,
        'p_participants': [for (final p in participants) p.toRpcJson()],
        'p_reason': _clean(reason),
      },
    );
    return SportMatchFinalization.fromRpc(response);
  }

  @override
  Stream<void> watchChanges(String matchId) {
    final sessionStream = _client
        .from('match_live_sessions')
        .stream(primaryKey: ['match_id'])
        .eq('match_id', matchId)
        .map((_) => null);
    final eventsStream = _client
        .from('match_live_events')
        .stream(primaryKey: ['id'])
        .eq('match_id', matchId)
        .map((_) => null);
    return Stream<void>.multi((controller) {
      final subs = [
        sessionStream.listen(controller.add, onError: controller.addError),
        eventsStream.listen(controller.add, onError: controller.addError),
      ];
      controller.onCancel = () {
        for (final sub in subs) {
          sub.cancel();
        }
      };
    });
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

final matchLiveRepositoryProvider = Provider<MatchLiveRepository>((ref) {
  return SupabaseMatchLiveRepository(ref.watch(supabaseClientProvider));
});
