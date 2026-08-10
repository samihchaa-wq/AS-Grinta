import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/matches/data/calendar_matches_local_cache.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchesState {
  const MatchesState({
    this.matches = const [],
    this.seasons = const [],
    this.opponents = const [],
    this.selectedSeasonId,
    this.includesAllSeasons = false,
    this.isLoading = false,
    this.error,
  });

  final List<MatchModel> matches;
  final List<Map<String, dynamic>> seasons;
  final List<Map<String, dynamic>> opponents;
  final String? selectedSeasonId;
  final bool includesAllSeasons;
  final bool isLoading;
  final String? error;

  MatchesState copyWith({
    List<MatchModel>? matches,
    List<Map<String, dynamic>>? seasons,
    List<Map<String, dynamic>>? opponents,
    String? selectedSeasonId,
    bool? includesAllSeasons,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return MatchesState(
      matches: matches ?? this.matches,
      seasons: seasons ?? this.seasons,
      opponents: opponents ?? this.opponents,
      selectedSeasonId: selectedSeasonId ?? this.selectedSeasonId,
      includesAllSeasons: includesAllSeasons ?? this.includesAllSeasons,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class MatchesController extends StateNotifier<MatchesState> {
  MatchesController(this._repository, this._ref) : super(const MatchesState());

  final MatchesRepository _repository;
  final Ref _ref;
  final CalendarMatchesLocalCache _localCache =
      const CalendarMatchesLocalCache();
  Future<void>? _loadInFlight;
  String? _loadKey;
  int _loadGeneration = 0;

  AuthRole? get _role => _ref.read(authControllerProvider).profile?.role;
  bool get _isAdmin => _role?.isAdmin ?? false;
  bool get _canManageMatches => _isAdmin;

  Future<void> load({
    String? seasonId,
    bool allSeasons = false,
    bool forceRefresh = false,
  }) {
    final key = '${seasonId ?? ''}:$allSeasons';
    final existing = _loadInFlight;
    if (!forceRefresh && existing != null) {
      if (_loadKey == key) return existing;
      return existing.whenComplete(
        () => load(seasonId: seasonId, allSeasons: allSeasons),
      );
    }

    // Une écriture peut arriver pendant qu'une ancienne lecture est encore en
    // vol. Le numéro de génération empêche cette ancienne réponse d'écraser le
    // nouvel état une fois l'écriture terminée.
    final generation = ++_loadGeneration;
    final request = _performLoad(
      seasonId: seasonId,
      allSeasons: allSeasons,
      generation: generation,
    );
    _loadInFlight = request;
    _loadKey = key;
    return request.whenComplete(() {
      if (identical(_loadInFlight, request)) {
        _loadInFlight = null;
        _loadKey = null;
      }
    });
  }

  Future<void> _performLoad({
    String? seasonId,
    bool allSeasons = false,
    required int generation,
  }) async {
    if (generation != _loadGeneration) return;
    state = state.copyWith(isLoading: true, clearError: true);
    var hasLocalFallback = false;
    try {
      if (!_ref.read(authControllerProvider).isAuthenticated) {
        if (generation != _loadGeneration) return;
        state = state.copyWith(
          isLoading: false,
          error: 'Authentification requise.',
        );
        return;
      }

      // Sur le calendrier principal, on affiche d'abord le dernier état local
      // connu. La requête Supabase démarre ensuite et remplace ce snapshot dès
      // qu'elle répond. Un cache absent ne change pas le comportement actuel.
      if (allSeasons) {
        final localMatches = await _localCache.read();
        if (generation != _loadGeneration) return;
        if (localMatches.isNotEmpty) {
          hasLocalFallback = true;
          state = state.copyWith(
            matches: localMatches,
            includesAllSeasons: true,
            isLoading: false,
            clearError: true,
          );
        }
      }

      // Le calendrier principal demande toutes les saisons : dans ce cas les
      // trois lectures sont indépendantes et peuvent partir immédiatement.
      final seasonsFuture = _repository.fetchSeasons();
      final opponentsFuture = _repository.fetchOpponents();
      final allMatchesFuture = allSeasons ? _repository.fetchMatches() : null;

      final seasons = await seasonsFuture;
      if (generation != _loadGeneration) return;
      final resolvedSeasonId = seasonId ??
          state.selectedSeasonId ??
          _currentSeasonId(seasons) ??
          (seasons.isNotEmpty ? seasons.first['id']?.toString() : null);

      final matches = allMatchesFuture != null
          ? await allMatchesFuture
          : await _repository.fetchMatches(seasonId: resolvedSeasonId);
      if (generation != _loadGeneration) return;
      final opponents = await opponentsFuture;
      if (generation != _loadGeneration) return;

      state = state.copyWith(
        matches: matches,
        seasons: seasons,
        opponents: opponents,
        selectedSeasonId: resolvedSeasonId,
        includesAllSeasons: allSeasons,
        isLoading: false,
        clearError: true,
      );

      if (allSeasons && generation == _loadGeneration) {
        await _localCache.write(matches);
      }
    } catch (error) {
      if (generation != _loadGeneration) return;
      if (hasLocalFallback) {
        state = state.copyWith(isLoading: false, clearError: true);
      } else {
        state = state.copyWith(isLoading: false, error: humanizeError(error));
      }
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
      await load(
        seasonId: state.selectedSeasonId,
        allSeasons: state.includesAllSeasons,
        forceRefresh: true,
      );
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
    int? squadSizeLimit,
    String? address,
    bool rememberAddressAsDefault = false,
    String matchType = 'championnat',
    String? jerseyNote,
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
    if (squadSizeLimit != null && (squadSizeLimit < 1 || squadSizeLimit > 30)) {
      state = state.copyWith(
        isLoading: false,
        error: 'Le nombre de convoqués doit être compris entre 1 et 30.',
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
        squadSizeLimit: squadSizeLimit,
        address: address,
        rememberAddressAsDefault: rememberAddressAsDefault,
        matchType: matchType,
        jerseyNote: jerseyNote,
      );
      await load(
        seasonId: state.selectedSeasonId,
        allSeasons: state.includesAllSeasons,
        forceRefresh: true,
      );
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
    int? squadSizeLimit,
    String? address,
    bool rememberAddressAsDefault = false,
    String matchType = 'championnat',
    String? jerseyNote,
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
    if (squadSizeLimit != null && (squadSizeLimit < 1 || squadSizeLimit > 30)) {
      state = state.copyWith(
        isLoading: false,
        error: 'Le nombre de convoqués doit être compris entre 1 et 30.',
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
        squadSizeLimit: squadSizeLimit,
        address: address,
        rememberAddressAsDefault: rememberAddressAsDefault,
        matchType: matchType,
        jerseyNote: jerseyNote,
      );
      await load(
        seasonId: state.selectedSeasonId,
        allSeasons: state.includesAllSeasons,
        forceRefresh: true,
      );
      _ref.invalidate(matchInfoProvider(id));
    } catch (error) {
      state = state.copyWith(isLoading: false, error: humanizeError(error));
    }
  }

  /// Crée un « match entre nous » : pas d'adversaire, pas de cotes, pas de
  /// limite convocable.
  Future<void> createInternalMatch({
    required String seasonId,
    required DateTime kickoffAt,
    String? address,
  }) async {
    if (!_canManageMatches) {
      state = state.copyWith(isLoading: false, error: 'Droits insuffisants.');
      return;
    }
    if (seasonId.isEmpty) {
      state = state.copyWith(isLoading: false, error: 'Saison obligatoire.');
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.createInternalMatch(
        seasonId: seasonId,
        kickoffAt: kickoffAt,
        address: address,
      );
      await load(
        seasonId: state.selectedSeasonId,
        allSeasons: state.includesAllSeasons,
        forceRefresh: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: humanizeError(error));
    }
  }

  Future<void> updateInternalMatch({
    required String id,
    required String seasonId,
    required DateTime kickoffAt,
    String? address,
    bool rememberAddressAsDefault = false,
  }) async {
    if (!_canManageMatches) {
      state = state.copyWith(isLoading: false, error: 'Droits insuffisants.');
      return;
    }
    if (id.isEmpty || seasonId.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        error: 'Match et saison obligatoires.',
      );
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.updateInternalMatch(
        id: id,
        seasonId: seasonId,
        kickoffAt: kickoffAt,
      );
      await _repository.setMatchAddress(
        matchId: id,
        address: address,
        rememberAsDefault: rememberAddressAsDefault,
      );
      await load(
        seasonId: state.selectedSeasonId,
        allSeasons: state.includesAllSeasons,
        forceRefresh: true,
      );
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
      await load(
        seasonId: state.selectedSeasonId,
        allSeasons: state.includesAllSeasons,
        forceRefresh: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: humanizeError(error));
    }
  }

  Future<void> cancelMatch(String id) async {
    if (!_canManageMatches) {
      state = state.copyWith(error: 'Seul le staff peut annuler un match.');
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.cancelMatch(id);
      await load(
        seasonId: state.selectedSeasonId,
        allSeasons: state.includesAllSeasons,
        forceRefresh: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: humanizeError(error));
    }
  }

  /// Clôture un match entre nous une fois joué : il n'a ni pronostics, ni
  /// feuille de match à valider, donc pas d'autre façon de sortir de
  /// « à venir » que cette bascule directe en archivé.
  Future<void> finishInternalMatch(String id) async {
    if (!_canManageMatches) {
      state = state.copyWith(error: 'Seul le staff peut terminer un match.');
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.updateMatchStatus(id: id, status: 'archive');
      await load(
        seasonId: state.selectedSeasonId,
        allSeasons: state.includesAllSeasons,
        forceRefresh: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: humanizeError(error));
    }
  }
}

final matchesControllerProvider =
    StateNotifierProvider<MatchesController, MatchesState>((ref) {
  return MatchesController(ref.watch(matchesRepositoryProvider), ref);
});
