import 'dart:async';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/live/data/live_repository.dart';
import 'package:as_grinta/features/live/domain/live_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final liveControlSessionIdProvider = StateProvider<String?>((ref) => null);

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
  LiveController(
    this._repository,
    this._currentUserId,
    this._currentRole,
    this._ref,
  ) : super(const LiveControllerState());

  final LiveRepository _repository;
  final String? _currentUserId;
  final AuthRole? _currentRole;
  final Ref _ref;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;

  bool get _isAdmin => _currentRole == AuthRole.admin;
  bool get _isModerator => _currentRole == AuthRole.moderateur;
  bool get _canOperateRecoveredLive => _isAdmin || _isModerator;

  Future<void> initialize(String matchId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      var session = await _repository.fetchLiveSession(matchId);
      if (session == null) {
        if (!_isAdmin) {
          throw StateError(
            'Seul un administrateur peut initialiser une session Live.',
          );
        }
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
          final nextSession = LiveSessionState.fromJson(rows.first);
          final localSessionId = _ref.read(liveControlSessionIdProvider);
          if (localSessionId != null &&
              nextSession.controllerProfileId != _currentUserId) {
            _ref.read(liveControlSessionIdProvider.notifier).state = null;
          }
          state = state.copyWith(
            session: nextSession,
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
    if (!_isAdmin) {
      state = state.copyWith(
        error: 'Seul un administrateur peut prendre le contrôle du Live.',
      );
      return;
    }
    if (userId == null) {
      state = state.copyWith(error: 'Aucun utilisateur connecté.');
      return;
    }

    try {
      final sessionId = '$userId-${DateTime.now().microsecondsSinceEpoch}';
      final claimed = await _repository.claimControl(
        matchId: matchId,
        profileId: userId,
        sessionId: sessionId,
      );
      if (!claimed) {
        state = state.copyWith(
          error: 'Ce Live est déjà contrôlé par une autre connexion.',
        );
        return;
      }
      _ref.read(liveControlSessionIdProvider.notifier).state = sessionId;
      final session = await _repository.fetchLiveSession(matchId);
      state = state.copyWith(session: session, clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> releaseControl(String matchId) async {
    final sessionId = _ref.read(liveControlSessionIdProvider);
    if (!_canOperateRecoveredLive || sessionId == null) {
      state = state.copyWith(error: 'Cette connexion ne contrôle pas le Live.');
      return;
    }

    try {
      final released = await _repository.releaseControl(
        matchId: matchId,
        sessionId: sessionId,
      );
      if (!released) {
        state = state.copyWith(error: 'La cession du contrôle a été refusée.');
        return;
      }
      _ref.read(liveControlSessionIdProvider.notifier).state = null;
      final session = await _repository.fetchLiveSession(matchId);
      state = state.copyWith(session: session, clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> markDisconnected(String matchId) async {
    final sessionId = _ref.read(liveControlSessionIdProvider);
    if (sessionId == null) return;
    try {
      await _repository.markDisconnected(
        matchId: matchId,
        sessionId: sessionId,
      );
    } catch (_) {
      // Best effort during lifecycle changes or network loss.
    }
  }

  Future<void> forceResumeControl(String matchId) async {
    final userId = _currentUserId;
    if (!_isModerator || userId == null) {
      state = state.copyWith(
        error: 'Seul le Modérateur peut effectuer une reprise forcée.',
      );
      return;
    }

    try {
      final sessionId =
          'moderator-$userId-${DateTime.now().microsecondsSinceEpoch}';
      final resumed = await _repository.forceResumeControl(
        matchId: matchId,
        sessionId: sessionId,
      );
      if (!resumed) {
        state = state.copyWith(
          error: 'Le délai de grâce de 60 secondes n’est pas terminé.',
        );
        return;
      }
      _ref.read(liveControlSessionIdProvider.notifier).state = sessionId;
      final session = await _repository.fetchLiveSession(matchId);
      state = state.copyWith(session: session, clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> _setStatus(String matchId, String status) async {
    final userId = _currentUserId;
    final sessionId = _ref.read(liveControlSessionIdProvider);
    if (!_canOperateRecoveredLive || userId == null || sessionId == null) {
      state = state.copyWith(
        error: 'Vous devez contrôler ce Live avant cette action.',
      );
      return;
    }

    final session = state.session;
    if (session?.controllerProfileId != userId) {
      _ref.read(liveControlSessionIdProvider.notifier).state = null;
      state = state.copyWith(
        error: 'Cette connexion ne contrôle plus le Live.',
      );
      return;
    }

    try {
      final updated = await _repository.updateLiveSession(
        matchId: matchId,
        status: status,
        elapsedSeconds: session?.elapsedSeconds ?? 0,
        controllerProfileId: userId,
        controllerSessionId: sessionId,
      );
      if (!updated) {
        _ref.read(liveControlSessionIdProvider.notifier).state = null;
        state = state.copyWith(
          error: 'Le contrôle du Live a changé. Action refusée.',
        );
        return;
      }
      final refreshed = await _repository.fetchLiveSession(matchId);
      state = state.copyWith(session: refreshed, clearError: true);
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
  final currentRole = ref.watch(authControllerProvider).profile?.role;
  return LiveController(repository, currentUserId, currentRole, ref);
});
