import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_board_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_availability_board.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_board_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// L'onglet Effectif des joueurs montre les mêmes personnes que la page des
/// admins, de la même façon : photos, titres, compteur et ordre.
void main() {
  final kickoffAt = DateTime.now().add(const Duration(days: 3));

  Map<String, dynamic> player(
    String name, {
    required String status,
    String convocation = 'not_applicable',
    int? position,
    bool coach = false,
    String? photo,
    bool goalkeeper = false,
  }) =>
      {
        'participant_id': 'p-$name',
        'season_player_id': 'sp-$name',
        'first_name': name,
        'last_name': '',
        'display_name': name,
        'is_coach': coach,
        'status': status,
        'convocation_status': convocation,
        'waitlist_position': position,
        'photo_url': photo,
        'is_goalkeeper': goalkeeper,
      };

  MatchAvailabilityBoard board() => MatchAvailabilityBoard.fromRpc({
        'match_id': 'match-1',
        'kickoff_at': kickoffAt.toUtc().toIso8601String(),
        'availability_opens_at': kickoffAt
            .subtract(const Duration(days: 6))
            .toUtc()
            .toIso8601String(),
        'availability_state': 'open',
        'composition_published': false,
        'squad_size_limit': 2,
        'convocation_state': 'published',
        'players': [
          player('Aki',
              status: 'available',
              convocation: 'convoked',
              position: 2,
              photo: 'aki/avatar.jpg'),
          player('Hakim',
              status: 'available',
              convocation: 'convoked',
              position: 1,
              goalkeeper: true),
          player('Philippe',
              status: 'available', convocation: 'convoked', coach: true),
          player('Julien',
              status: 'available', convocation: 'not_convoked', position: 3),
          player('Zoé', status: 'absent', position: 4),
          player('Bruno', status: 'absent', position: 5),
          player('Simon', status: 'no_response', position: 6),
        ],
      });

  group('tableau d’effectif', () {
    test('transmet la photo et le poste de gardien', () {
      final players = {for (final p in board().players) p.displayName: p};
      expect(players['Aki']!.photoUrl, 'aki/avatar.jpg');
      expect(players['Hakim']!.photoUrl, isNull);
      expect(players['Hakim']!.isGoalkeeper, isTrue);
      expect(players['Aki']!.isGoalkeeper, isFalse);
    });

    test('ordre des convoqués : coach d’abord, puis liste inversée', () {
      expect(
        board().convoked.map((p) => p.displayName),
        ['Philippe', 'Aki', 'Hakim'],
      );
    });

    test('absents dans l’ordre de la liste d’attente, comme chez les admins',
        () {
      expect(
        board()
            .playersWith(MatchAvailabilityBoardStatus.absent)
            .map((p) => p.displayName),
        ['Zoé', 'Bruno'],
      );
    });

    test('le coach est compté à part', () {
      expect(effectifCountText(total: 15, coaches: 1), '14 + coach');
      expect(effectifCountText(total: 3, coaches: 0), '3');
      expect(effectifCountText(total: 5, coaches: 2), '3 + 2 coachs');
    });
  });

  Future<void> pump(WidgetTester tester, {String matchType = 'amical'}) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sportsManagementEnabledProvider.overrideWithValue(true),
          matchAvailabilityBoardProvider('match-1').overrideWith(
            (ref) async => board(),
          ),
          matchInfoProvider('match-1').overrideWith(
            (ref) async => MatchInfo(
              kickoffAt: kickoffAt,
              address: null,
              lastEncounters: const [],
              matchType: matchType,
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MatchAvailabilityBoardCard(
                matchId: 'match-1',
                showAfterComposition: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('vue joueur : photos et mêmes titres que les admins',
      (tester) async {
    await pump(tester);

    expect(find.text('Convoqués (2 + coach)'), findsOneWidget);
    expect(find.text('Liste d’attente (1)'), findsOneWidget);
    expect(find.text('Absents (2)'), findsOneWidget);
    expect(find.text('Sans réponse (1)'), findsOneWidget);
    expect(find.textContaining('Disponibles'), findsNothing);

    // Un avatar par personne, photo ou initiales.
    expect(find.byType(PlayerAvatar), findsNWidgets(7));
    final aki = tester.widget<PlayerAvatar>(
      find.descendant(
        of: find.byKey(const ValueKey('board-player-p-Aki')),
        matching: find.byType(PlayerAvatar),
      ),
    );
    expect(aki.photoUrl, 'aki/avatar.jpg');

    // Plus de pastilles sans photo.
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('match entre nous : pas de liste d’attente ni de limite',
      (tester) async {
    await pump(tester, matchType: 'entre_nous');

    expect(find.textContaining('Liste d’attente'), findsNothing);
    expect(find.textContaining('limite indicative'), findsNothing);
    expect(find.text('Convoqués (2 + coach)'), findsOneWidget);
  });
}
