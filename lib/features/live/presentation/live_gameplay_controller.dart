import 'dart:async';

import 'package:as_grinta/features/live/data/live_repository.dart';
import 'package:as_grinta/features/live/domain/live_gameplay.dart';
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
  LiveGameplayController(this._repository, this._matchId)
      : super(const LiveGameplayStateModel());

  final LiveRepository _repository;
  final String _matchId;
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

  Future<void> changeFormation(String formationKey) async {
    try {
      await _repository.setFormation(_matchId, formationKey);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> movePlayer({
    required String playerId,
    required String slotKey,
  }) async {
    try {
      await _repository.movePlayer(
        matchId: _matchId,
        playerId: playerId,
        slotKey: slotKey,
      );
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
    try {
      await _repository.addGoal(
        matchId: _matchId,
        team: team,
        minute: minute,
        type: type,
        scorerId: scorerId,
        assisterId: assisterId,
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> removeGoal(String goalId) async {
    try {
      await _repository.removeGoal(goalId);
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
    try {
      await _repository.updateGoal(
        goalId: goalId,
        team: team,
        minute: minute,
        type: type,
        scorerId: scorerId,
        assisterId: assisterId,
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> addSubstitution({
    required int minute,
    required String inPlayerId,
    required String outPlayerId,
  }) async {
    try {
      await _repository.addSubstitution(
        matchId: _matchId,
        minute: minute,
        inPlayerId: inPlayerId,
        outPlayerId: outPlayerId,
      );
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
  return LiveGameplayController(repository, matchId);
});
