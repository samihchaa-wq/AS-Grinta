import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/admin_motm_dashboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminMotmDashboardRepository {
  AdminMotmDashboardRepository(this._client);

  final SupabaseClient _client;

  Future<List<AdminMotmListItem>> fetchAll() async {
    final response = await _client.rpc('admin_list_match_motm_votes');
    if (response is! List) {
      throw const FormatException('Liste des scrutins HDM invalide.');
    }
    return response
        .map(
          (item) => AdminMotmListItem.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<AdminMotmDashboard> fetchDashboard(String matchId) async {
    final response = await _client.rpc(
      'admin_get_match_motm_dashboard',
      params: {'p_match_id': matchId},
    );
    if (response is! Map) {
      throw const FormatException('Tableau de bord HDM invalide.');
    }
    return AdminMotmDashboard.fromJson(Map<String, dynamic>.from(response));
  }

  Future<SportStatisticsIntegrity> fetchIntegrity(String matchId) async {
    final response = await _client.rpc(
      'admin_get_match_sport_statistics_integrity',
      params: {'p_match_id': matchId},
    );
    if (response is! Map) {
      throw const FormatException('Contrôle des statistiques invalide.');
    }
    return SportStatisticsIntegrity.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  Future<void> closeEarly({
    required String matchId,
    required String reason,
  }) async {
    final response = await _client.rpc(
      'admin_close_match_motm_vote_early',
      params: {'p_match_id': matchId, 'p_reason': reason.trim()},
    );
    if (response is! Map || response['state'] != 'closed') {
      throw StateError('Le scrutin n’a pas pu être clôturé.');
    }
  }

  Future<void> cancel({required String matchId, required String reason}) async {
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

final adminMotmDashboardRepositoryProvider =
    Provider<AdminMotmDashboardRepository>((ref) {
  return AdminMotmDashboardRepository(ref.watch(supabaseClientProvider));
});

final adminMotmVotesProvider =
    FutureProvider.autoDispose<List<AdminMotmListItem>>((ref) {
  return ref.watch(adminMotmDashboardRepositoryProvider).fetchAll();
});

final adminMotmDashboardProvider = FutureProvider.autoDispose
    .family<AdminMotmDashboard, String>((ref, matchId) {
  return ref
      .watch(adminMotmDashboardRepositoryProvider)
      .fetchDashboard(matchId);
});

final sportStatisticsIntegrityProvider = FutureProvider.autoDispose
    .family<SportStatisticsIntegrity, String>((ref, matchId) {
  return ref
      .watch(adminMotmDashboardRepositoryProvider)
      .fetchIntegrity(matchId);
});
