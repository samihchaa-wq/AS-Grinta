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

class FeatureFlagsController extends AsyncNotifier<FeatureFlagsSnapshot> {
  StreamSubscription<FeatureFlagChangeSignal>? _changeSubscription;
  FeatureFlagChangeSignal? _lastSignal;
  bool _signalRefreshInProgress = false;
  bool _signalRefreshRequested = false;

  @override
  Future<FeatureFlagsSnapshot> build() async {
    final sessionReady = ref.watch(featureFlagsSessionReadyProvider);
    await _changeSubscription?.cancel();
    _changeSubscription = null;
    _lastSignal = null;

    ref.onDispose(() {
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
    _changeSubscription = ref
        .read(featureFlagsRepositoryProvider)
        .watchSportsManagementChanges()
        .listen(
          _handleServerSignal,
          onError: (Object error, StackTrace stackTrace) {
            AppLogger.error('feature_flags.watch', error, stackTrace);
          },
        );
  }

  void _handleServerSignal(FeatureFlagChangeSignal signal) {
    if (_lastSignal?.revision == signal.revision) return;
    _lastSignal = signal;

    final currentUpdatedAt = state.valueOrNull?.sportsManagement.updatedAt
        ?.toUtc();
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
