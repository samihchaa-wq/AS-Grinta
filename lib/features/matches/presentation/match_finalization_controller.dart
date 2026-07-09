import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/matches/domain/match_finalization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchFinalizationState {
  const MatchFinalizationState({
    this.isLoading = false,
    this.error,
    this.validation,
  });

  final bool isLoading;
  final String? error;
  final MatchFinalizationValidation? validation;

  MatchFinalizationState copyWith({
    bool? isLoading,
    String? error,
    MatchFinalizationValidation? validation,
    bool clearError = false,
  }) {
    return MatchFinalizationState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      validation: validation ?? this.validation,
    );
  }
}

class MatchFinalizationController
    extends StateNotifier<MatchFinalizationState> {
  MatchFinalizationController(this._repository, this._ref)
      : super(const MatchFinalizationState());

  final MatchesRepository _repository;
  final Ref _ref;

  Future<void> finalizeMatch({
    required String matchId,
    required int grintaScore,
    required int opponentScore,
    required List<MatchGoal> goals,
    required List<MatchSubstitution> substitutions,
    required String? manOfTheMatchId,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final authState = _ref.read(authControllerProvider);
    if (authState.profile?.role != AuthRole.admin) {
      state = state.copyWith(
        isLoading: false,
        error: 'Seul un admin peut finaliser un match.',
      );
      return;
    }

    final validation = MatchFinalizationRules.validate(
      grintaScore: grintaScore,
      opponentScore: opponentScore,
      goals: goals,
      substitutions: substitutions,
    );
    state = state.copyWith(validation: validation);

    if (!validation.isValid) {
      state = state.copyWith(
        isLoading: false,
        error: validation.issues.join('\n'),
      );
      return;
    }

    try {
      await _repository.finalizeMatch(
        id: matchId,
        grintaScore: grintaScore,
        opponentScore: opponentScore,
        status: 'termine',
        manOfTheMatchId: manOfTheMatchId,
      );
      state = state.copyWith(isLoading: false, clearError: true);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: error.toString(),
      );
    }
  }
}

final matchFinalizationControllerProvider =
    StateNotifierProvider<MatchFinalizationController, MatchFinalizationState>(
        (ref) {
  final repository = ref.watch(matchesRepositoryProvider);
  return MatchFinalizationController(repository, ref);
});
