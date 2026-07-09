import 'dart:async';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/live/data/live_repository.dart';
import 'package:as_grinta/features/live/domain/live_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LiveControllerState {
  const LiveControllerState({
    this.session,
    this.isLoading = false,
    this.error,
  });

  final LiveSessionState? session;
  final bool isLoading;
  final String? error;

  LiveControllerState copyWith({
    LiveSessionState? session,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return LiveControllerState(
      session: session ?? this.session,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class LiveController extends StateNotifier<LiveControllerState> {
  LiveController(this._repository, this._currentUserId)
      : super(const LiveControllerState());

  final LiveRepository _repository;
  final String? _currentUserId;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;

  Future<void> initialize(String matchId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      var session = await _repository.fetchLiveSession(matchId);
      if (session == null) {
        await _repository.createLiveSession(matchId: matchId);
        session = await _repository.fetchLiveSession(matchId);
      }
      state = state.copyWith(
        session: session,
        isLoading: false,
        clearError: true,
      );

      await _subscription?.cancel();
      _subscription = _repository.subscribeToLive(matchId).listen(
        (rows) {
          if (rows.isEmpty) return;
          state = state.copyWith(
            session: LiveSessionState.fromJson(rows.first),
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
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: error.toString(),
      );
    }
  }

  Future<void> start(String matchId) => _setStatus(matchId, 'running');

  Future<void> pause(String matchId) => _setStatus(matchId, 'paused');

  Future<void> setHalftime(String matchId) => _setStatus(matchId, 'halftime');

  Future<void> finish(String matchId) => _setStatus(matchId, 'finished');

  Future<void> claimControl(String matchId) async {
    final userId = _currentUserId;
    if (userId == null) {
      state = state.copyWith(error: 'Aucun utilisateur connecté.');
      return;
    }

    try {
      final sessionId = '$userId-${DateTime.now().microsecondsSinceEpoch}';
      await _repository.claimControl(
        matchId: matchId,
        profileId: userId,
        sessionId: sessionId,
      );
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> _setStatus(String matchId, String status) async {
    final session = state.session;
    try {
      await _repository.updateLiveSession(
        matchId: matchId,
        status: status,
        elapsedSeconds: session?.elapsedSeconds ?? 0,
        controllerProfileId: session?.controllerProfileId,
        controllerSessionId: session?.controllerSessionId,
      );
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final liveControllerProvider =
    StateNotifierProvider<LiveController, LiveControllerState>((ref) {
  final repository = ref.watch(liveRepositoryProvider);
  final currentUserId = ref.watch(supabaseClientProvider).auth.currentUser?.id;
  return LiveController(repository, currentUserId);
});
