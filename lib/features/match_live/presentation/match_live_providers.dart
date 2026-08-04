import 'dart:async';

import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/match_live/data/match_live_repository.dart';
import 'package:as_grinta/features/match_live/domain/match_live_add_player_options.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/domain/match_live_timeline.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final matchLiveTimelineProvider =
    FutureProvider.autoDispose.family<MatchLiveTimeline?, String>((
  ref,
  matchId,
) {
  return ref.watch(matchLiveRepositoryProvider).fetchTimeline(matchId);
});

final matchLiveStateProvider = AsyncNotifierProvider.autoDispose
    .family<MatchLiveStateController, MatchLiveStateBundle, String>(
  MatchLiveStateController.new,
);

class MatchLiveStateController
    extends AutoDisposeFamilyAsyncNotifier<MatchLiveStateBundle, String> {
  StreamSubscription<void>? _subscription;

  @override
  Future<MatchLiveStateBundle> build(String matchId) async {
    final repository = ref.watch(matchLiveRepositoryProvider);
    _subscription = repository.watchChanges(matchId).listen(
          (_) => unawaited(_refresh()),
          onError: (Object error, StackTrace stackTrace) =>
              AppLogger.error('match_live.watch_changes', error, stackTrace),
        );
    ref.onDispose(() => _subscription?.cancel());
    return repository.fetchLiveState(matchId);
  }

  Future<void> _refresh() async {
    final repository = ref.read(matchLiveRepositoryProvider);
    try {
      final bundle = await repository.fetchLiveState(arg);
      state = AsyncData(bundle);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> _mutate(
    Future<MatchLiveStateBundle> Function(MatchLiveRepository repository)
        action,
  ) async {
    final repository = ref.read(matchLiveRepositoryProvider);
    final bundle = await action(repository);
    state = AsyncData(bundle);
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
    return _mutate(
      (repository) => repository.adjustScore(
        matchId: arg,
        team: team,
        delta: delta,
        scorerParticipantId: scorerParticipantId,
      ),
    );
  }

  Future<void> saveLiveLineup({
    required List<Map<String, dynamic>> entries,
    List<({String playerIn, String playerOut})> substitutions = const [],
  }) {
    return _mutate(
      (repository) => repository.saveLiveLineup(
        matchId: arg,
        entries: entries,
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
