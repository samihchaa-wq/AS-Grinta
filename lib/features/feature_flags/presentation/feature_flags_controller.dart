import 'dart:async';

import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/data/feature_flags_repository.dart';
import 'package:as_grinta/features/feature_flags/domain/feature_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final featureFlagsSessionReadyProvider = Provider<bool>((ref) {
  final authState = ref.watch(authControllerProvider);
  return !authState.isLoading && authState.isAuthenticated;
});

typedef FeatureFlagsWatchRetryDelay = Duration Function(int attempt);

final featureFlagsWatchRetryDelayProvider =
    Provider<FeatureFlagsWatchRetryDelay>((ref) {
  return (attempt) {
    if (attempt <= 1) return const Duration(seconds: 5);
    if (attempt == 2) return const Duration(seconds: 15);
    return const Duration(minutes: 1);
  };
});

class FeatureFlagsController extends AsyncNotifier<FeatureFlagsSnapshot> {
  StreamSubscription<FeatureFlagChangeSignal>? _changeSubscription;
  Timer? _watchRetryTimer;
  FeatureFlagChangeSignal? _lastSignal;
  bool _signalRefreshInProgress = false;
  bool _signalRefreshRequested = false;
  bool _watchErrorLogged = false;
  bool _disposed = false;
  int _watchFailureCount = 0;

  @override
  Future<FeatureFlagsSnapshot> build() async {
    _disposed = false;
    final sessionReady = ref.watch(featureFlagsSessionReadyProvider);
    _watchRetryTimer?.cancel();
    _watchRetryTimer = null;
    await _changeSubscription?.cancel();
    _changeSubscription = null;
    _lastSignal = null;
    _watchFailureCount = 0;
    _watchErrorLogged = false;

    ref.onDispose(() {
      _disposed = true;
      _watchRetryTimer?.cancel();
      _watchRetryTimer = null;
      unawaited(_changeSubscription?.cancel() ?? Future<void>.value());
    });

    if (!sessionReady) {
      return const FeatureFlagsSnapshot.unavailable();
    }

    final snapshot = await _loadFailClosed();
    _watchServerChanges();
    return snapshot;
  }

  void _watchServerChanges() {
    if (_disposed || !ref.read(featureFlagsSessionReadyProvider)) return;

    try {
      _changeSubscription = ref
          .read(featureFlagsRepositoryProvider)
          .watchSportsManagementChanges()
          .listen(
        (signal) {
          _watchFailureCount = 0;
          _watchErrorLogged = false;
          _handleServerSignal(signal);
        },
        onError: _handleWatchError,
        onDone: _handleWatchDone,
      );
    } catch (error, stackTrace) {
      _handleWatchError(error, stackTrace);
    }
  }

  void _handleWatchError(Object error, StackTrace stackTrace) {
    if (_disposed || !ref.read(featureFlagsSessionReadyProvider)) return;

    _watchFailureCount += 1;
    if (!_watchErrorLogged) {
      _watchErrorLogged = true;
      AppLogger.error('feature_flags.watch', error, stackTrace);
    }
    _scheduleWatchRestart();
  }

  void _handleWatchDone() {
    if (_disposed || !ref.read(featureFlagsSessionReadyProvider)) return;
    if (_watchFailureCount == 0) {
      _watchFailureCount = 1;
    }
    _scheduleWatchRestart();
  }

  void _scheduleWatchRestart() {
    if (_disposed || _watchRetryTimer != null) return;
    if (!ref.read(featureFlagsSessionReadyProvider)) return;

    final attempt = _watchFailureCount <= 0 ? 1 : _watchFailureCount;
    final delay = ref.read(featureFlagsWatchRetryDelayProvider)(attempt);
    _watchRetryTimer = Timer(delay, () {
      _watchRetryTimer = null;
      unawaited(_restartServerWatch());
    });
  }

  Future<void> _restartServerWatch() async {
    await _changeSubscription?.cancel();
    _changeSubscription = null;
    if (_disposed || !ref.read(featureFlagsSessionReadyProvider)) return;
    _watchServerChanges();
  }

  void _handleServerSignal(FeatureFlagChangeSignal signal) {
    if (_lastSignal?.revision == signal.revision) return;
    _lastSignal = signal;

    final currentUpdatedAt =
        state.valueOrNull?.sportsManagement.updatedAt?.toUtc();
    if (currentUpdatedAt != null &&
        !signal.updatedAt.isAfter(currentUpdatedAt)) {
      return;
    }

    _signalRefreshRequested = true;
    if (!_signalRefreshInProgress) {
      unawaited(_refreshFromSignals());
    }
  }

  Future<void> _refreshFromSignals() async {
    _signalRefreshInProgress = true;
    try {
      while (_signalRefreshRequested) {
        _signalRefreshRequested = false;
        if (!ref.read(featureFlagsSessionReadyProvider)) return;

        final next = await _loadFailClosed();
        if (!ref.read(featureFlagsSessionReadyProvider)) return;
        state = AsyncData(next);
      }
    } finally {
      _signalRefreshInProgress = false;
    }
  }

  Future<FeatureFlagsSnapshot> _loadFailClosed() async {
    try {
      return await ref.read(featureFlagsRepositoryProvider).fetchFeatureFlags();
    } catch (error, stackTrace) {
      AppLogger.error('feature_flags.fetch', error, stackTrace);
      return const FeatureFlagsSnapshot.unavailable();
    }
  }

  Future<void> refresh() async {
    if (!ref.read(featureFlagsSessionReadyProvider)) {
      state = const AsyncData(FeatureFlagsSnapshot.unavailable());
      return;
    }
    state = const AsyncLoading();
    state = AsyncData(await _loadFailClosed());
  }

  Future<FeatureFlagsSnapshot> setSportsManagementEnabled({
    required bool enabled,
    String? justification,
  }) async {
    final previous =
        state.valueOrNull ?? const FeatureFlagsSnapshot.unavailable();
    state = const AsyncLoading();

    try {
      final next = await ref
          .read(featureFlagsRepositoryProvider)
          .setSportsManagementEnabled(
            enabled: enabled,
            justification: justification,
          );
      state = AsyncData(next);
      return next;
    } catch (error, stackTrace) {
      AppLogger.error('feature_flags.set_sports_management', error, stackTrace);
      state = AsyncData(previous);
      rethrow;
    }
  }
}

final featureFlagsControllerProvider =
    AsyncNotifierProvider<FeatureFlagsController, FeatureFlagsSnapshot>(
  FeatureFlagsController.new,
);

final sportsManagementEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(featureFlagsControllerProvider)
          .valueOrNull
          ?.sportsManagement
          .enabled ??
      false;
});
