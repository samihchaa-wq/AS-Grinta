import 'package:as_grinta/features/matches/data/historical_match_detail_repository.dart';
import 'package:as_grinta/features/matches/presentation/historical_match_detail_page.dart';
import 'package:as_grinta/features/matches/presentation/widgets/completed_match_composition_card.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _archiveRow({
  required List<String> presentNames,
  Map<String, dynamic> photoUrls = const {},
  Map<String, dynamic> identities = const {},
}) {
  return {
    'formation': null,
    'field_players': const <Map<String, dynamic>>[],
    'bench_players': const <String>[],
    'present_names': presentNames,
    'scorers': const <Map<String, dynamic>>[],
    'motm_names': const <String>[],
    'photo_urls': photoUrls,
    'display_names': identities,
  };
}

void main() {
  test('un match archivé sans composition garde la photo de chaque joueur', () {
    final detail = historicalMatchDetailFromRow(
      _archiveRow(
        presentNames: ['Olivier Millet', 'Xavier Inconnu'],
        photoUrls: const {'Olivier Millet': ' photos/poulain.jpg '},
        identities: const {
          'Olivier Millet': {'name': 'Poulain', 'last_initial': 'M'},
        },
      ),
    );

    final roster = historicalFallbackPlayers(detail);
    final poulain = roster.firstWhere((player) => player.name == 'Poulain');
    final xavier = roster.firstWhere((player) => player.name == 'Xavier');

    expect(poulain.photoUrl, 'photos/poulain.jpg');
    expect(poulain.lastInitial, 'M');
    // Sans photo connue, la pastille retombe sur les initiales.
    expect(xavier.photoUrl, isNull);
    expect(xavier.lastInitial, 'I');
  });

  test('une photo absente ou vide ne devient jamais une URL', () {
    final detail = historicalMatchDetailFromRow(
      _archiveRow(
        presentNames: ['Xavier Inconnu'],
        photoUrls: const {'Xavier Inconnu': '   '},
      ),
    );

    expect(historicalFallbackPlayers(detail).single.photoUrl, isNull);
  });

  testWidgets('la liste « Joueurs (n) » montre une pastille par joueur', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompletedCompositionCard(
              composition: null,
              fallbackPlayers: [
                CompletedPlayerSummary(name: 'Alban', goals: 0),
                CompletedPlayerSummary(name: 'Pipo', goals: 2),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(PlayerAvatar), findsNWidgets(2));
    expect(find.text('Alban'), findsOneWidget);
    expect(find.text('⚽ ×2'), findsOneWidget);
  });
}
