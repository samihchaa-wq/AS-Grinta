import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MatchLiveNotificationStatus {
  const MatchLiveNotificationStatus({
    required this.eligible,
    required this.subscribed,
    this.opensAt,
  });

  final bool eligible;
  final bool subscribed;
  final DateTime? opensAt;

  factory MatchLiveNotificationStatus.fromRpc(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('État des alertes de match invalide.');
    }
    final map = Map<String, dynamic>.from(raw);
    return MatchLiveNotificationStatus(
      eligible: map['eligible'] == true,
      subscribed: map['subscribed'] == true,
      opensAt: DateTime.tryParse('${map['opens_at'] ?? ''}')?.toLocal(),
    );
  }
}

abstract interface class MatchLiveNotificationRepository {
  Future<MatchLiveNotificationStatus> fetchStatus(String matchId);

  Future<MatchLiveNotificationStatus> setEnabled({
    required String matchId,
    required bool enabled,
  });
}

class SupabaseMatchLiveNotificationRepository
    implements MatchLiveNotificationRepository {
  SupabaseMatchLiveNotificationRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<MatchLiveNotificationStatus> fetchStatus(String matchId) async {
    final response = await _client.rpc(
      'get_match_live_notification_subscription',
      params: {'p_match_id': matchId},
    );
    return MatchLiveNotificationStatus.fromRpc(response);
  }

  @override
  Future<MatchLiveNotificationStatus> setEnabled({
    required String matchId,
    required bool enabled,
  }) async {
    final response = await _client.rpc(
      'set_match_live_notifications',
      params: {
        'p_match_id': matchId,
        'p_enabled': enabled,
      },
    );
    return MatchLiveNotificationStatus.fromRpc(response);
  }
}

final matchLiveNotificationRepositoryProvider =
    Provider<MatchLiveNotificationRepository>((ref) {
  return SupabaseMatchLiveNotificationRepository(
    ref.watch(supabaseClientProvider),
  );
});

final matchLiveNotificationStatusProvider = FutureProvider.autoDispose
    .family<MatchLiveNotificationStatus, String>((ref, matchId) {
  return ref.watch(matchLiveNotificationRepositoryProvider).fetchStatus(matchId);
});
