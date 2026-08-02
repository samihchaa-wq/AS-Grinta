import 'dart:async';

import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/badges/data/badge_inbox_repository.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/data/featured_badges_repository.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/players/data/roster_repository.dart';
import 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
import 'package:as_grinta/features/predictions/presentation/season_gauges_providers.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/inline_match_prediction_card.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_board_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_match_finalization_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_motm_vote_repository.dart';
import 'package:as_grinta/features/sports_management/presentation/match_availability_provider.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SharedDataChangeSignal {
  const SharedDataChangeSignal({
    required this.revision,
    required this.updatedAt,
  });

  factory SharedDataChangeSignal.fromRow(Map<String, dynamic> row) {
    final revision = row['revision'];
    final updatedAt = row['updated_at'];
    if (revision is! num || updatedAt is! String) {
      throw const FormatException('Signal de synchronisation invalide.');
    }
    return SharedDataChangeSignal(
      revision: revision.toInt(),
      updatedAt: DateTime.parse(updatedAt).toUtc(),
    );
  }

  final int revision;
  final DateTime updatedAt;
}

class SharedDataSyncRepository {
  SharedDataSyncRepository(this._client);

  final SupabaseClient _client;

  Stream<SharedDataChangeSignal> watchChanges() {
    return _client
        .from('shared_data_change_signals')
        .stream(primaryKey: ['key'])
        .eq('key', 'global')
        .where((rows) => rows.isNotEmpty)
        .map((rows) => SharedDataChangeSignal.fromRow(rows.first));
  }
}

final sharedDataSyncRepositoryProvider =
    Provider<SharedDataSyncRepository>((ref) {
  return SharedDataSyncRepository(ref.watch(supabaseClientProvider));
});

final sharedDataSignalProvider = StreamProvider<SharedDataChangeSignal?>((ref) {
  final authenticated = ref.watch(
    authControllerProvider.select((state) => state.isAuthenticated),
  );
  if (!authenticated) return Stream<SharedDataChangeSignal?>.value(null);
  return ref.watch(sharedDataSyncRepositoryProvider).watchChanges();
});

/// Invalide les caches de lecture partagés puis recharge les deux contrôleurs
/// longue durée qui ne sont pas des FutureProvider. C'est volontairement
/// centralisé : une écriture dans un module ne doit plus connaître à la main
/// la liste des autres écrans qu'elle impacte.
class SharedDataRefreshCoordinator {
  SharedDataRefreshCoordinator(this._ref);

  final Ref _ref;
  Future<void>? _refreshInFlight;
  bool _refreshQueued = false;

  Future<void> refreshAll({bool refreshProfile = true}) {
    _refreshQueued = true;
    final existing = _refreshInFlight;
    if (existing != null) return existing;

    final refresh = _drain(refreshProfile: refreshProfile);
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    });
  }

  Future<void> _drain({required bool refreshProfile}) async {
    var shouldRefreshProfile = refreshProfile;
    while (_refreshQueued) {
      _refreshQueued = false;
      await _refreshOnce(refreshProfile: shouldRefreshProfile);
      shouldRefreshProfile = true;
    }
  }

  Future<void> _refreshOnce({required bool refreshProfile}) async {
    if (!_ref.read(authControllerProvider).isAuthenticated) return;

    if (refreshProfile) {
      await _ref.read(authControllerProvider.notifier).refreshProfile();
      if (!_ref.read(authControllerProvider).isAuthenticated) return;
    }

    _invalidateSharedCaches();

    try {
      await Future.wait<void>([
        _ref.read(matchesControllerProvider.notifier).load(allSeasons: true),
        _ref.read(predictionsControllerProvider.notifier).load(),
      ]);
    } catch (error, stackTrace) {
      AppLogger.error('shared_data.refresh_controllers', error, stackTrace);
    }
  }

  void invalidateForSessionChange() {
    _invalidateSharedCaches();
    _ref.invalidate(matchesControllerProvider);
    _ref.invalidate(predictionsControllerProvider);
  }

  void _invalidateSharedCaches() {
    _ref
      ..invalidate(matchDetailsProvider)
      ..invalidate(matchInfoProvider)
      ..invalidate(inlineMatchPredictionProvider)
      ..invalidate(statisticsPeriodProvider)
      ..invalidate(teamStatisticsPeriodProvider)
      ..invalidate(leaderboardProvider)
      ..invalidate(enhancedSeasonLockedProvider)
      ..invalidate(enhancedSeasonGaugesProvider)
      ..invalidate(enhancedSeasonCompletedMatchesProvider)
      ..invalidate(adminDashboardProvider)
      ..invalidate(openSeasonIdProvider)
      ..invalidate(rosterProvider)
      ..invalidate(myArmoireProvider)
      ..invalidate(myFeaturedCodesProvider)
      ..invalidate(featuredBadgesProvider)
      ..invalidate(hasUnseenBadgeProvider)
      ..invalidate(myMatchAvailabilityProvider)
      ..invalidate(matchAvailabilityBoardProvider)
      ..invalidate(publishedMatchCompositionProvider)
      ..invalidate(publishedSportMatchResultProvider)
      ..invalidate(sportMotmVoteProvider);
  }
}

final sharedDataRefreshCoordinatorProvider =
    Provider<SharedDataRefreshCoordinator>((ref) {
  return SharedDataRefreshCoordinator(ref);
});

/// Écoute le petit signal Realtime public-safe. Les écritures métier restent
/// autoritaires dans leurs tables/RPC ; ce flux ne transporte qu'une révision.
/// Un debounce absorbe les nombreuses écritures d'une finalisation de match.
final sharedDataSyncListenerProvider = Provider<void>((ref) {
  Timer? debounce;
  int? lastRevision;
  String? lastProfileId = ref.read(authControllerProvider).profile?.id;

  ref.listen<AsyncValue<SharedDataChangeSignal?>>(
    sharedDataSignalProvider,
    (previous, next) {
      final signal = next.valueOrNull;
      if (signal == null) return;

      if (lastRevision == null) {
        lastRevision = signal.revision;
        return;
      }
      if (signal.revision <= lastRevision!) return;
      lastRevision = signal.revision;

      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 350), () {
        unawaited(ref.read(sharedDataRefreshCoordinatorProvider).refreshAll());
      });
    },
  );

  ref.listen<String?>(
    authControllerProvider.select((state) => state.profile?.id),
    (previous, next) {
      if (next == lastProfileId) return;
      lastProfileId = next;
      lastRevision = null;
      debounce?.cancel();
      ref
          .read(sharedDataRefreshCoordinatorProvider)
          .invalidateForSessionChange();
      ref.invalidate(sharedDataSignalProvider);
    },
  );

  ref.onDispose(() => debounce?.cancel());
});
