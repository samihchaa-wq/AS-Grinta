import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_availability.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final myMatchAvailabilityProvider = FutureProvider.autoDispose
    .family<MatchAvailability?, String>((ref, matchId) async {
  if (!ref.watch(sportsManagementEnabledProvider)) {
    return null;
  }

  try {
    return await ref
        .watch(matchAvailabilityRepositoryProvider)
        .fetchMyAvailability(matchId);
  } catch (error, stackTrace) {
    AppLogger.error(
      'sports_management.fetch_my_availability',
      error,
      stackTrace,
    );
    return null;
  }
});
