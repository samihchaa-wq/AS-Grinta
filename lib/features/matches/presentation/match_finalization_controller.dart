import 'package:as_grinta/core/utils/app_errors.dart';
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

  /// [scorerProfileIds] contient un identifiant par but marqué (un buteur
  /// qui a marqué deux fois apparaît deux fois). Le score d'AS Grinta en
  /// découle automatiquement.
  Future<bool> finalizeMatch({
    required String matchId,
    required int opponentScore,
    required List<String> scorerProfileIds,
    required String? cleanSheetProfileId,
  }) async {
    if (_ref.read(authControllerProvider).profile?.role != AuthRole.admin) {
      state = state.copyWith(
        error: 'Seul un administrateur peut valider le résultat.',
      );
      return false;
    }
    if (opponentScore < 0) {
      state = state.copyWith(error: 'Score adverse invalide.');
      return false;
    }
    if (opponentScore > 0 && cleanSheetProfileId != null) {
      state = state.copyWith(
        error: 'Un clean sheet est impossible si l’adversaire a marqué.',
      );
      return false;
    }

    // Agrège les buts par joueur.
    final goalsByPlayer = <String, int>{};
    for (final id in scorerProfileIds) {
      goalsByPlayer.update(id, (value) => value + 1, ifAbsent: () => 1);
    }
    final scorers = goalsByPlayer.entries
        .map((entry) => {'profile_id': entry.key, 'goals': entry.value})
        .toList();

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.finalizeMatchPostgame(
        id: matchId,
        opponentScore: opponentScore,
        scorers: scorers,
        cleanSheetProfileId: cleanSheetProfileId,
      );
      state = state.copyWith(isLoading: false, clearError: true);
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, error: humanizeError(error));
      return false;
    }
  }
}

final matchFinalizationControllerProvider =
    StateNotifierProvider<MatchFinalizationController, MatchFinalizationState>(
        (ref) {
  return MatchFinalizationController(ref.watch(matchesRepositoryProvider), ref);
});
