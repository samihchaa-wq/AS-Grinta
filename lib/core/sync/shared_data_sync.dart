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

enum SharedDataRefreshScope { sports, all }

class SharedDataRefreshDecision {
  const SharedDataRefreshDecision({
    required this.scope,
    required this.refreshProfile,
  });

  final SharedDataRefreshScope scope;
  final bool refreshProfile;
}

class SharedDataChangeSignal {
  const SharedDataChangeSignal({
    required this.revision,
    required this.profileRevision,
    required this.sportsRevision,
    required this.updatedAt,
  });

  factory SharedDataChangeSignal.fromRow(Map<String, dynamic> row) {
    final revision = row['revision'];
    final profileRevision = row['profile_revision'];
    final sportsRevision = row['sports_revision'];
    final updatedAt = row['updated_at'];
    if (revision is! num ||
        (profileRevision != null && profileRevision is! num) ||
        (sportsRevision != null && sportsRevision is! num) ||
        updatedAt is! String) {
      throw const FormatException('Signal de synchronisation invalide.');
    }
    return SharedDataChangeSignal(
      revision: revision.toInt(),
      // Avant le déploiement de profile_revision, le fallback conserve le
      // comportement historique : chaque signal recharge aussi le profil.
      profileRevision:
          profileRevision is num ? profileRevision.toInt() : revision.toInt(),
      // Sans sports_revision, aucun lot ne peut être prouvé 100 % sportif :
      // le client garde donc le refresh global historique.
      sportsRevision: sportsRevision is num ? sportsRevision.toInt() : 0,
      updatedAt: DateTime.parse(updatedAt).toUtc(),
    );
  }

  final int revision;
  final int profileRevision;
  final int sportsRevision;
  final DateTime updatedAt;
}

/// Suit les révisions sans dépendre de Riverpod afin que la portée du refresh
/// puisse être testée séparément du flux Realtime.
class SharedDataSignalCursor {
  int? _lastRevision;
  int? _lastProfileRevision;
  int? _lastSportsRevision;

  /// Retourne `null` lorsque le signal est initial ou obsolète. Un refresh
  /// sportif n'est retenu que si toutes les révisions manquées sont sportives.
  SharedDataRefreshDecision? register(SharedDataChangeSignal signal) {
    final previousRevision = _lastRevision;
    if (previousRevision == null) {
      _lastRevision = signal.revision;
      _lastProfileRevision = signal.profileRevision;
      _lastSportsRevision = signal.sportsRevision;
      return null;
    }
    if (signal.revision <= previousRevision) return null;

    final previousProfileRevision = _lastProfileRevision ?? previousRevision;
    final previousSportsRevision = _lastSportsRevision ?? 0;
    final refreshProfile = signal.profileRevision > previousProfileRevision;
    final revisionDelta = signal.revision - previousRevision;
    final sportsDelta = signal.sportsRevision - previousSportsRevision;
    final sportsOnly =
        !refreshProfile && sportsDelta > 0 && sportsDelta == revisionDelta;

    _lastRevision = signal.revision;
    if (_lastProfileRevision == null ||
        signal.profileRevision > _lastProfileRevision!) {
      _lastProfileRevision = signal.profileRevision;
    }
    if (_lastSportsRevision == null ||
        signal.sportsRevision > _lastSportsRevision!) {
      _lastSportsRevision = signal.sportsRevision;
    }

    return SharedDataRefreshDecision(
      scope: sportsOnly
          ? SharedDataRefreshScope.sports
          : SharedDataRefreshScope.all,
      refreshProfile: refreshProfile,
    );
  }

  void reset() {
    _lastRevision = null;
    _lastProfileRevision = null;
    _lastSportsRevision = null;
  }
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

/// Invalide les caches de lecture partagés puis recharge les contrôleurs longue
/// durée uniquement lorsque le domaine touché le nécessite.
class SharedDataRefreshCoordinator {
  SharedDataRefreshCoordinator(this._ref);

  final Ref _ref;
  Future<void>? _refreshInFlight;
  SharedDataRefreshScope? _queuedScope;
  bool _refreshProfileQueued = false;

