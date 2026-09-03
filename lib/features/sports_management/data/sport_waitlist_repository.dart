import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/availability_reminder_models.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SportWaitlistRepository {
  Future<SportWaitlist> fetchWaitlist({String? seasonId});

  /// Lecture accessible à tout joueur actif, sans les effets de bord de
  /// [fetchWaitlist] (pas d'initialisation ni de clôture des tours en
  /// retard) et sans possibilité de modification.
  Future<SportWaitlist> fetchWaitlistReadOnly({String? seasonId});

  Future<SportWaitlist> reorderWaitlist({
    required String seasonId,
    required List<String> orderedPlayerIds,
    String? reason,
  });

  Future<void> setWaitlistManualCount({
    required String seasonPlayerId,
    required int count,
  });

  Future<List<AdminSportMatch>> fetchUpcomingMatches();

  Future<MatchConvocations> fetchMatchConvocations(String matchId);

  Future<AvailabilityReminderSummary> fetchReminderSummary(String matchId);

  Future<AvailabilityReminderResult> sendAvailabilityReminder({
    required String matchId,
    String? seasonPlayerId,
    String? reason,
  });

  Future<MatchConvocations> publishEffectif({
    required String matchId,
    required int squadSizeLimit,
    required Map<String, ConvocationStatus> decisions,
    String? reason,
  });
}

class SupabaseSportWaitlistRepository implements SportWaitlistRepository {
  SupabaseSportWaitlistRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<SportWaitlist> fetchWaitlist({String? seasonId}) async {
    final response = await _client.rpc(
      'admin_get_sport_waitlist',
      params: {'p_season_id': seasonId},
    );
    return SportWaitlist.fromRpc(response);
  }

  @override
  Future<SportWaitlist> fetchWaitlistReadOnly({String? seasonId}) async {
    final response = await _client.rpc(
      'get_sport_waitlist',
      params: {'p_season_id': seasonId},
    );
    return SportWaitlist.fromRpc(response);
  }

  @override
  Future<SportWaitlist> reorderWaitlist({
    required String seasonId,
    required List<String> orderedPlayerIds,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'admin_reorder_sport_waitlist',
      params: {
        'p_season_id': seasonId,
        'p_ordered_player_ids': orderedPlayerIds,
        'p_reason': _clean(reason),
      },
    );
    return SportWaitlist.fromRpc(response);
  }

  @override
  Future<void> setWaitlistManualCount({
    required String seasonPlayerId,
    required int count,
  }) async {
    await _client.rpc(
      'admin_set_waitlist_manual_count',
      params: {'p_season_player_id': seasonPlayerId, 'p_count': count},
    );
  }

  @override
  Future<List<AdminSportMatch>> fetchUpcomingMatches() async {
    final rows = await _client
        .from('matches')
        .select('id, kickoff_at, match_type, opponents(name)')
        .inFilter('status', const ['a_venir', 'termine']).order('kickoff_at',
            ascending: false);
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .map(
          (row) => AdminSportMatch.fromJson({
            'id': row['id'],
            'kickoff_at': row['kickoff_at'],
            'match_type': row['match_type'],
            'opponent_name': (row['opponents'] as Map?)?['name'],
          }),
        )
        .toList();
  }

  @override
  Future<MatchConvocations> fetchMatchConvocations(String matchId) async {
    final response = await _client.rpc(
      'admin_get_match_convocations',
      params: {'p_match_id': matchId},
    );
    return MatchConvocations.fromRpc(response);
  }

  @override
  Future<AvailabilityReminderSummary> fetchReminderSummary(
    String matchId,
  ) async {
    final response = await _client.rpc(
      'admin_get_match_availability_reminders',
      params: {'p_match_id': matchId},
    );
    return AvailabilityReminderSummary.fromRpc(response);
  }

  @override
  Future<AvailabilityReminderResult> sendAvailabilityReminder({
    required String matchId,
    String? seasonPlayerId,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'admin_send_match_availability_reminder',
      params: {
        'p_match_id': matchId,
        'p_season_player_id': seasonPlayerId,
        'p_reason': _clean(reason),
      },
    );
    return AvailabilityReminderResult.fromRpc(response);
  }

  @override
  Future<MatchConvocations> publishEffectif({
    required String matchId,
    required int squadSizeLimit,
    required Map<String, ConvocationStatus> decisions,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'admin_publish_match_effectif',
      params: _effectifParams(
        matchId: matchId,
        squadSizeLimit: squadSizeLimit,
        decisions: decisions,
        reason: reason,
      ),
    );
    return MatchConvocations.fromRpc(response);
  }

  @override

  Map<String, Object?> _effectifParams({
    required String matchId,
    required int squadSizeLimit,
    required Map<String, ConvocationStatus> decisions,
    String? reason,
  }) {
    return {
      'p_match_id': matchId,
      'p_squad_size_limit': squadSizeLimit,
      'p_decisions': [
        for (final decision in decisions.entries)
          {
            'season_player_id': decision.key,
            'status': decision.value.wireValue,
          },
      ],
      'p_reason': _clean(reason),
    };
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

final sportWaitlistRepositoryProvider = Provider<SportWaitlistRepository>((
  ref,
) {
  return SupabaseSportWaitlistRepository(ref.watch(supabaseClientProvider));
});
