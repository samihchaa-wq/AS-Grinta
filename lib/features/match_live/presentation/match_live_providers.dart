import 'dart:async';
import 'dart:math';

import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/match_live/data/match_live_repository.dart';
import 'package:as_grinta/features/match_live/domain/match_live_add_player_options.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/domain/match_live_timeline.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Random _scoreOperationRandom = Random.secure();
const Duration matchLiveFallbackPollInterval = Duration(seconds: 30);

String _newScoreOperationId() {
  final bytes = List<int>.generate(
    16,
    (_) => _scoreOperationRandom.nextInt(256),
    growable: false,
  );
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex =
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Vrai si l'utilisateur courant peut piloter le Tableau Blanc de ce match :
/// admin, ou joueur du roster coché "Coach" (season_players.is_coach) pour
/// la saison du match. Purement indicatif côté client pour choisir l'écran à
/// afficher — l'autorisation réelle est toujours revérifiée côté serveur par
/// private.is_match_coach_or_admin dans chaque RPC d'écriture.
final isMatchCoachOrAdminProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, matchId) async {
  if (ref.watch(isAdminViewProvider)) return true;

  final profileId = ref.watch(
    authControllerProvider.select((state) => state.profile?.id),
  );
  if (profileId == null) return false;

  final client = ref.watch(supabaseClientProvider);
  final match = await client
      .from('matches')
      .select('season_id')
      .eq('id', matchId)
      .maybeSingle();
  final seasonId = match?['season_id']?.toString();
  if (seasonId == null) return false;

  final coachRow = await client
      .from('season_players')
      .select('id')
      .eq('season_id', seasonId)
      .eq('profile_id', profileId)
      .eq('is_coach', true)
      .eq('is_active', true)
      .maybeSingle();
  return coachRow != null;
});

final matchLiveTimelineProvider = FutureProvider.autoDispose
    .family<MatchLiveTimeline?, String>((ref, matchId) {
  return ref.watch(matchLiveRepositoryProvider).fetchTimeline(matchId);
});

/// Message transitoire affiché au coach lorsqu'une écriture Live n'a pas pu
/// être confirmée. Le contrôleur relit d'abord l'état autoritaire du serveur :
/// le message ne remplace donc jamais le snapshot par une supposition locale.
final matchLiveActionMessageProvider =
    StateProvider.autoDispose.family<String?, String>((ref, matchId) => null);

/// Indique qu'une erreur a été signalée par le flux Realtime. Le Live continue
/// alors à se resynchroniser par lecture serveur périodique jusqu'au prochain
/// signal Realtime reçu.
final matchLiveRealtimeDegradedProvider =
    StateProvider.autoDispose.family<bool, String>((ref, matchId) => false);

final matchLiveStateProvider = AsyncNotifierProvider.autoDispose
    .family<MatchLiveStateController, MatchLiveStateBundle, String>(
  MatchLiveStateController.new,
);

