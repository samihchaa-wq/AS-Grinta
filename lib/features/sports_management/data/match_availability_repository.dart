import 'dart:async';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/match_availability.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _availabilityReadTimeout = Duration(seconds: 8);
const _availabilityWriteTimeout = Duration(seconds: 12);

class MatchAvailabilityWriteOutcomeUnknown implements Exception {
  const MatchAvailabilityWriteOutcomeUnknown();

  @override
  String toString() => 'Match availability write outcome is unknown.';
}

class MatchAvailabilityWriteConfirmedButRefreshFailed implements Exception {
  const MatchAvailabilityWriteConfirmedButRefreshFailed();

  @override
  String toString() =>
      'Match availability was saved but the refreshed value could not be read.';
}

Future<MatchAvailability> confirmMatchAvailabilityWrite({
  required Future<Object?> Function() submit,
  required Future<MatchAvailability?> Function() readBack,
  required MatchAvailabilityStatus expectedStatus,
  required String? expectedPrivateComment,
  Duration writeTimeout = _availabilityWriteTimeout,
  Duration readTimeout = _availabilityReadTimeout,
}) async {
  var writeAcknowledged = false;

  try {
    await submit().timeout(writeTimeout);
    writeAcknowledged = true;
  } on PostgrestException {
    // Le serveur a répondu explicitement avec un refus : l'échec est certain.
    rethrow;
  } catch (_) {
    // Timeout, coupure réseau ou accusé perdu : on ne sait pas encore si la
    // transaction serveur a été appliquée. La relecture ci-dessous tranche
    // lorsque c'est possible, sans renvoyer aveuglément la mutation.
  }

  try {
    final current = await readBack().timeout(readTimeout);
    if (current != null &&
        current.status == expectedStatus &&
        current.privateComment == expectedPrivateComment) {
      return current;
    }
  } catch (_) {
    if (writeAcknowledged) {
      throw const MatchAvailabilityWriteConfirmedButRefreshFailed();
    }
    throw const MatchAvailabilityWriteOutcomeUnknown();
  }

  if (writeAcknowledged) {
    throw const MatchAvailabilityWriteConfirmedButRefreshFailed();
  }
  throw const MatchAvailabilityWriteOutcomeUnknown();
}

abstract interface class MatchAvailabilityRepository {
  Future<MatchAvailability?> fetchMyAvailability(String matchId);

  Future<MatchAvailability> setMyAvailability({
    required String matchId,
    required MatchAvailabilityStatus status,
    String? privateComment,
  });
}

class SupabaseMatchAvailabilityRepository
    implements MatchAvailabilityRepository {
  SupabaseMatchAvailabilityRepository(this._client);

  final SupabaseClient _client;
  final Map<String, Future<MatchAvailability?>> _fetchesInFlight = {};

  @override
  Future<MatchAvailability?> fetchMyAvailability(String matchId) {
    final existing = _fetchesInFlight[matchId];
    if (existing != null) return existing;

    final request = _fetchMyAvailability(matchId);
    _fetchesInFlight[matchId] = request;
    return request.whenComplete(() {
      if (identical(_fetchesInFlight[matchId], request)) {
        _fetchesInFlight.remove(matchId);
      }
    });
  }

  Future<MatchAvailability?> _fetchMyAvailability(String matchId) async {
    final response = await _client.rpc('get_my_match_availability',
        params: {'p_match_id': matchId}).timeout(_availabilityReadTimeout);
    if (response == null) return null;
    return MatchAvailability.fromRpc(response);
  }

  @override
  Future<MatchAvailability> setMyAvailability({
    required String matchId,
    required MatchAvailabilityStatus status,
    String? privateComment,
  }) async {
    if (status != MatchAvailabilityStatus.available &&
        status != MatchAvailabilityStatus.absent) {
      throw ArgumentError.value(
        status,
        'status',
        'Only available or absent can be submitted',
      );
    }

    final cleanedComment = status == MatchAvailabilityStatus.available
        ? null
        : _cleanComment(privateComment);

    return confirmMatchAvailabilityWrite(
      submit: () async {
        return _client.rpc(
          'set_my_match_availability',
          params: {
            'p_match_id': matchId,
            'p_status': status.wireValue,
            'p_private_comment': cleanedComment,
          },
        );
      },
      readBack: () async {
        // Une lecture précédente peut encore être en vol au moment de
        // l'écriture. Elle ne doit jamais être réutilisée pour confirmer la
        // valeur fraîche après une réponse normale ou un accusé perdu.
        _fetchesInFlight.remove(matchId);
        return fetchMyAvailability(matchId);
      },
      expectedStatus: status,
      expectedPrivateComment: cleanedComment,
    );
  }

  String? _cleanComment(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

final matchAvailabilityRepositoryProvider =
    Provider<MatchAvailabilityRepository>((ref) {
  return SupabaseMatchAvailabilityRepository(
    ref.watch(supabaseClientProvider),
  );
});
