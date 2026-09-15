import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/unavailability/domain/player_unavailability.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _unavailabilityReadTimeout = Duration(seconds: 8);
const _unavailabilityWriteTimeout = Duration(seconds: 12);

/// Formate une date en `YYYY-MM-DD`, la seule forme que Postgres lit sans
/// ambiguïté de fuseau. Envoyer un horodatage ferait glisser la période d'un
/// jour pour les joueurs situés à l'ouest de Paris.
String encodeUnavailabilityDate(DateTime day) {
  final month = day.month.toString().padLeft(2, '0');
  final dayOfMonth = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$dayOfMonth';
}

class PlayerUnavailabilityRepository {
  PlayerUnavailabilityRepository(this._client);

  final SupabaseClient _client;

  Future<List<PlayerUnavailability>> fetchMine() async {
    final response = await _client
        .rpc('get_my_unavailabilities')
        .timeout(_unavailabilityReadTimeout);
    return PlayerUnavailability.listFromRpc(response);
  }

  Future<List<PlayerUnavailability>> fetchAll() async {
    final response = await _client
        .rpc('admin_get_player_unavailabilities')
        .timeout(_unavailabilityReadTimeout);
    return PlayerUnavailability.listFromRpc(response);
  }

  /// Crée la période quand [id] est nul, la remplace sinon.
  Future<void> save({
    String? id,
    required DateTime startsOn,
    required DateTime endsOn,
    required String reason,
  }) async {
    await _client.rpc(
      'set_my_unavailability',
      params: {
        'p_id': id,
        'p_starts_on': encodeUnavailabilityDate(startsOn),
        'p_ends_on': encodeUnavailabilityDate(endsOn),
        'p_reason': reason.trim(),
      },
    ).timeout(_unavailabilityWriteTimeout);
  }

  Future<void> cancel(String id) async {
    await _client.rpc(
      'cancel_my_unavailability',
      params: {'p_id': id},
    ).timeout(_unavailabilityWriteTimeout);
  }
}

final playerUnavailabilityRepositoryProvider =
    Provider<PlayerUnavailabilityRepository>((ref) {
  return PlayerUnavailabilityRepository(ref.watch(supabaseClientProvider));
});

final myUnavailabilitiesProvider =
    FutureProvider.autoDispose<List<PlayerUnavailability>>((ref) {
  return ref.watch(playerUnavailabilityRepositoryProvider).fetchMine();
});

final clubUnavailabilitiesProvider =
    FutureProvider.autoDispose<List<PlayerUnavailability>>((ref) {
  return ref.watch(playerUnavailabilityRepositoryProvider).fetchAll();
});
