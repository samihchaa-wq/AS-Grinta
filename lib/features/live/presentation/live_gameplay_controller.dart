import 'dart:async';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/live/data/live_repository.dart';
import 'package:as_grinta/features/live/domain/live_gameplay.dart';
import 'package:as_grinta/features/live/presentation/live_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LiveGameplayStateModel {
  const LiveGameplayStateModel({
    this.gameplay,
    this.isLoading = false,
    this.error,
  });

  final LiveGameplayState? gameplay;
  final bool isLoading;
  final String? error;

  LiveGameplayStateModel copyWith({
    LiveGameplayState? gameplay,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return LiveGameplayStateModel(
      gameplay: gameplay ?? this.gameplay,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class LiveGameplayController extends StateNotifier<LiveGameplayStateModel> {
  LiveGameplayController(this._repository, this._matchId, this._ref)
      : super(const LiveGameplayStateModel());

  final LiveRepository _repository;
  final String _matchId;
  final Ref _ref;
  StreamSubscription<LiveGameplayState>? _subscription;
  List<LivePlayer> _players = const [];
  String _fallbackFormation = '4-4-2';

  Future<void> initialize({
    required List<LivePlayer> players,
    String formationKey = '4-4-2',
  }) async {
    _players = players;
    _fallbackFormation = formationKey;
    state = state.copyWith(isLoading: true, clearError: true);
    await _subscription?.cancel();
    _subscription = _repository
        .subscribeToGameplay(
          matchId: _matchId,
          players: players,
          fallbackFormation: formationKey,
        )
        .listen(
          (gameplay) {
            state = state.copyWith(
              gameplay: gameplay,
              isLoading: false,
              clearError: true,
            );
          },
          onError: (Object error) {
            state = state.copyWith(
              isLoading: false,
              error: error.toString(),
            );
          },
        );
  }

  bool _canWrite() {
    final authState = _ref.read(authControllerProvider);
    final currentUserId = _ref.read(supabaseClientProvider).auth.currentUser?.id;
    final controllerSessionId = _ref.read(liveControlSessionIdProvider);
    final liveSession = _ref.read(liveControllerProvider).session;

    final allowed = authState.profile?.role == AuthRole.admin &&
        currentUserId != null &&
        controllerSessionId != null &&
        liveSession?.controllerProfileId == currentUserId &&
        liveSession?.controllerSessionId == controllerSessionId;

    if (!allowed) {
      state = state.copyWith(
        error: 'Cette session ne contrôle pas le Live.',
      );
    }
    return allowed;
  }

  Future<void> changeFormation(String formationKey) async {
    if (!_canWrite()) return;
    try {
      await _repository.setFormation(_matchId, formationKey);
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> movePlayer({
    required String playerId,
    required String slotKey,
  }) async {
    if (!_canWrite()) return;
    try {
      await _repository.movePlayer(
        matchId: _matchId,
        playerId: playerId,
        slotKey: slotKey,
      );
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> addGoal({
    required String team,
    required int minute,
    required GoalType type,
    required String? scorerId,
    required String? assisterId,
  }) async {
    if (!_canWrite()) return;
    if (minute < 0 || minute > 100) {
      state = state.copyWith(error: 'Minute invalide.');
      return;
    }
    final hidesPlayers = team != 'grinta' || type == GoalType.ownGoal;
    if (!hidesPlayers && scorerId == null) {
      state = state.copyWith(error: 'Le buteur est obligatoire.');
      return;
    }
    if (scorerId != null && assisterId == scorerId) {
      state = state.copyWith(
        error: 'Le passeur doit être différent du buteur.',
      );
      return;
    }

    try {
      await _repository.addGoal(
        matchId: _matchId,
        team: team,
        minute: minute,
        type: type,
        scorerId: hidesPlayers ? null : scorerId,
        assisterId: hidesPlayers ? null : assisterId,
      );
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> removeGoal(String goalId) async {
    if (!_canWrite()) return;
    try {
      await _repository.removeGoal(goalId);
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> updateGoal({
    required String goalId,
    required String team,
    required int minute,
    required GoalType type,
    required String? scorerId,
    required String? assisterId,
  }) async {
    if (!_canWrite()) return;
    if (minute < 0 || minute > 100) {
      state = state.copyWith(error: 'Minute invalide.');
      return;
    }
    final hidesPlayers = team != 'grinta' || type == GoalType.ownGoal;
    if (!hidesPlayers && scorerId == null) {
      state = state.copyWith(error: 'Le buteur est obligatoire.');
      return;
    }
    if (scorerId != null && assisterId == scorerId) {
      state = state.copyWith(
        error: 'Le passeur doit être différent du buteur.',
      );
      return;
    }

    try {
      await _repository.updateGoal(
        goalId: goalId,
        team: team,
        minute: minute,
        type: type,
        scorerId: hidesPlayers ? null : scorerId,
        assisterId: hidesPlayers ? null : assisterId,
      );
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> addSubstitution({
    required int minute,
    required String inPlayerId,
    required String outPlayerId,
  }) async {
    if (!_canWrite()) return;
    if (minute < 0 || minute > 100) {
      state = state.copyWith(error: 'Minute invalide.');
      return;
    }
    if (inPlayerId == outPlayerId) {
      state = state.copyWith(
        error: 'Les joueurs entrant et sortant doivent être différents.',
      );
      return;
    }

    final gameplay = state.gameplay;
    if (gameplay == null ||
        !gameplay.bench.contains(inPlayerId) ||
        !gameplay.lineup.values.contains(outPlayerId)) {
      state = state.copyWith(
        error: 'Remplacement invalide : vérifiez le banc et le terrain.',
      );
      return;
    }

    try {
      await _repository.addSubstitution(
        matchId: _matchId,
        minute: minute,
        inPlayerId: inPlayerId,
        outPlayerId: outPlayerId,
      );
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> reload() async {
    await initialize(
      players: _players,
      formationKey: _fallbackFormation,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final liveGameplayControllerProvider = StateNotifierProvider.family<
    LiveGameplayController, LiveGameplayStateModel, String>((ref, matchId) {
  final repository = ref.watch(liveGameplayRepositoryProvider);
  return LiveGameplayController(repository, matchId, ref);
});
