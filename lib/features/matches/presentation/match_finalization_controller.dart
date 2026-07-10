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
}

final matchFinalizationControllerProvider =
    StateNotifierProvider<MatchFinalizationController, MatchFinalizationState>(
        (ref) {
  return MatchFinalizationController(ref.watch(matchesRepositoryProvider), ref);
});