class MatchLiveStateController
    extends AutoDisposeFamilyAsyncNotifier<MatchLiveStateBundle, String> {
  StreamSubscription<void>? _subscription;
  Timer? _fallbackPollTimer;
  int _stateGeneration = 0;

  @override
  Future<MatchLiveStateBundle> build(String matchId) async {
    final repository = ref.watch(matchLiveRepositoryProvider);

    // Charger d'abord un snapshot cohérent. L'abonnement est installé juste
    // après et une relecture immédiate referme la petite fenêtre entre les deux.
    // Cela évite surtout qu'un refresh lancé pendant build() soit ensuite
    // écrasé par le résultat initial, plus ancien.
    final initial = await repository.fetchLiveState(matchId);
    ref.read(matchLiveRealtimeDegradedProvider(matchId).notifier).state = false;
    _subscription = repository.watchChanges(matchId).listen(
      (_) {
        ref.read(matchLiveRealtimeDegradedProvider(matchId).notifier).state =
            false;
        unawaited(_refresh());
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error('match_live.watch_changes', error, stackTrace);
        ref.read(matchLiveRealtimeDegradedProvider(matchId).notifier).state =
            true;
        unawaited(_refresh());
      },
    );
    _fallbackPollTimer = Timer.periodic(
      matchLiveFallbackPollInterval,
      (_) => unawaited(_refresh()),
    );
    ref.onDispose(() {
      _subscription?.cancel();
      _fallbackPollTimer?.cancel();
    });
    unawaited(_refresh());
    return initial;
  }

  Future<void> _refresh() async {
    final generation = ++_stateGeneration;
    final repository = ref.read(matchLiveRepositoryProvider);
    try {
      final bundle = await repository.fetchLiveState(arg);
      if (generation != _stateGeneration) return;
      state = AsyncData(bundle);
    } catch (error, stackTrace) {
      if (generation != _stateGeneration) return;
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> _mutate(
    Future<MatchLiveStateBundle> Function(MatchLiveRepository repository)
        action,
  ) async {
    // Une écriture invalide toutes les lectures déjà en vol. Si une nouvelle
    // lecture ou une autre écriture démarre pendant celle-ci, son résultat est
    // considéré comme plus récent et le bundle de cette action ne remplace pas
    // cet état ; une relecture autoritaire tranche alors l'ordre réel serveur.
    final generation = ++_stateGeneration;
    final repository = ref.read(matchLiveRepositoryProvider);
    try {
      final bundle = await action(repository);
      if (generation != _stateGeneration) {
        unawaited(_refresh());
        return;
      }
      state = AsyncData(bundle);
    } catch (error, stackTrace) {
      AppLogger.error('match_live.mutation', error, stackTrace);

      var resynced = false;
      if (generation == _stateGeneration) {
        try {
          final authoritative = await repository.fetchLiveState(arg);
          if (generation == _stateGeneration) {
            state = AsyncData(authoritative);
            resynced = true;
          }
        } catch (refreshError, refreshStackTrace) {
          AppLogger.error(
            'match_live.mutation_resync',
            refreshError,
            refreshStackTrace,
          );
          if (generation == _stateGeneration) {
            state = AsyncError(refreshError, refreshStackTrace);
          }
        }
      }

      ref.read(matchLiveActionMessageProvider(arg).notifier).state = resynced
          ? 'Action non confirmée. L’état réel du serveur a été rechargé.'
          : 'Action non confirmée. Impossible de relire le serveur : vérifie '
              'le Live avant de continuer.';
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<MatchLiveAddPlayerOptions> fetchAddPlayerOptions() {
    return ref.read(matchLiveRepositoryProvider).fetchAddPlayerOptions(arg);
  }

  Future<void> addPlayers(
    List<MatchLiveAddPlayerRequest> players, {
    String? reason,
  }) {
    return _mutate(
      (repository) => repository.addLivePlayers(
        matchId: arg,
        players: players,
        reason: reason,
      ),
    );
  }

  Future<void> openWorkspace({int? plannedDurationMinutes}) {
    return _mutate(
      (repository) => repository.openWorkspace(
        matchId: arg,
        plannedDurationMinutes: plannedDurationMinutes,
      ),
    );
  }

  Future<void> confirmStart({String? reason}) {
    return _mutate(
      (repository) => repository.confirmStart(matchId: arg, reason: reason),
    );
  }

  Future<void> setClockState(String action, {String? reason}) {
    return _mutate(
      (repository) => repository.setClockState(
        matchId: arg,
        action: action,
        reason: reason,
      ),
    );
  }

  Future<void> adjustScore({
    required String team,
    required int delta,
    String? scorerParticipantId,
  }) {
    final operationId = _newScoreOperationId();
    return _mutate((repository) async {
      Future<MatchLiveStateBundle> send() => repository.adjustScore(
            matchId: arg,
            team: team,
            delta: delta,
            operationId: operationId,
            scorerParticipantId: scorerParticipantId,
          );

      try {
        return await send();
      } catch (_) {
        // Le premier appel peut avoir ete committe alors que sa reponse reseau
        // a ete perdue. Un unique retry avec le meme UUID est sans effet double
        // grace au ledger serveur.
        return send();
      }
    });
  }

  Future<void> saveLiveLineup({
    required List<Map<String, dynamic>> entries,
    required int expectedLineupRevision,
    List<({String playerIn, String playerOut})> substitutions = const [],
  }) {
    return _mutate(
      (repository) => repository.saveLiveLineup(
        matchId: arg,
        entries: entries,
        expectedLineupRevision: expectedLineupRevision,
        substitutions: substitutions,
      ),
    );
  }

  Future<void> deleteEvent(String eventId) {
    return _mutate(
      (repository) => repository.deleteEvent(matchId: arg, eventId: eventId),
    );
  }

  Future<void> setEventScorer(
    String eventId, {
    String? scorerParticipantId,
    bool isOpponentOwnGoal = false,
  }) {
    return _mutate(
      (repository) => repository.setEventScorer(
        matchId: arg,
        eventId: eventId,
        scorerParticipantId: scorerParticipantId,
        isOpponentOwnGoal: isOpponentOwnGoal,
      ),
    );
  }

  Future<void> endMatch({String? reason}) {
    return _mutate(
      (repository) => repository.endMatch(matchId: arg, reason: reason),
    );
  }

  Future<void> reopen({String? reason}) {
    return _mutate(
      (repository) => repository.reopen(matchId: arg, reason: reason),
    );
  }

  /// Remet le suivi en direct à zéro : tout ce qui a été saisi est effacé et
  /// le match revient à l'écran de préparation.
  Future<void> restartSession({String? reason}) {
    return _mutate(
      (repository) => repository.restartSession(matchId: arg, reason: reason),
    );
  }
}
