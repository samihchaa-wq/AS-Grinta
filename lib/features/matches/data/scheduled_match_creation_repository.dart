import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/matches/domain/convocation_launch.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ScheduledMatchCreationRepository {
  ScheduledMatchCreationRepository(this._client);

  final SupabaseClient _client;

  Future<String> createMatch({
    required String seasonId,
    required String opponentId,
    required DateTime kickoffAt,
    required bool isHome,
    required double oddsWin,
    required double oddsDraw,
    required double oddsLoss,
    required ConvocationLaunchMode launchMode,
    DateTime? customLaunchAt,
    DateTime? meetingAt,
    int? squadSizeLimit,
    String? address,
    bool rememberAddressAsDefault = false,
    String matchType = 'championnat',
    String? jerseyNote,
  }) async {
    final result = await _client.rpc(
      'admin_create_match_complete_v3',
      params: {
        'p_season_id': seasonId,
        'p_opponent_id': opponentId,
        'p_match_date': kickoffAt.toIso8601String().split('T').first,
        'p_match_time': _formatTime(kickoffAt),
        'p_location': isHome ? 'domicile' : 'exterieur',
        'p_win': oddsWin,
        'p_draw': oddsDraw,
        'p_loss': oddsLoss,
        'p_squad_size_limit': squadSizeLimit,
        'p_address': address,
        'p_remember_address_as_default': rememberAddressAsDefault,
        'p_match_type': matchType,
        'p_jersey_note': jerseyNote,
        'p_availability_schedule_mode': launchMode.apiValue,
        'p_availability_opens_at': launchMode == ConvocationLaunchMode.custom
            ? customLaunchAt?.toUtc().toIso8601String()
            : null,
        'p_meeting_at': meetingAt?.toUtc().toIso8601String(),
      },
    );
    if (result == null || result.toString().isEmpty) {
      throw StateError('Le match n’a pas pu être créé.');
    }
    return result.toString();
  }

  Future<String> createInternalMatch({
    required String seasonId,
    required DateTime kickoffAt,
    required ConvocationLaunchMode launchMode,
    DateTime? customLaunchAt,
    DateTime? meetingAt,
    String? address,
  }) async {
    final result = await _client.rpc(
      'create_internal_match_v3',
      params: {
        'p_season_id': seasonId,
        'p_match_date': kickoffAt.toIso8601String().split('T').first,
        'p_match_time': _formatTime(kickoffAt),
        'p_address': address,
        'p_availability_schedule_mode': launchMode.apiValue,
        'p_availability_opens_at': launchMode == ConvocationLaunchMode.custom
            ? customLaunchAt?.toUtc().toIso8601String()
            : null,
        'p_meeting_at': meetingAt?.toUtc().toIso8601String(),
      },
    );
    if (result == null || result.toString().isEmpty) {
      throw StateError('Le match n’a pas pu être créé.');
    }
    return result.toString();
  }

  String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}

final scheduledMatchCreationRepositoryProvider =
    Provider<ScheduledMatchCreationRepository>((ref) {
      return ScheduledMatchCreationRepository(
        ref.watch(supabaseClientProvider),
      );
    });
