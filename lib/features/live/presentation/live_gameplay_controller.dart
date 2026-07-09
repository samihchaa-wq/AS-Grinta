import 'dart:async';

import 'package:as_grinta/features/live/data/live_repository.dart';
import 'package:as_grinta/features/live/domain/live_gameplay.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LiveGameplayStateModel {
  const LiveGameplayStateModel({this.gameplay, this.isLoading = false, this.error});

  final LiveGameplayState? gameplay;
  final bool isLoading;
  final String? error;

  LiveGameplayStateModel copyWith({LiveGameplayState? gameplay, bool? isLoading, String? error}) {
    return LiveGameplayStateModel(
      gameplay: gameplay ?? this.gameplay,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class LiveGameplayController extends StateNotifier<LiveGameplayStateModel> {
  LiveGameplayController(this._repository, this._matchId) : super(const LiveGameplayStateModel());

  final LiveRepository _repository;
  final String _matchId;
  StreamSubscription<LiveGameplayState>? _subscription;

  Future<void> initialize({required List<LivePlayer> players, String formationKey = '4-4-2'}) async {
    state = state.copyWith(isLoading: true, error: null);
    final existing = _repository.loadGameplay(_matchId);
    if (existing != null) {
      _subscription?.cancel();
      _subscription = _repository.subscribeToGameplay(_matchId).listen((gameplay) {
        state = state.copyWith(gameplay: gameplay, isLoading: false);
      });
      state = state.copyWith(gameplay: existing, isLoading: false);
      return;
    }

    final initialState = LiveGameplayState.initial(players: players, formationKey: formationKey);
    _repository.saveGameplay(_matchId, initialState);
    _subscription?.cancel();
    _subscription = _repository.subscribeToGameplay(_matchId).listen((gameplay) {
      state = state.copyWith(gameplay: gameplay, isLoading: false);
    });
    state = state.copyWith(gameplay: initialState, isLoading: false);
  }

  void changeFormation(String formationKey) {
    final gameplay = state.gameplay;
    if (gameplay == null) return;
    gameplay.changeFormation(formationKey);
    _repository.saveGameplay(_matchId, gameplay);
    state = state.copyWith(gameplay: gameplay, error: null);
  }

  void movePlayer({required String playerId, required String slotKey}) {
    final gameplay = state.gameplay;
    if (gameplay == null) return;
    gameplay.movePlayer(playerId: playerId, slotKey: slotKey);
    _repository.saveGameplay(_matchId, gameplay);
    state = state.copyWith(gameplay: gameplay, error: null);
  }

  void addGoal({
    required String team,
    required int minute,
    required GoalType type,
    required String? scorerId,
    required String? assisterId,
  }) {
    final gameplay = state.gameplay;
    if (gameplay == null) return;
    gameplay.addGoal(team: team, minute: minute, type: type, scorerId: scorerId, assisterId: assisterId);
    _repository.saveGameplay(_matchId, gameplay);
    state = state.copyWith(gameplay: gameplay, error: null);
  }

  void removeGoal(String goalId) {
    final gameplay = state.gameplay;
    if (gameplay == null) return;
    gameplay.removeGoal(goalId);
    _repository.saveGameplay(_matchId, gameplay);
    state = state.copyWith(gameplay: gameplay, error: null);
  }

  void updateGoal({
    required String goalId,
    required String team,
    required int minute,
    required GoalType type,
    required String? scorerId,
    required String? assisterId,
  }) {
    final gameplay = state.gameplay;
    if (gameplay == null) return;
    gameplay.updateGoal(goalId: goalId, team: team, minute: minute, type: type, scorerId: scorerId, assisterId: assisterId);
    _repository.saveGameplay(_matchId, gameplay);
    state = state.copyWith(gameplay: gameplay, error: null);
  }

  void addSubstitution({required int minute, required String inPlayerId, required String outPlayerId}) {
    final gameplay = state.gameplay;
    if (gameplay == null) return;
    gameplay.addSubstitution(minute: minute, inPlayerId: inPlayerId, outPlayerId: outPlayerId);
    _repository.saveGameplay(_matchId, gameplay);
    state = state.copyWith(gameplay: gameplay, error: null);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final liveGameplayControllerProvider = StateNotifierProvider.family<LiveGameplayController, LiveGameplayStateModel, String>((ref, matchId) {
  final repository = ref.watch(liveGameplayRepositoryProvider);
  return LiveGameplayController(repository, matchId);
});
