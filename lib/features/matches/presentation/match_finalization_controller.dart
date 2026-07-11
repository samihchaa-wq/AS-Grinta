import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchFinalizationState {
  const MatchFinalizationState({this.isLoading = false, this.error});

  final bool isLoading;
  final String? error;

  MatchFinalizationState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return MatchFinalizationState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class MatchFinalizationController
    extends StateNotifier<MatchFinalizationState> {
  MatchFinalizationController(this._repository, this._ref)
      : super(const MatchFinalizationState());

  final MatchesRepository _repository;
  final Ref _ref;

  Future<bool> finalizeMatch({
    required String matchId,
    required int opponentScore,
    required String? manOfTheMatchId,
    required List<Map<String, dynamic>> playerStats,
    required List<Map<String, dynamic>> guestStats,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    if (_ref.read(authControllerProvider).profile?.role != AuthRole.admin) {
      state = state.copyWith(
        isLoading: false,
        error: 'Seul un administrateur peut valider le résultat.',
      );
      return false;
    }
    if (opponentScore < 0) {
      state = state.copyWith(isLoading: false, error: 'Score adverse invalide.');
      return false;
    }

    final playerIds = <String>{};
    for (final item in playerStats) {
      final profileId = item['profile_id']?.toString() ?? '';
      if (profileId.isEmpty || !playerIds.add(profileId)) {
        state = state.copyWith(
          isLoading: false,
          error: 'La liste des joueurs contient un doublon ou un joueur invalide.',
        );
        return false;
      }
    }

    final guestNames = <String>{};
    for (final item in guestStats) {
      final name = (item['display_name'] ?? '').toString().trim();
      if (name.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'Le nom de chaque invité est requis.',
        );
        return false;
      }
      if (!guestNames.add(name.toLowerCase())) {
        state = state.copyWith(
          isLoading: false,
          error: 'Deux invités ne peuvent pas avoir le même nom.',
        );
        return false;
      }
    }

    final allStats = [...playerStats, ...guestStats];
    for (final item in allStats) {
      final present = item['present'] == true;
      final goals = _asInt(item['goals']);
      final assists = _asInt(item['assists']);
      final penaltyFaults = _asInt(item['penalty_faults']);
      final cleanSheet = item['clean_sheet'] == true;
      if (goals < 0 || assists < 0 || penaltyFaults < 0) {
        state = state.copyWith(
          isLoading: false,
          error: 'Les statistiques négatives sont interdites.',
        );
        return false;
      }
      if (!present &&
          (goals > 0 || assists > 0 || penaltyFaults > 0 || cleanSheet)) {
        state = state.copyWith(
          isLoading: false,
          error: 'Un joueur absent ne peut pas avoir de statistiques.',
        );
        return false;
      }
    }

    final totalGoals = allStats.fold<int>(
      0,
      (sum, item) => sum + _asInt(item['goals']),
    );
    final totalAssists = allStats.fold<int>(
      0,
      (sum, item) => sum + _asInt(item['assists']),
    );
    if (totalAssists > totalGoals) {
      state = state.copyWith(
        isLoading: false,
        error: 'Le nombre de passes décisives ne peut pas dépasser le nombre de buts.',
      );
      return false;
    }

    if (opponentScore > 0 &&
        playerStats.any((item) => item['clean_sheet'] == true)) {
      state = state.copyWith(
        isLoading: false,
        error: 'Un clean sheet est impossible si l’adversaire a marqué.',
      );
      return false;
    }

    if (manOfTheMatchId != null && !playerIds.contains(manOfTheMatchId)) {
      state = state.copyWith(
        isLoading: false,
        error: 'L’homme du match sélectionné est invalide.',
      );
      return false;
    }

    try {
      await _repository.finalizeMatchPostgame(
        id: matchId,
        opponentScore: opponentScore,
        manOfTheMatchId: manOfTheMatchId,
        playerStats: playerStats,
        guestStats: guestStats,
      );
      state = state.copyWith(isLoading: false, clearError: true);
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
      return false;
    }
  }

  int _asInt(dynamic value) => value is num ? value.toInt() : 0;
}

final matchFinalizationControllerProvider =
    StateNotifierProvider<MatchFinalizationController, MatchFinalizationState>(
        (ref) {
  return MatchFinalizationController(ref.watch(matchesRepositoryProvider), ref);
});
