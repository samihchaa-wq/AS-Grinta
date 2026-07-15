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

  /// [grintaScore] est choisi par l'admin. [scorerGoals] attribue des buts à
  /// des joueurs (facultatif) : la somme des buts attribués ne peut pas
  /// dépasser le score, mais peut être inférieure (buts sans buteur).
  Future<bool> finalizeMatch({
    required String matchId,
    required int grintaScore,
    required int opponentScore,
    required Map<String, int> scorerGoals,
    required String? cleanSheetProfileId,
  }) async {
    if (_ref.read(authControllerProvider).profile?.role != AuthRole.admin) {
      state = state.copyWith(
        error: 'Seul un administrateur peut valider le résultat.',
      );
      return false;
    }
    if (grintaScore < 0 || opponentScore < 0) {
      state = state.copyWith(error: 'Score invalide.');
      return false;
    }
    if (opponentScore > 0 && cleanSheetProfileId != null) {
      state = state.copyWith(
        error: 'Un clean sheet est impossible si l’adversaire a marqué.',
      );
      return false;
    }

    final scorers = scorerGoals.entries
        .where((entry) => entry.value > 0)
        .map((entry) => {'season_player_id': entry.key, 'goals': entry.value})
        .toList();
    final attributed = scorers.fold<int>(
      0,
      (sum, s) => sum + (s['goals'] as int),
    );
    if (attributed > grintaScore) {
      state = state.copyWith(
        error:
            'Tu as attribué plus de buts ($attributed) que le score '
            'd’AS Grinta ($grintaScore).',
      );
      return false;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.finalizeMatchPostgame(
        id: matchId,
        grintaScore: grintaScore,
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
    StateNotifierProvider<MatchFinalizationController, MatchFinalizationState>((
      ref,
    ) {
      return MatchFinalizationController(
        ref.watch(matchesRepositoryProvider),
        ref,
      );
    });
