import 'dart:async';
import 'dart:math';

import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:as_grinta/core/network/confirmed_write.dart';
import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/match_live/data/match_live_repository.dart';
import 'package:as_grinta/features/match_live/domain/match_live_add_player_options.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/domain/match_live_timeline.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_pilot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Random _scoreOperationRandom = Random.secure();
const Duration matchLiveFallbackPollInterval = Duration(seconds: 30);
const Duration matchLivePilotHeartbeatInterval = Duration(seconds: 15);

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

/// Vrai si l'utilisateur courant peut valider le compte rendu de ce match :
/// admin, ou coach de la saison du match. Purement indicatif côté client pour
/// choisir l'écran à afficher — l'autorisation réelle est revérifiée côté
/// serveur.
final isMatchCoachOrAdminProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, matchId) async {
  if (ref.watch(isAdminViewProvider)) return true;
  return ref.watch(isMatchLiveCoachProvider(matchId).future);
});

/// Vrai si l'utilisateur courant pilote le Live de ce match : joueur du
/// roster coché "Coach" (season_players.is_coach) pour la saison du match.
/// Un administrateur qui n'est pas coach suit le Live en spectateur. Le
/// serveur refuse de toute façon la place de pilote à tout autre profil.
final isMatchLiveCoachProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, matchId) async {
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
/// Delais des ecritures et relectures du Live, injectables pour les tests.
final matchLiveWriteTimeoutProvider = Provider<Duration>(
  (ref) => kConfirmedWriteTimeout,
);

final matchLiveReadTimeoutProvider = Provider<Duration>(
  (ref) => kConfirmedReadTimeout,
);

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

/// Source de vérité du pilote : uniquement le snapshot serveur, jamais un état
/// local.
final livePilotProvider = Provider.autoDispose.family<LivePilot, String>((
  ref,
  matchId,
) {
  final session =
      ref.watch(matchLiveStateProvider(matchId)).valueOrNull?.session;
  if (session == null || !session.pilotActive) return LivePilot.nobody;
  return session.pilotIsMe ? LivePilot.me : LivePilot.other;
});

class MatchLiveStateController
    extends AutoDisposeFamilyAsyncNotifier<MatchLiveStateBundle, String> {
  StreamSubscription<void>? _subscription;
  Timer? _fallbackPollTimer;
  int _stateGeneration = 0;

  @override
  Future<MatchLiveStateBundle> build(String matchId) async {
    final repository = ref.watch(matchLiveRepositoryProvider);

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
        action, {
    Duration? writeTimeout,
  }) async {
    final generation = ++_stateGeneration;
    final repository = ref.read(matchLiveRepositoryProvider);
    try {
      final bundle = await action(repository).timeout(
        writeTimeout ?? ref.read(matchLiveWriteTimeoutProvider),
      );
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
          final authoritative = await repository
              .fetchLiveState(arg)
              .timeout(ref.read(matchLiveReadTimeoutProvider));
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

  /// Signal technique silencieux : une perte réseau pendant le heartbeat ou
  /// la libération ne doit pas afficher un message toutes les 15 secondes.
  /// Le serveur expirera de toute façon le verrou après environ une minute.
  Future<void> _pilotSignal(
    Future<MatchLiveStateBundle> Function(MatchLiveRepository repository)
        action,
  ) async {
    final generation = ++_stateGeneration;
    final repository = ref.read(matchLiveRepositoryProvider);
    try {
      final bundle = await action(repository).timeout(
        ref.read(matchLiveWriteTimeoutProvider),
      );
      if (generation == _stateGeneration) state = AsyncData(bundle);
    } catch (error, stackTrace) {
      AppLogger.error('match_live.pilot_signal', error, stackTrace);
      if (generation == _stateGeneration) unawaited(_refresh());
    }
  }

  Future<void> claimPilot({int? plannedDurationMinutes}) {
    return _mutate(
      (repository) => repository.claimPilot(
        matchId: arg,
        plannedDurationMinutes: plannedDurationMinutes,
      ),
    );
  }

  Future<void> takeOverPilot() {
    return _mutate(
      (repository) => repository.takeOverPilot(matchId: arg),
    );
  }

  Future<void> heartbeatPilot() {
    return _pilotSignal(
      (repository) => repository.heartbeatPilot(matchId: arg),
    );
  }

  Future<void> releasePilot() {
    return _pilotSignal(
      (repository) => repository.releasePilot(matchId: arg),
    );
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
    final attemptTimeout = ref.read(matchLiveWriteTimeoutProvider);
    final attemptBudget = attemptTimeout * 2 + const Duration(seconds: 1);
    return _mutate((repository) async {
      Future<MatchLiveStateBundle> send() => repository
          .adjustScore(
            matchId: arg,
            team: team,
            delta: delta,
            operationId: operationId,
            scorerParticipantId: scorerParticipantId,
          )
          .timeout(attemptTimeout);

      try {
        return await send();
      } catch (_) {
        return send();
      }
    }, writeTimeout: attemptBudget);
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

  Future<void> changeFormation({
    required String formationCode,
    required List<Map<String, dynamic>> entries,
    required int expectedLineupRevision,
  }) {
    return _mutate(
      (repository) => repository.changeLiveFormation(
        matchId: arg,
        formationCode: formationCode,
        entries: entries,
        expectedLineupRevision: expectedLineupRevision,
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
    String? assistParticipantId,
  }) {
    return _mutate(
      (repository) => repository.setEventScorer(
        matchId: arg,
        eventId: eventId,
        scorerParticipantId: scorerParticipantId,
        isOpponentOwnGoal: isOpponentOwnGoal,
        assistParticipantId: assistParticipantId,
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

  Future<void> restartSession({String? reason}) {
    return _mutate(
      (repository) => repository.restartSession(matchId: arg, reason: reason),
    );
  }
}
