import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PredictionsState {
  const PredictionsState({
    this.items = const [],
    this.isLoading = false,
    this.savingMatchId,
    this.error,
  });

  final List<MatchPredictionItem> items;
  final bool isLoading;
  final String? savingMatchId;
  final String? error;

  PredictionsState copyWith({
    List<MatchPredictionItem>? items,
    bool? isLoading,
    String? savingMatchId,
    bool clearSaving = false,
    String? error,
    bool clearError = false,
  }) {
    return PredictionsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      savingMatchId: clearSaving ? null : (savingMatchId ?? this.savingMatchId),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class PredictionsController extends StateNotifier<PredictionsState> {
  PredictionsController(this._repository) : super(const PredictionsState());

  final PredictionsRepository _repository;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, items: const [], clearError: true);
    try {
      final items = await _repository.fetchMyMatchPredictions();
      state = state.copyWith(items: items, isLoading: false, clearError: true);
    } catch (error) {
      state = state.copyWith(
        items: const [],
        isLoading: false,
        error: error.toString(),
      );
    }
  }

  void changeScore({
    required String matchId,
    required bool grinta,
    required int delta,
  }) {
    final items = state.items.map((item) {
      if (item.matchId != matchId || !item.canEdit) return item;
      final nextGrinta = grinta
          ? (item.scoreGrinta + delta).clamp(0, 99)
          : item.scoreGrinta;
      final nextOpponent = grinta
          ? item.scoreOpponent
          : (item.scoreOpponent + delta).clamp(0, 99);
      return item.updated(
        scoreGrinta: nextGrinta,
        scoreOpponent: nextOpponent,
      );
    }).toList();
    state = state.copyWith(items: items, clearError: true);
  }

  void toggleX2(String matchId) {
    final items = state.items.map((item) {
      if (item.matchId != matchId || !item.canEdit) return item;
      if (!item.useX2 && item.x2Available <= 0) return item;
      return item.updated(useX2: !item.useX2);
    }).toList();
    state = state.copyWith(items: items, clearError: true);
  }

  Future<void> save(String matchId) async {
    final item = state.items
        .where((value) => value.matchId == matchId)
        .firstOrNull;
    if (item == null || !item.canEdit) return;

    state = state.copyWith(savingMatchId: matchId, clearError: true);
    try {
      await _repository.savePrediction(
        matchId: matchId,
        scoreGrinta: item.scoreGrinta,
        scoreOpponent: item.scoreOpponent,
        useX2: item.useX2,
      );
      final items = state.items
          .map(
            (value) => value.matchId == matchId
                ? value.updated(isFilled: true)
                : value,
          )
          .toList();
      state = state.copyWith(items: items, clearSaving: true, clearError: true);
    } catch (error) {
      state = state.copyWith(clearSaving: true, error: error.toString());
    }
  }
}

final predictionsControllerProvider =
    StateNotifierProvider<PredictionsController, PredictionsState>((ref) {
  return PredictionsController(ref.watch(predictionsRepositoryProvider));
});

extension MatchPredictionItemUpdate on MatchPredictionItem {
  MatchPredictionItem updated({
    int? scoreGrinta,
    int? scoreOpponent,
    bool? isFilled,
    bool? useX2,
    int? x2Available,
  }) {
    return MatchPredictionItem(
      matchId: matchId,
      opponentName: opponentName,
      kickoffAt: kickoffAt,
      status: status,
      scoreGrinta: scoreGrinta ?? this.scoreGrinta,
      scoreOpponent: scoreOpponent ?? this.scoreOpponent,
      isFilled: isFilled ?? this.isFilled,
      useX2: useX2 ?? this.useX2,
      x2Available: x2Available ?? this.x2Available,
      oddsWin: oddsWin,
      oddsDraw: oddsDraw,
      oddsLoss: oddsLoss,
      actualScoreGrinta: actualScoreGrinta,
      actualScoreOpponent: actualScoreOpponent,
      predictionsClosedAt: predictionsClosedAt,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
