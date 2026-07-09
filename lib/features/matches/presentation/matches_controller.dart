import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchesState {
  const MatchesState({
    this.matches = const [],
    this.seasons = const [],
    this.opponents = const [],
    this.isLoading = false,
    this.error,
  });

  final List<MatchModel> matches;
  final List<Map<String, dynamic>> seasons;
  final List<Map<String, dynamic>> opponents;
  final bool isLoading;
  final String? error;

  MatchesState copyWith({
    List<MatchModel>? matches,
    List<Map<String, dynamic>>? seasons,
    List<Map<String, dynamic>>? opponents,
    bool? isLoading,
    String? error,
  }) {
    return MatchesState(
      matches: matches ?? this.matches,
      seasons: seasons ?? this.seasons,
      opponents: opponents ?? this.opponents,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class MatchesController extends StateNotifier<MatchesState> {
  MatchesController(this._repository, this._ref) : super(const MatchesState());

  final MatchesRepository _repository;
  final Ref _ref;

  Future<void> load({String? seasonId}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final authState = _ref.read(authControllerProvider);
      if (!authState.isAuthenticated) {
        state = state.copyWith(isLoading: false);
        return;
      }
      final matches = await _repository.fetchMatches(seasonId: seasonId);
      final seasons = await _repository.fetchSeasons();
      final opponents = await _repository.fetchOpponents();
      state = state.copyWith(
        matches: matches,
        seasons: seasons,
        opponents: opponents,
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> createMatch({
    required String seasonId,
    required String opponentId,
    required DateTime kickoffAt,
    required bool isHome,
    required int plannedDurationMinutes,
    required String status,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.createMatch(
        seasonId: seasonId,
        opponentId: opponentId,
        kickoffAt: kickoffAt,
        isHome: isHome,
        plannedDurationMinutes: plannedDurationMinutes,
        status: status,
      );
      await load();
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> updateMatch({
    required String id,
    required String seasonId,
    required String opponentId,
    required DateTime kickoffAt,
    required bool isHome,
    required int plannedDurationMinutes,
    required String status,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.updateMatch(
        id: id,
        seasonId: seasonId,
        opponentId: opponentId,
        kickoffAt: kickoffAt,
        isHome: isHome,
        plannedDurationMinutes: plannedDurationMinutes,
        status: status,
      );
      await load();
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> deleteMatch(String id) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.deleteMatch(id);
      await load();
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }
}

final matchesControllerProvider = StateNotifierProvider<MatchesController, MatchesState>((ref) {
  final repository = ref.watch(matchesRepositoryProvider);
  return MatchesController(repository, ref);
});
