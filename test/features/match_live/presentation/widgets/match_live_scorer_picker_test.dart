import 'package:as_grinta/features/match_live/presentation/widgets/match_live_scorer_picker_dialog.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Régression : la liste des joueurs remplit l'écran. Sans bouton visible, le
  // coach ne pouvait plus refermer la feuille sans désigner quelqu'un.
  testWidgets('la feuille du buteur peut être refermée sans rien choisir', (
    tester,
  ) async {
    String? result = 'inchangé';
    await _pumpPicker(
      tester,
      onOpen: (context) async {
        result = await pickMatchLiveScorer(
          context,
          candidates: _candidates,
          extraChoiceLabel: 'CSC adverse',
        );
      },
    );

    expect(find.text('Annuler'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('le buteur déjà désigné peut être effacé', (tester) async {
    String? result = 'inchangé';
    await _pumpPicker(
      tester,
      onOpen: (context) async {
        result = await pickMatchLiveScorer(
          context,
          candidates: _candidates,
          extraChoiceLabel: 'CSC adverse',
          clearChoiceLabel: 'Effacer · buteur à désigner plus tard',
        );
      },
    );

    await tester.tap(find.text('Effacer · buteur à désigner plus tard'));
    await tester.pumpAndSettle();

    expect(result, kMatchLiveClearChoiceId);
  });

  testWidgets('sans attribution existante, aucun choix « effacer »', (
    tester,
  ) async {
    await _pumpPicker(
      tester,
      onOpen: (context) async {
        await pickMatchLiveScorer(
          context,
          candidates: _candidates,
          extraChoiceLabel: 'CSC adverse',
        );
      },
    );

    expect(find.textContaining('Effacer'), findsNothing);
    expect(find.text('CSC adverse'), findsOneWidget);
    expect(find.text('Amine'), findsOneWidget);
  });
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  required Future<void> Function(BuildContext context) onOpen,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onOpen(context),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
}

final List<MatchCompositionEntry> _candidates = [
  _entry('p1', 'Amine'),
  _entry('p2', 'François'),
];

MatchCompositionEntry _entry(String id, String name) => MatchCompositionEntry(
      participantId: id,
      seasonPlayerId: 'sp-$id',
      displayName: name,
      isGoalkeeper: false,
      zone: MatchCompositionZone.field,
      sortOrder: 0,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'starter',
    );
