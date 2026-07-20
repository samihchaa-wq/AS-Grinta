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
  @override
  Future<FeatureFlagsSnapshot> build() async {
    if (!ref.watch(featureFlagsSessionReadyProvider)) {
      return const FeatureFlagsSnapshot.unavailable();
    }
    return _loadFailClosed();
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
