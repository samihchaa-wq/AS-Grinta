import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/matches/domain/convocation_launch.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef MatchAvailabilitySchedule = ({
  ConvocationLaunchMode mode,
  DateTime? customAt,
});

class MatchEditScheduleRepository {
  MatchEditScheduleRepository(this._client);

  final SupabaseClient _client;

  Future<MatchAvailabilitySchedule> fetchSchedule(String matchId) async {
    final response = await _client.rpc(
      'get_match_availability_schedule',
      params: {'p_match_id': matchId},
    );
    if (response == null) {
      return (mode: ConvocationLaunchMode.automatic, customAt: null);
    }
    if (response is! Map) {
      throw const FormatException('Planning de convocation invalide.');
    }

    final map = Map<String, dynamic>.from(response);
    final rawMode = map['mode']?.toString();
    final mode = ConvocationLaunchMode.values.firstWhere(
      (value) => value.apiValue == rawMode,
      orElse: () => ConvocationLaunchMode.automatic,
    );
    final rawOpensAt = map['availability_opens_at']?.toString();
    final opensAt = rawOpensAt == null ? null : DateTime.tryParse(rawOpensAt);

    return (
      mode: mode,
      customAt:
          mode == ConvocationLaunchMode.custom ? opensAt?.toLocal() : null,
    );
  }

  Future<void> updateMatch({
    required String id,
    required String seasonId,
    required String opponentId,
    required DateTime kickoffAt,
    required bool isHome,
    required String status,
    required double oddsWin,
    required double oddsDraw,
    required double oddsLoss,
    required DateTime? expectedUpdatedAt,
    int? squadSizeLimit,
    String? address,
    bool rememberAddressAsDefault = false,
    String matchType = 'championnat',
    String? jerseyNote,
    DateTime? meetingAt,
    ConvocationLaunchMode? launchMode,
    DateTime? customLaunchAt,
  }) async {
    if (expectedUpdatedAt == null) {
      throw StateError(
        'Le match a changé. Recharge l’écran avant d’enregistrer.',
      );
    }
    final result = await _client.rpc(
      'admin_update_match_complete_v3',
      params: {
        'p_match_id': id,
        'p_season_id': seasonId,
        'p_opponent_id': opponentId,
        'p_match_date': kickoffAt.toIso8601String().split('T').first,
        'p_match_time': _formatTime(kickoffAt),
        'p_location': isHome ? 'domicile' : 'exterieur',
        'p_status': status,
        'p_win': oddsWin,
        'p_draw': oddsDraw,
        'p_loss': oddsLoss,
        'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
        'p_squad_size_limit': squadSizeLimit,
        'p_address': address,
        'p_remember_address_as_default': rememberAddressAsDefault,
        'p_match_type': matchType,
        'p_jersey_note': jerseyNote,
        'p_meeting_at': meetingAt?.toUtc().toIso8601String(),
        'p_availability_schedule_mode': launchMode?.apiValue,
        'p_availability_opens_at': launchMode == ConvocationLaunchMode.custom
            ? customLaunchAt?.toUtc().toIso8601String()
            : null,
      },
    );
    if (result != true) {
      throw StateError(
        'Le match et ses convocations n’ont pas pu être enregistrés.',
      );
    }
  }

  Future<void> updateInternalMatch({
    required String id,
    required String seasonId,
    required DateTime kickoffAt,
    required DateTime? expectedUpdatedAt,
    String? address,
    DateTime? meetingAt,
    ConvocationLaunchMode? launchMode,
    DateTime? customLaunchAt,
  }) async {
    if (expectedUpdatedAt == null) {
      throw StateError(
        'Le match a changé. Recharge l’écran avant d’enregistrer.',
      );
    }
    final result = await _client.rpc(
      'update_internal_match_v3',
      params: {
        'p_match_id': id,
        'p_season_id': seasonId,
        'p_match_date': kickoffAt.toIso8601String().split('T').first,
        'p_match_time': _formatTime(kickoffAt),
        'p_address': address,
        'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
        'p_meeting_at': meetingAt?.toUtc().toIso8601String(),
        'p_availability_schedule_mode': launchMode?.apiValue,
        'p_availability_opens_at': launchMode == ConvocationLaunchMode.custom
            ? customLaunchAt?.toUtc().toIso8601String()
            : null,
      },
    );
    if (result != true) {
      throw StateError(
        'Le match et ses convocations n’ont pas pu être enregistrés.',
      );
    }
  }

  String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}

final matchEditScheduleRepositoryProvider =
    Provider<MatchEditScheduleRepository>((ref) {
  return MatchEditScheduleRepository(ref.watch(supabaseClientProvider));
});