  Future<void> refreshAll({bool refreshProfile = true}) {
    return refresh(
      scope: SharedDataRefreshScope.all,
      refreshProfile: refreshProfile,
    );
  }

  Future<void> refresh({
    required SharedDataRefreshScope scope,
    required bool refreshProfile,
  }) {
    final queuedScope = _queuedScope;
    if (queuedScope == null ||
        (queuedScope == SharedDataRefreshScope.sports &&
            scope == SharedDataRefreshScope.all)) {
      _queuedScope = scope;
    }
    _refreshProfileQueued = _refreshProfileQueued || refreshProfile;

    final existing = _refreshInFlight;
    if (existing != null) return existing;

    final refresh = _drain();
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    });
  }

  Future<void> _drain() async {
    while (_queuedScope != null) {
      final scope = _queuedScope!;
      final refreshProfile = _refreshProfileQueued;
      _queuedScope = null;
      _refreshProfileQueued = false;
      await _refreshOnce(scope: scope, refreshProfile: refreshProfile);
    }
  }

  Future<void> _refreshOnce({
    required SharedDataRefreshScope scope,
    required bool refreshProfile,
  }) async {
    if (!_ref.read(authControllerProvider).isAuthenticated) return;

    if (refreshProfile) {
      await _ref.read(authControllerProvider.notifier).refreshProfile();
      if (!_ref.read(authControllerProvider).isAuthenticated) return;
    }

    if (scope == SharedDataRefreshScope.sports) {
      _invalidateSportsCaches();
      return;
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

  void _invalidateSportsCaches() {
    _ref
      ..invalidate(matchDetailsProvider)
      ..invalidate(myMatchAvailabilityProvider)
      ..invalidate(matchAvailabilityBoardProvider)
      ..invalidate(publishedMatchCompositionProvider);
  }

  void _invalidateSharedCaches() {
    _invalidateSportsCaches();
    _ref
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
      ..invalidate(publishedSportMatchResultProvider)
      ..invalidate(sportMotmVoteProvider);
  }
}

final sharedDataRefreshCoordinatorProvider =
    Provider<SharedDataRefreshCoordinator>((ref) {
  return SharedDataRefreshCoordinator(ref);
});

/// Écoute le petit signal Realtime public-safe. Les écritures métier restent
/// autoritaires dans leurs tables/RPC ; ce flux ne transporte que des révisions.
/// Un debounce absorbe les nombreuses écritures d'une finalisation de match.
final sharedDataSyncListenerProvider = Provider<void>((ref) {
  Timer? debounce;
  final cursor = SharedDataSignalCursor();
  SharedDataRefreshScope? refreshScopeQueued;
  bool refreshProfileQueued = false;
  String? lastProfileId = ref.read(authControllerProvider).profile?.id;

  ref.listen<AsyncValue<SharedDataChangeSignal?>>(
    sharedDataSignalProvider,
    (previous, next) {
      final signal = next.valueOrNull;
      if (signal == null) return;

      final decision = cursor.register(signal);
      if (decision == null) return;
      refreshProfileQueued = refreshProfileQueued || decision.refreshProfile;
      if (refreshScopeQueued == null ||
          decision.scope == SharedDataRefreshScope.all) {
        refreshScopeQueued = decision.scope;
      }

      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 350), () {
        final scope = refreshScopeQueued;
        if (scope == null) return;
        final shouldRefreshProfile = refreshProfileQueued;
        refreshScopeQueued = null;
        refreshProfileQueued = false;
        unawaited(
          ref
              .read(sharedDataRefreshCoordinatorProvider)
              .refresh(
                scope: scope,
                refreshProfile: shouldRefreshProfile,
              ),
        );
      });
    },
  );

  ref.listen<String?>(
    authControllerProvider.select((state) => state.profile?.id),
    (previous, next) {
      if (next == lastProfileId) return;
      lastProfileId = next;
      cursor.reset();
      refreshScopeQueued = null;
      refreshProfileQueued = false;
      debounce?.cancel();
      ref
          .read(sharedDataRefreshCoordinatorProvider)
          .invalidateForSessionChange();
      ref.invalidate(sharedDataSignalProvider);
    },
  );

  ref.onDispose(() => debounce?.cancel());
});
