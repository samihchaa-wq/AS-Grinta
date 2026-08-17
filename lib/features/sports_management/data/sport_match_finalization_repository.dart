import 'dart:async';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _finalizationWriteTimeout = Duration(seconds: 15);
const _finalizationReadTimeout = Duration(seconds: 10);

class SportMatchFinalizationWriteOutcomeUnknown implements Exception {
  const SportMatchFinalizationWriteOutcomeUnknown();

  @override
  String toString() =>
      'Connexion interrompue : le match a peut-être été validé. '
      'Tes saisies restent affichées. Actualise la page avant de réessayer.';
}

bool sportMatchFinalizationMatchesSubmitted(
  SportMatchFinalization published,
  SportMatchFinalization expected,
) {
  if (published.matchId != expected.matchId ||
      published.scoreAsGrinta != expected.scoreAsGrinta ||
      published.scoreAdverse != expected.scoreAdverse ||
      !published.isValidated ||
      published.participants.length != expected.participants.length) {
    return false;
  }

  final publishedById = {
    for (final participant in published.participants)
      participant.participantId: participant,
  };
  for (final expectedParticipant in expected.participants) {
    final actual = publishedById[expectedParticipant.participantId];
    if (actual == null ||
        actual.present != expectedParticipant.present ||
        actual.selectionStatus != expectedParticipant.selectionStatus ||
        actual.goals != expectedParticipant.goals ||
        actual.cleanSheet != expectedParticipant.cleanSheet) {
      return false;
    }
  }
  return true;
}

Future<SportMatchFinalization> confirmSportMatchFinalizationWrite({
  required Future<SportMatchFinalization> Function() submit,
  required Future<SportMatchFinalization?> Function() readBack,
  required SportMatchFinalization expected,
  Duration writeTimeout = _finalizationWriteTimeout,
  Duration readTimeout = _finalizationReadTimeout,
}) async {
  try {
    return await submit().timeout(writeTimeout);
  } on PostgrestException {
    // Le serveur a répondu explicitement : ce n'est pas un accusé perdu.
    rethrow;
  } on FormatException {
    // Une réponse reçue mais invalide est un échec certain du contrat client.
    rethrow;
  } catch (_) {
    // Timeout/coupure après le clic : la transaction peut déjà être validée.
    // On relit la source de vérité au lieu de rejouer aveuglément la mutation.
  }

  try {
    final published = await readBack().timeout(readTimeout);
    if (published != null &&
        sportMatchFinalizationMatchesSubmitted(published, expected)) {
      return published;
    }
  } catch (_) {
    // La relecture est elle-même indisponible : impossible de conclure.
  }

  throw const SportMatchFinalizationWriteOutcomeUnknown();
}

abstract interface class SportMatchFinalizationRepository {
  Future<SportMatchFinalization> fetchAdminContext(String matchId);

  Future<SportMatchFinalization> finalize({
    required SportMatchFinalization finalization,
    String? reason,
  });

  Future<SportMatchFinalization?> fetchPublishedResult(String matchId);
}

class SupabaseSportMatchFinalizationRepository
    implements SportMatchFinalizationRepository {
  SupabaseSportMatchFinalizationRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<SportMatchFinalization> fetchAdminContext(String matchId) async {
    final response = await _client.rpc(
      'admin_get_match_sport_finalization',
      params: {'p_match_id': matchId},
    );
    return SportMatchFinalization.fromRpc(response);
  }

  @override
  Future<SportMatchFinalization> finalize({
    required SportMatchFinalization finalization,
    String? reason,
  }) {
    return confirmSportMatchFinalizationWrite(
      expected: finalization,
      submit: () async {
        final response = await _client.rpc(
          'admin_finalize_match_sport_postgame',
          params: {
            'p_match_id': finalization.matchId,
            'p_score_as_grinta': finalization.scoreAsGrinta,
            'p_score_adverse': finalization.scoreAdverse,
            'p_participants': [
              for (final participant in finalization.participants)
                participant.toRpcJson(),
            ],
            'p_reason': _clean(reason),
          },
        );
        return SportMatchFinalization.fromRpc(response);
      },
      readBack: () => fetchPublishedResult(finalization.matchId),
    );
  }

  @override
  Future<SportMatchFinalization?> fetchPublishedResult(String matchId) async {
    final response = await _client.rpc(
      'get_match_sport_result',
      params: {'p_match_id': matchId},
    );
    return response == null ? null : SportMatchFinalization.fromRpc(response);
  }

  String? _clean(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}

final sportMatchFinalizationRepositoryProvider =
    Provider<SportMatchFinalizationRepository>((ref) {
  return SupabaseSportMatchFinalizationRepository(
    ref.watch(supabaseClientProvider),
  );
});

final publishedSportMatchResultProvider = FutureProvider.autoDispose
    .family<SportMatchFinalization?, String>((ref, matchId) {
  return ref
      .watch(sportMatchFinalizationRepositoryProvider)
      .fetchPublishedResult(matchId);
});
