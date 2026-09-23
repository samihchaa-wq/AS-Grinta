import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/presentation/match_details_page.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_sport_report_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_motm_vote_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/sport_motm_vote.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

const _matchId = 'match-1';

MatchDetailsData _details() => MatchDetailsData(
      matchId: _matchId,
      opponentId: 'opp',
      opponentName: 'FC Test',
      isInternal: false,
      kickoffAt: DateTime(2026, 9, 20, 15),
      status: 'archive',
      resultValidatedAt: DateTime(2026, 9, 20, 17),
      location: 'domicile',
      address: null,
      matchType: 'amical',
      championshipRound: null,
      scoreGrinta: 2,
      scoreOpponent: 1,
      oddsWin: null,
      oddsDraw: null,
      oddsLoss: null,
      predictionParticipantCount: 0,
      headToHead: const [],
      playerStats: const [],
      startingLineup: const [],
      predictions: const [],
    );

Map<String, dynamic> _candidate(
  String id,
  String name,
  int? votes, {
  bool? winner,
}) =>
    {
      'participant_id': id,
      'display_name': name,
      'votes_count': votes,
      'is_winner': winner,
    };

SportMotmVote _vote(String state, List<Map<String, dynamic>> candidates) =>
    SportMotmVote.fromJson({
      'match_id': _matchId,
      'state': state,
      'candidates': candidates,
    });

Future<void> _pump(
  WidgetTester tester,
  SportMotmVote vote, {
  MatchComposition? composition,
  void Function()? onCompositionFetch,
  MatchDetailsData? details,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        matchDetailsProvider(_matchId)
            .overrideWith((ref) async => details ?? _details()),
        sportMotmVoteProvider(_matchId).overrideWith((ref) async => vote),
        authControllerProvider.overrideWith(
          (ref) => AuthController(_FakeAuthRepository()),
        ),
        sportsManagementEnabledProvider.overrideWithValue(true),
        isAdminViewProvider.overrideWithValue(false),
        publishedMatchCompositionProvider(_matchId).overrideWith((ref) async {
          onCompositionFetch?.call();
          return composition;
        }),
        matchGoalActionsProvider(_matchId).overrideWith((ref) async => []),
        matchLiveTimelineProvider(_matchId).overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: MatchDetailsPage(matchId: _matchId)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Votes HDM lists ranked vote counts once the vote is closed',
      (tester) async {
    await _pump(
      tester,
      _vote('closed', [
        _candidate('a', 'Alice', 1),
        _candidate('b', 'Bruno', 4, winner: true),
        _candidate('c', 'Chloé', 0),
        _candidate('d', 'David', 2),
      ]),
      composition: MatchComposition.tryFromRpc({
        'match_id': _matchId,
        'status': 'published',
        'entries': [
          {
            'participant_id': 'b',
            'display_name': 'Brunito',
            'zone': 'bench',
          },
        ],
      }),
    );

    expect(find.text('Votes HDM'), findsOneWidget);
    // Fermé à l'ouverture de la fiche : le classement s'affiche au toucher.
    expect(find.text('4 voix'), findsNothing);
    await tester.tap(find.text('Votes HDM'));
    await tester.pumpAndSettle();
    final card = find.ancestor(
      of: find.text('Votes HDM'),
      matching: find.byType(Card),
    );
    Finder inCard(Finder finder) => find.descendant(of: card, matching: finder);
    // Le surnom de la composition remplace le nom du scrutin, avec sa pastille.
    expect(inCard(find.text('Brunito')), findsOneWidget);
    expect(inCard(find.byType(PlayerAvatar)), findsNWidgets(3));
    expect(find.text('4 voix'), findsOneWidget);
    expect(find.text('2 voix'), findsOneWidget);
    expect(find.text('1 voix'), findsOneWidget);
    expect(find.text('Chloé'), findsNothing);
    final bruno = tester.getTopLeft(inCard(find.text('Brunito'))).dy;
    final david = tester.getTopLeft(find.text('David')).dy;
    final alice = tester.getTopLeft(find.text('Alice')).dy;
    expect(bruno < david && david < alice, isTrue);
  });

  testWidgets(
      'scrolling down then back up keeps the composition loaded, '
      'so the page does not jump', (tester) async {
    var fetches = 0;
    final base = _details();
    await _pump(
      tester,
      _vote('closed', [_candidate('a', 'Alice', 3, winner: true)]),
      onCompositionFetch: () => fetches++,
      // Assez de pronos pour pousser la composition loin hors de l'écran.
      details: MatchDetailsData(
        matchId: base.matchId,
        opponentId: base.opponentId,
        opponentName: base.opponentName,
        isInternal: base.isInternal,
        kickoffAt: base.kickoffAt,
        status: base.status,
        resultValidatedAt: base.resultValidatedAt,
        location: base.location,
        address: base.address,
        matchType: base.matchType,
        championshipRound: base.championshipRound,
        scoreGrinta: base.scoreGrinta,
        scoreOpponent: base.scoreOpponent,
        oddsWin: null,
        oddsDraw: null,
        oddsLoss: null,
        predictionParticipantCount: 60,
        headToHead: const [],
        playerStats: const [],
        startingLineup: const [],
        predictions: [
          for (var i = 0; i < 60; i++)
            MatchPredictionResult(
              profileId: 'p$i',
              name: 'Joueur $i',
              scoreGrinta: 2,
              scoreOpponent: 1,
              points: 3,
              usedX2: false,
            ),
        ],
      ),
      composition: MatchComposition.tryFromRpc({
        'match_id': _matchId,
        'status': 'published',
        'entries': [
          {'participant_id': 'a', 'display_name': 'Alice', 'zone': 'bench'},
        ],
      }),
    );
    expect(fetches, 1);

    // Prono ouvert : la page devient assez longue pour sortir la
    // composition de l'écran.
    await tester.tap(find.text('Prono'));
    await tester.pumpAndSettle();

    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, -20000));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, 20000));
    await tester.pumpAndSettle();

    expect(fetches, 1);
    // Prono reste ouvert après l'aller-retour.
    expect(find.text('Joueur 0'), findsOneWidget);
  });

  testWidgets('Votes HDM stays hidden while the vote is open', (tester) async {
    await _pump(
      tester,
      _vote('open', [_candidate('a', 'Alice', null)]),
    );

    expect(find.text('Votes HDM'), findsNothing);
  });
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Stream<supabase.AuthState> get authStateChanges => const Stream.empty();

  @override
  bool get hasSession => false;

  @override
  Future<AuthProfile?> fetchProfile({bool retryAfterSignIn = false}) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
