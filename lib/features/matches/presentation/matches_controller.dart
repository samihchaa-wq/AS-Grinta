import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchesState {
  const MatchesState({
    this.matches = const [],
    this.seasons = const [],
    this.opponents = const [],
    this.selectedSeasonId,
    this.isLoading = false,
    this.error,
  });

  final List<MatchModel> matches;
  final List<Map<String, dynamic>> seasons;
  final List<Map<String, dynamic>> opponents;
  final String? selectedSeasonId;
  final bool isLoading;
  final String? error;

  MatchesState copyWith({
    List<MatchModel>? matches,
    List<Map<String, dynamic>>? seasons,
    List<Map<String, dynamic>>? opponents,
    String? selectedSeasonId,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return MatchesState(
      matches: matches ?? this.matches,
      seasons: seasons ?? this.seasons,
      opponents: opponents ?? this.opponents,
      selectedSeasonId: selectedSeasonId ?? this.selectedSeasonId,
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
  bool get _canManageMatches => _isAdmin;

  Future<void> load({String? seasonId}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      if (!_ref.read(authControllerProvider).isAuthenticated) {
        state = state.copyWith(
          isLoading: false,
          error: 'Authentification requise.',
        );
        return;
      }

      final seasons = await _repository.fetchSeasons();
      final resolvedSeasonId = seasonId ??
          state.selectedSeasonId ??
          _currentSeasonId(seasons) ??
          (seasons.isNotEmpty ? seasons.first['id']?.toString() : null);
      final results = await Future.wait([
        _repository.fetchMatches(seasonId: resolvedSeasonId),
        _repository.fetchOpponents(),
      ]);
      state = state.copyWith(
        matches: results[0] as List<MatchModel>,
        seasons: seasons,
        opponents: results[1] as List<Map<String, dynamic>>,
        selectedSeasonId: resolvedSeasonId,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: humanizeError(error));
    }
  }

  String? _currentSeasonId(List<Map<String, dynamic>> seasons) {
    for (final season in seasons) {
      if (season['status']?.toString() == 'open') {
        return season['id']?.toString();
      }
    }
    return null;
  }

  Future<String?> createOpponent(String name) async {
    if (!_canManageMatches) {
      state = state.copyWith(error: 'Droits insuffisants.');
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
      state = state.copyWith(error: humanizeError(error));
      return null;
    }
  }

  Future<void> createMatch({
    required String seasonId,
    required String opponentId,
    required DateTime kickoffAt,
    required bool isHome,
    required double oddsWin,
    required double oddsDraw,
    required double oddsLoss,
  }) async {
    if (!_canManageMatches) {
      state = state.copyWith(isLoading: false, error: 'Droits insuffisants.');
      return;
    }
    if (seasonId.isEmpty || opponentId.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        error: 'Saison et adversaire sont obligatoires.',
      );
      return;
    }
    if (!_validOdds(oddsWin, oddsDraw, oddsLoss)) {
      state = state.copyWith(
        isLoading: false,
        error: 'Chaque cote doit être comprise entre 1,01 et 100.',
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
        oddsWin: oddsWin,
        oddsDraw: oddsDraw,
        oddsLoss: oddsLoss,
      );
      await load(seasonId: state.selectedSeasonId);
      _ref.invalidate(homeDashboardProvider);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: humanizeError(error));
    }
  }

  Future<void> updateMatch({
    required String id,
    required String seasonId,
    required String opponentId,
    required DateTime kickoffAt,
    required bool isHome,
    required String status,
    required double oddsWin,
    required double oddsDraw,
    required double oddsLoss,
  }) async {
    if (!_canManageMatches) {
      state = state.copyWith(isLoading: false, error: 'Droits insuffisants.');
      return;
    }
    if (id.isEmpty || seasonId.isEmpty || opponentId.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        error: 'Match, saison et adversaire sont obligatoires.',
      );
      return;
    }
    if (!_validOdds(oddsWin, oddsDraw, oddsLoss)) {
      state = state.copyWith(
        isLoading: false,
        error: 'Chaque cote doit être comprise entre 1,01 et 100.',
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
        status: status,
        oddsWin: oddsWin,
        oddsDraw: oddsDraw,
        oddsLoss: oddsLoss,
      );
      await load(seasonId: state.selectedSeasonId);
      _ref.invalidate(homeDashboardProvider);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: humanizeError(error));
    }
  }

  bool _validOdds(double win, double draw, double loss) {
    return [win, draw, loss].every((value) => value >= 1.01 && value <= 100);
  }

  Future<void> deleteMatch(String id) async {
    if (!_canManageMatches) {
      state = state.copyWith(error: 'Seul le staff peut supprimer un match.');
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.deleteMatch(id);
      await load(seasonId: state.selectedSeasonId);
      _ref.invalidate(homeDashboardProvider);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: humanizeError(error));
    }
  }
}

final matchesControllerProvider =
    StateNotifierProvider<MatchesController, MatchesState>((ref) {
  return MatchesController(ref.watch(matchesRepositoryProvider), ref);
});
