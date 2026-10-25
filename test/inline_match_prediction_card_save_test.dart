import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/inline_match_prediction_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _matchId = 'match-1';
const _outcomeUnknownMessage =
    'Connexion interrompue : ton pronostic a peut-être été enregistré. '
    'Actualise la page avant de réessayer.';

/// Une coupure pendant l'enregistrement laisse l'issue inconnue : la carte doit
/// le dire, et non annoncer un échec qui pousserait à ressaisir un pronostic
/// peut-être déjà enregistré.
void main() {
  testWidgets('une coupure pendant l’enregistrement le dit sans parler d’échec',
      (tester) async {
    final repository = _FakePredictionsRepository(
      saveError: const PredictionWriteOutcomeUnknown(),
    );
    await _pump(tester, repository);

    await _tapSave(tester);

    expect(repository.saveCalls, 1);
    expect(find.text(_outcomeUnknownMessage), findsOneWidget);
    await _dismissSnackBar(tester);
  });

  testWidgets('un refus du serveur reste annoncé comme un échec', (
    tester,
  ) async {
    final repository = _FakePredictionsRepository(
      saveError: StateError('Le pronostic n’a pas pu être enregistré.'),
    );
    await _pump(tester, repository);

    await _tapSave(tester);

    expect(
      find.text('Le pronostic n’a pas pu être enregistré.'),
      findsOneWidget,
    );
    expect(find.text(_outcomeUnknownMessage), findsNothing);
    await _dismissSnackBar(tester);
  });
}

Future<void> _pump(
  WidgetTester tester,
  _FakePredictionsRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        predictionsRepositoryProvider.overrideWithValue(repository),
        matchDetailsProvider(_matchId).overrideWith(
          (ref) => Future<MatchDetailsData>.error(StateError('indisponible')),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InlineMatchPredictionCard(matchId: _matchId),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester) async {
  final save = find.text('Enregistrer');
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

/// Laisse le message se refermer pour ne pas finir le test sur une minuterie
/// encore active.
Future<void> _dismissSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

class _FakePredictionsRepository implements PredictionsRepository {
  _FakePredictionsRepository({required this.saveError});

  final Object saveError;
  int saveCalls = 0;

  @override
  Future<MatchPredictionItem?> fetchMatchPrediction(String matchId) async {
    return MatchPredictionItem(
      matchId: matchId,
      opponentName: 'Olympique Test',
      kickoffAt: DateTime.now().add(const Duration(days: 3)),
      status: 'a_venir',
      scoreGrinta: 2,
      scoreOpponent: 1,
      isFilled: false,
      oddsWin: 2,
      oddsDraw: 3,
      oddsLoss: 4,
      actualScoreGrinta: null,
      actualScoreOpponent: null,
    );
  }

  @override
  Future<void> savePrediction({
    required String matchId,
    required int scoreGrinta,
    required int scoreOpponent,
  }) async {
    saveCalls += 1;
    throw saveError;
  }
}
