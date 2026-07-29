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

  /// Enregistre le résultat, les buteurs, le clean sheet, la feuille de match
  /// et l'homme du match dans une seule transaction côté Supabase.
  Future<bool> finalizeMatch({
    required String matchId,
    required int grintaScore,
    required int opponentScore,
    required Map<String, int> scorerGoals,
    required String? cleanSheetProfileId,
    required Set<String> presentPlayerIds,
    required String? manOfMatchPlayerId,
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
    if (presentPlayerIds.isEmpty) {
      state = state.copyWith(error: 'Sélectionne au moins un joueur présent.');
      return false;
    }
    if (opponentScore > 0 && cleanSheetProfileId != null) {
      state = state.copyWith(
        error: 'Un clean sheet est impossible si l’adversaire a marqué.',
      );
      return false;
    }

    final absentScorers = scorerGoals.keys
        .where((playerId) => !presentPlayerIds.contains(playerId))
        .toList();
    if (absentScorers.isNotEmpty) {
      state = state.copyWith(
        error: 'Tous les buteurs doivent être cochés comme présents.',
      );
      return false;
    }
    if (cleanSheetProfileId != null &&
        !presentPlayerIds.contains(cleanSheetProfileId)) {
      state = state.copyWith(
        error: 'Le gardien crédité du clean sheet doit être présent.',
      );
      return false;
    }
    if (manOfMatchPlayerId != null &&
        !presentPlayerIds.contains(manOfMatchPlayerId)) {
      state = state.copyWith(
        error: 'L’homme du match doit faire partie des joueurs présents.',
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
        presentPlayerIds: presentPlayerIds.toList(growable: false),
        manOfMatchPlayerId: manOfMatchPlayerId,
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
