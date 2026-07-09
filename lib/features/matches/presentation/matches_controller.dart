import 'package:as_grinta/features/auth/domain/auth_profile.dart';
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
    bool clearError = false,
  }) {
    return MatchesState(
      matches: matches ?? this.matches,
      seasons: seasons ?? this.seasons,
      opponents: opponents ?? this.opponents,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class MatchesController extends StateNotifier<MatchesState> {
  MatchesController(this._repository, this._ref) : super(const MatchesState());

  final MatchesRepository _repository;
  final Ref _ref;

  AuthRole? get _role => _ref.read(authControllerProvider).profile?.role;
  bool get _isAdmin => _role == AuthRole.admin;
  bool get _isModerator => _role == AuthRole.moderateur;
  bool get _canManageMatches => _isAdmin || _isModerator;

  Future<void> load({String? seasonId}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final authState = _ref.read(authControllerProvider);
      if (!authState.isAuthenticated) {
        state = state.copyWith(
          isLoading: false,
          error: 'Authentification requise.',
        );
        return;
      }

      final results = await Future.wait([
        _repository.fetchMatches(seasonId: seasonId),
        _repository.fetchSeasons(),
        _repository.fetchOpponents(),
      ]);

      state = state.copyWith(
        matches: results[0] as List<MatchModel>,
        seasons: results[1] as List<Map<String, dynamic>>,
        opponents: results[2] as List<Map<String, dynamic>>,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<String?> createOpponent(String name) async {
    if (!_canManageMatches) {
      state = state.copyWith(
        error: 'Seul un administrateur ou un coach peut créer un adversaire.',
      );
      return null;
    }
    final trimmed = name.trim();
    if (trimmed.length < 2) {
      state = state.copyWith(error: 'Nom d’adversaire invalide.');
      return null;
    }

    try {
      final id = await _repository.createOpponent(trimmed);
      await load();
      return id;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      return null;
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
    if (!_canManageMatches) {
      state = state.copyWith(
        isLoading: false,
        error: 'Seul un administrateur ou un coach peut créer un match.',
      );
      return;
    }
    if (seasonId.isEmpty || opponentId.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        error: 'La saison et l’adversaire sont obligatoires.',
      );
      return;
    }
    if (plannedDurationMinutes <= 0) {
      state = state.copyWith(
        isLoading: false,
        error: 'La durée du match doit être supérieure à zéro.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
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
    if (!_canManageMatches) {
      state = state.copyWith(
        isLoading: false,
        error: 'Seul un administrateur ou un coach peut modifier un match.',
      );
      return;
    }
    if (id.isEmpty || seasonId.isEmpty || opponentId.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        error: 'Le match, la saison et l’adversaire sont obligatoires.',
      );
      return;
    }
    if (plannedDurationMinutes <= 0) {
      state = state.copyWith(
        isLoading: false,
        error: 'La durée du match doit être supérieure à zéro.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
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

  Future<void> archiveMatch(String id) async {
    if (!_isAdmin) {
      state = state.copyWith(
        error: 'Seul un administrateur peut archiver un match.',
      );
      return;
    }
    if (id.isEmpty) {
      state = state.copyWith(error: 'Identifiant de match invalide.');
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.updateMatchStatus(id: id, status: 'archive');
      await load();
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> deleteMatch(String id) async {
    if (!_isModerator) {
      state = state.copyWith(
        isLoading: false,
        error: 'Seul un modérateur peut supprimer définitivement un match.',
      );
      return;
    }
    if (id.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        error: 'Identifiant de match invalide.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.deleteMatch(id);
      await load();
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }
}

final matchesControllerProvider =
    StateNotifierProvider<MatchesController, MatchesState>((ref) {
  final repository = ref.watch(matchesRepositoryProvider);
  return MatchesController(repository, ref);
});
