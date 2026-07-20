import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/availability_reminder_models.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SportWaitlistRepository {
  Future<SportWaitlist> fetchWaitlist({String? seasonId});

  Future<SportWaitlist> reorderWaitlist({
    required String seasonId,
    required List<String> orderedPlayerIds,
    String? reason,
  });

  Future<List<AdminSportMatch>> fetchUpcomingMatches();

  Future<MatchConvocations> fetchMatchConvocations(String matchId);

  Future<AvailabilityReminderSummary> fetchReminderSummary(String matchId);

  Future<AvailabilityReminderResult> sendAvailabilityReminder({
    required String matchId,
    String? seasonPlayerId,
    String? reason,
  });

  Future<MatchConvocations> configureMatch({
    required String matchId,
    required int squadSizeLimit,
  });

  Future<MatchConvocations> recomputeMatch({
    required String matchId,
    bool resetOverrides = false,
  });

  Future<MatchConvocations> setConvocation({
    required String matchId,
    required String seasonPlayerId,
    required ConvocationStatus status,
    required bool turnShouldConsume,
    String? reason,
  });

  Future<MatchConvocations> publishMatch({
    required String matchId,
    String? reason,
  });

  Future<int> finalizeTurns(String matchId);
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
  Future<List<AdminSportMatch>> fetchUpcomingMatches() async {
    final rows = await _client
        .from('matches')
        .select('id, kickoff_at, opponents(name)')
        .eq('status', 'a_venir')
        .order('kickoff_at');
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .map(
          (row) => AdminSportMatch.fromJson({
            'id': row['id'],
            'kickoff_at': row['kickoff_at'],
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
  Future<MatchConvocations> configureMatch({
    required String matchId,
    required int squadSizeLimit,
  }) async {
    await _client.rpc(
      'admin_configure_match_sport_workflow',
      params: {
        'p_match_id': matchId,
        'p_squad_size_limit': squadSizeLimit,
      },
    );
    return fetchMatchConvocations(matchId);
  }

  @override
  Future<MatchConvocations> recomputeMatch({
    required String matchId,
    bool resetOverrides = false,
  }) async {
    await _client.rpc(
      'admin_recompute_match_convocations',
      params: {
        'p_match_id': matchId,
        'p_reset_overrides': resetOverrides,
      },
    );
    return fetchMatchConvocations(matchId);
  }

  @override
  Future<MatchConvocations> setConvocation({
    required String matchId,
    required String seasonPlayerId,
    required ConvocationStatus status,
    required bool turnShouldConsume,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'admin_set_match_convocation',
      params: {
        'p_match_id': matchId,
        'p_season_player_id': seasonPlayerId,
        'p_status': status.wireValue,
        'p_turn_should_consume': turnShouldConsume,
        'p_reason': _clean(reason),
      },
    );
    return MatchConvocations.fromRpc(response);
  }

  @override
  Future<MatchConvocations> publishMatch({
    required String matchId,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'admin_publish_match_convocations',
      params: {'p_match_id': matchId, 'p_reason': _clean(reason)},
    );
    return MatchConvocations.fromRpc(response);
  }

  @override
  Future<int> finalizeTurns(String matchId) async {
    final response = await _client.rpc(
      'admin_finalize_match_waitlist_turns',
      params: {'p_match_id': matchId},
    );
    return (response as num?)?.toInt() ?? 0;
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

final sportWaitlistRepositoryProvider =
    Provider<SportWaitlistRepository>((ref) {
  return SupabaseSportWaitlistRepository(ref.watch(supabaseClientProvider));
});

final adminSportMatchesProvider =
    FutureProvider.autoDispose<List<AdminSportMatch>>((ref) {
  return ref.watch(sportWaitlistRepositoryProvider).fetchUpcomingMatches();
});

final sportWaitlistProvider =
    FutureProvider.autoDispose.family<SportWaitlist, String?>((ref, seasonId) {
  return ref
      .watch(sportWaitlistRepositoryProvider)
      .fetchWaitlist(seasonId: seasonId);
});

final matchConvocationsProvider = FutureProvider.autoDispose
    .family<MatchConvocations, String>((ref, matchId) {
  return ref
      .watch(sportWaitlistRepositoryProvider)
      .fetchMatchConvocations(matchId);
});

final availabilityReminderSummaryProvider = FutureProvider.autoDispose
    .family<AvailabilityReminderSummary, String>((ref, matchId) {
  return ref
      .watch(sportWaitlistRepositoryProvider)
      .fetchReminderSummary(matchId);
});
