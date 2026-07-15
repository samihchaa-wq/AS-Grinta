import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatchPredictionItem timing', () {
    final kickoff = DateTime.utc(2026, 7, 14, 20);

    test('closes exactly five minutes before kickoff', () {
      final item = _item(kickoffAt: kickoff);

      expect(item.closesAt, DateTime.utc(2026, 7, 14, 19, 55));
      expect(
        item.isClosedAt(DateTime.utc(2026, 7, 14, 19, 54, 59, 999)),
        isFalse,
      );
      expect(item.isClosedAt(item.closesAt), isTrue);
    });

    test('respects an explicit earlier closure timestamp', () {
      final explicitClosure = DateTime.utc(2026, 7, 14, 19, 30);
      final item = _item(
        kickoffAt: kickoff,
        predictionsClosedAt: explicitClosure,
      );

      expect(
        item.isClosedAt(explicitClosure.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(item.isClosedAt(explicitClosure), isTrue);
    });

    test('non-upcoming matches are always closed', () {
      final item = _item(kickoffAt: kickoff, status: 'termine');

      expect(item.isClosedAt(DateTime.utc(2026, 7, 1)), isTrue);
    });
  });

  group('PredictionsController', () {
    test('loads prediction items', () async {
      final item = _editableItem();
      final repository = _FakePredictionsRepository(fetchResult: [item]);
      final controller = PredictionsController(repository);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.items, [item]);
      expect(controller.state.error, isNull);
    });

    test('clears items and exposes an error when loading fails', () async {
      final repository = _FakePredictionsRepository(
        fetchError: StateError('load failed'),
      );
      final controller = PredictionsController(repository);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.items, isEmpty);
      expect(
        controller.state.error,
        'Une erreur est survenue. Réessaie dans un instant.',
      );
    });

    test('changes scores and clamps them between zero and 99', () async {
      final repository = _FakePredictionsRepository(
        fetchResult: [_editableItem(scoreGrinta: 98, scoreOpponent: 1)],
      );
      final controller = PredictionsController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      controller.changeScore(matchId: 'match', grinta: true, delta: 5);
      controller.changeScore(matchId: 'match', grinta: false, delta: -5);

      final item = controller.state.items.single;
      expect(item.scoreGrinta, 99);
      expect(item.scoreOpponent, 0);
    });

    test('does not edit a closed match', () async {
      final closed = _item(
        kickoffAt: DateTime.now().subtract(const Duration(hours: 1)),
        scoreGrinta: 2,
      );
      final repository = _FakePredictionsRepository(fetchResult: [closed]);
      final controller = PredictionsController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      controller.changeScore(matchId: 'match', grinta: true, delta: 1);
      controller.toggleX2('match');

      final item = controller.state.items.single;
      expect(item.scoreGrinta, 2);
      expect(item.useX2, isFalse);
    });

    test('enables x2 only with an available token', () async {
      final repository = _FakePredictionsRepository(
        fetchResult: [_editableItem(x2Available: 1)],
      );
      final controller = PredictionsController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      controller.toggleX2('match');

      expect(controller.state.items.single.useX2, isTrue);
    });

    test('cannot enable x2 without a token', () async {
      final repository = _FakePredictionsRepository(
        fetchResult: [_editableItem(x2Available: 0)],
      );
      final controller = PredictionsController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      controller.toggleX2('match');

      expect(controller.state.items.single.useX2, isFalse);
    });

    test('can disable an already selected x2 even when none remain', () async {
      final repository = _FakePredictionsRepository(
        fetchResult: [_editableItem(useX2: true, x2Available: 0)],
      );
      final controller = PredictionsController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      controller.toggleX2('match');

      expect(controller.state.items.single.useX2, isFalse);
    });

    test('saves the current values and marks the prediction filled', () async {
      final repository = _FakePredictionsRepository(
        fetchResult: [
          _editableItem(
            scoreGrinta: 3,
            scoreOpponent: 1,
            useX2: true,
            x2Available: 1,
          ),
        ],
      );
      final controller = PredictionsController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      await controller.save('match');

      expect(repository.savedMatchId, 'match');
      expect(repository.savedScoreGrinta, 3);
      expect(repository.savedScoreOpponent, 1);
      expect(repository.savedUseX2, isTrue);
      expect(controller.state.items.single.isFilled, isTrue);
      expect(controller.state.savingMatchId, isNull);
      expect(controller.state.error, isNull);
    });

    test('keeps the prediction editable and exposes save errors', () async {
      final repository = _FakePredictionsRepository(
        fetchResult: [_editableItem()],
        saveError: StateError('save failed'),
      );
      final controller = PredictionsController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      await controller.save('match');

      expect(controller.state.items.single.isFilled, isFalse);
      expect(controller.state.savingMatchId, isNull);
      expect(
        controller.state.error,
        'Une erreur est survenue. Réessaie dans un instant.',
      );
    });

    test('does not call the repository for a closed prediction', () async {
      final repository = _FakePredictionsRepository(
        fetchResult: [
          _item(kickoffAt: DateTime.now().subtract(const Duration(hours: 1))),
        ],
      );
      final controller = PredictionsController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      await controller.save('match');

      expect(repository.saveCalls, 0);
    });
  });
}

