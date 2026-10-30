import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _names = [
  'Samih',
  'Alyoun',
  'Hakim',
  'Steph',
  'Amine',
  'Romain',
  'Lulu',
  'Alban',
  'Nicolas',
  'Simon',
  'Allan',
];

MatchCompositionEntry _entry(
  String name,
  MatchCompositionZone zone, {
  Offset? position,
  bool goalkeeper = false,
}) =>
    MatchCompositionEntry(
      participantId: name,
      seasonPlayerId: name,
      displayName: name,
      isGoalkeeper: goalkeeper,
      zone: zone,
      sortOrder: 0,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'selected',
      x: position?.dx,
      y: position?.dy,
    );

CompositionPresentationData _data({bool coach = true}) {
  final slots = formationForCode('4-2-1-3').slots;
  return CompositionPresentationData(
    homeName: 'TOAC Foot Loisir 2',
    awayName: 'AS Grinta',
    grintaIsHome: false,
    kickoffAt: DateTime(2026, 10, 27, 21),
    typeLabel: 'Amical',
    address: 'Complexe sportif du TOAC - 20 Chemin de Garric - Toulouse',
    formationCode: '4-2-1-3',
    field: [
      for (final (index, slot) in slots.indexed)
        _entry(
          _names[index],
          MatchCompositionZone.field,
          position: slot.position,
          goalkeeper: slot.label == 'GB',
        ),
    ],
    bench: [
      _entry('Flo', MatchCompositionZone.bench),
      _entry('Pipo', MatchCompositionZone.bench),
    ],
    coach: coach
        ? const CompositionPresentationCoach(id: 'coach', name: 'Philippe')
        : null,
  );
}

Widget _plainBackground(BuildContext context, PresentationCue cue) {
  WidgetsBinding.instance.addPostFrameCallback((_) => cue.onReady());
  return const ColoredBox(color: Colors.black);
}

Future<void> _pumpPage(WidgetTester tester, CompositionPresentationData data) {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: CompositionPresentationPage(
        data: data,
        background: _plainBackground,
      ),
    ),
  );
}

/// Avance l'horloge de la vidéo jusqu'à [seconds] secondes.
Future<void> _playUntil(WidgetTester tester, double seconds) async {
  final steps = (seconds * 10).round();
  for (var index = 0; index < steps; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('la vidéo enchaîne accroche, lignes, puis l’écran Composition', (
    tester,
  ) async {
    await _pumpPage(tester, _data());
    await tester.pump();
    await tester.pump();

    expect(find.text('Passer'), findsOneWidget);

    await _playUntil(tester, 1.6);
    expect(find.text('TOAC FOOT LOISIR 2'), findsOneWidget);
    expect(find.text('COMPOSITION'), findsOneWidget);

    await _playUntil(tester, 1.6);
    expect(find.text('GARDIEN'), findsOneWidget);
    expect(find.text('TOAC FOOT LOISIR 2'), findsNothing);

    await _playUntil(tester, 2);
    expect(find.text('DÉFENSEURS'), findsOneWidget);

    await _playUntil(tester, 8);
    expect(find.text('COACH'), findsWidgets);
    expect(find.text('Philippe'), findsOneWidget);

    // Fin : l'écran Composition, sans le coach, avec « Revoir ».
    await _playUntil(tester, 7);
    expect(find.text('Revoir'), findsOneWidget);
    expect(find.text('Passer'), findsNothing);
    expect(find.byType(CompositionPitchWithBench), findsOneWidget);
    expect(find.text('Philippe'), findsNothing);
    expect(find.text('Remplaçants (2)'), findsOneWidget);
  });

  testWidgets('« Passer » mène directement à l’écran final, « Revoir » relance',
      (
    tester,
  ) async {
    await _pumpPage(tester, _data(coach: false));
    await tester.pump();
    await tester.pump();
    await _playUntil(tester, 1);

    await tester.tap(find.text('Passer'));
    await tester.pump();
    expect(find.text('Revoir'), findsOneWidget);
    expect(find.text('Aperçu : personne n’a été prévenu.'), findsOneWidget);

    await tester.tap(find.text('Revoir'));
    await tester.pump();
    expect(find.text('Passer'), findsOneWidget);
    await _playUntil(tester, 3.2);
    expect(find.text('GARDIEN'), findsOneWidget);
  });

  testWidgets('sans coach présent, pas d’écran Coach', (tester) async {
    await _pumpPage(tester, _data(coach: false));
    await tester.pump();
    await tester.pump();
    await _playUntil(tester, 14);
    expect(find.text('COACH'), findsNothing);
    expect(find.text('Philippe'), findsNothing);
  });
}
