import 'dart:async';

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
    .family<MatchLiveNotificationStatus, String>((ref, matchId) async {
  final status = await ref
      .watch(matchLiveNotificationRepositoryProvider)
      .fetchStatus(matchId);

  // Si l'écran reste ouvert avant J-6 12 h, la cloche doit apparaître toute
  // seule au moment de l'ouverture sans imposer un pull-to-refresh.
  final delay = matchLiveNotificationRecheckDelay(status, DateTime.now());
  if (delay != null) {
    final timer = Timer(delay, () => ref.invalidateSelf());
    ref.onDispose(timer.cancel);
  }

  return status;
});

/// Plus longue attente confiée à une seule minuterie.
///
/// Sur le Web, une minuterie de plus de 24,8 jours (2^31 - 1 ms) déborde et se
/// déclenche immédiatement. Pour un match lointain, la relecture repartait
/// donc aussitôt, sans fin : des millions de requêtes inutiles. Au-delà de ce
/// plafond, on relit simplement l'état une fois, puis on réarme.
const Duration matchLiveNotificationMaxRecheckDelay = Duration(hours: 12);

/// Délai avant de relire l'état de la cloche, ou `null` s'il n'y a rien à
/// attendre. Toujours compris entre 1 s et [matchLiveNotificationMaxRecheckDelay].
Duration? matchLiveNotificationRecheckDelay(
  MatchLiveNotificationStatus status,
  DateTime now,
) {
  final opensAt = status.opensAt;
  if (status.eligible || opensAt == null) return null;
  final untilOpen = opensAt.difference(now);
  if (untilOpen <= Duration.zero) return null;
  final delay = untilOpen + const Duration(seconds: 1);
  return delay > matchLiveNotificationMaxRecheckDelay
      ? matchLiveNotificationMaxRecheckDelay
      : delay;
}