MatchPredictionItem _editableItem({
  int scoreGrinta = 0,
  int scoreOpponent = 0,
  bool useX2 = false,
  int x2Available = 0,
}) {
  return _item(
    kickoffAt: DateTime.now().add(const Duration(days: 1)),
    scoreGrinta: scoreGrinta,
    scoreOpponent: scoreOpponent,
    useX2: useX2,
    x2Available: x2Available,
  );
}

MatchPredictionItem _item({
  required DateTime kickoffAt,
  String status = 'a_venir',
  int scoreGrinta = 0,
  int scoreOpponent = 0,
  bool isFilled = false,
  bool useX2 = false,
  int x2Available = 0,
  DateTime? predictionsClosedAt,
}) {
  return MatchPredictionItem(
    matchId: 'match',
    opponentName: 'Opponent',
    kickoffAt: kickoffAt,
    status: status,
    scoreGrinta: scoreGrinta,
    scoreOpponent: scoreOpponent,
    isFilled: isFilled,
    useX2: useX2,
    x2Available: x2Available,
    oddsWin: 2,
    oddsDraw: 3,
    oddsLoss: 4,
    actualScoreGrinta: null,
    actualScoreOpponent: null,
    predictionsClosedAt: predictionsClosedAt,
  );
}

class _FakePredictionsRepository implements PredictionsRepository {
  _FakePredictionsRepository({
    this.fetchResult = const [],
    this.fetchError,
    this.saveError,
  });

  final List<MatchPredictionItem> fetchResult;
  final Object? fetchError;
  final Object? saveError;

  int saveCalls = 0;
  String? savedMatchId;
  int? savedScoreGrinta;
  int? savedScoreOpponent;
  bool? savedUseX2;

  @override
  Future<List<MatchPredictionItem>> fetchMyMatchPredictions() async {
    if (fetchError != null) throw fetchError!;
    return fetchResult;
  }

  @override
  Future<MatchPredictionItem?> fetchMatchPrediction(String matchId) async {
    return fetchResult.where((item) => item.matchId == matchId).firstOrNull;
  }

  @override
  Future<void> savePrediction({
    required String matchId,
    required int scoreGrinta,
    required int scoreOpponent,
    required bool useX2,
  }) async {
    saveCalls += 1;
    savedMatchId = matchId;
    savedScoreGrinta = scoreGrinta;
    savedScoreOpponent = scoreOpponent;
    savedUseX2 = useX2;
    if (saveError != null) throw saveError!;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => this.isEmpty ? null : first;
}
