import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/presentation/match_details_page.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_board_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_sport_report_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_availability_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

const _matchId = 'upcoming-1';

MatchDetailsData _upcoming() => MatchDetailsData(
      matchId: _matchId,
      opponentId: 'opp',
      opponentName: 'FC Test',
      isInternal: false,
      kickoffAt: DateTime.now().add(const Duration(days: 3)),
      status: 'a_venir',
      resultValidatedAt: null,
      location: 'domicile',
      address: null,
      matchType: 'championnat',
      championshipRound: 3,
      scoreGrinta: null,
      scoreOpponent: null,
      oddsWin: null,
      oddsDraw: null,
      oddsLoss: null,
      predictionParticipantCount: 0,
      headToHead: const [],
      playerStats: const [],
      startingLineup: const [],
      predictions: const [],
    );

MatchAvailabilityBoard _board({
  required String convocationState,
  required bool compositionPublished,
}) =>
    MatchAvailabilityBoard(
      matchId: _matchId,
      kickoffAt: DateTime.now().add(const Duration(days: 3)),
      opensAt: DateTime.now().subtract(const Duration(days: 1)),
      state: 'open',
      compositionPublished: compositionPublished,
      squadSizeLimit: 14,
      convocationState: convocationState,
      players: const [],
    );

Future<void> _pump(
  WidgetTester tester, {
  required bool isAdmin,
  MatchAvailabilityBoard? board,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        matchDetailsProvider(_matchId).overrideWith((ref) async => _upcoming()),
        sportsManagementEnabledProvider.overrideWithValue(true),
        isAdminViewProvider.overrideWithValue(isAdmin),
        matchAvailabilityBoardProvider(_matchId).overrideWith(
          (ref) async => board,
        ),
        authControllerProvider.overrideWith(
          (ref) => AuthController(_FakeAuthRepository()),
        ),
        publishedMatchCompositionProvider(_matchId).overrideWith(
          (ref) async => null,
        ),
        matchGoalActionsProvider(_matchId).overrideWith((ref) async => []),
        matchLiveTimelineProvider(_matchId).overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: MatchDetailsPage(matchId: _matchId)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('match à venir, vue joueur', () {
    testWidgets('rien de publié : aucune carte menant à une page vide',
        (tester) async {
      await _pump(
        tester,
        isAdmin: false,
        board: _board(convocationState: 'draft', compositionPublished: false),
      );

      expect(find.text('Effectif'), findsNothing);
      expect(find.text('Composition'), findsNothing);
    });

    testWidgets('effectif publié : seule la carte Effectif apparaît',
        (tester) async {
      await _pump(
        tester,
        isAdmin: false,
        board: _board(
          convocationState: 'published',
          compositionPublished: false,
        ),
      );

      expect(find.text('Effectif'), findsOneWidget);
      expect(find.text('Composition'), findsNothing);
    });

    testWidgets('effectif et composition publiés : les deux cartes',
        (tester) async {
      await _pump(
        tester,
        isAdmin: false,
        board:
            _board(convocationState: 'published', compositionPublished: true),
      );

      expect(find.text('Effectif'), findsOneWidget);
      expect(find.text('Composition'), findsOneWidget);
    });
  });

  testWidgets('l’administrateur garde ses deux cartes pour préparer le match',
      (tester) async {
    await _pump(
      tester,
      isAdmin: true,
      board: _board(convocationState: 'draft', compositionPublished: false),
    );

    expect(find.text('Effectif'), findsOneWidget);
    expect(find.text('Composition'), findsOneWidget);
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
