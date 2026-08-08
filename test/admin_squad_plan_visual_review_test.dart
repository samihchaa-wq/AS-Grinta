import 'dart:io';
import 'dart:ui' as ui;

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';
import 'package:as_grinta/features/sports_management/domain/availability_reminder_models.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_history.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:as_grinta/features/sports_management/presentation/admin_squad_plan_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = Key('admin-squad-plan-visual-review');
const _matchId = 'match-visual-review';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures the compact effectif with explicit save',
      (tester) async {
    await _setPhoneViewport(tester);
    await _pumpWorkspace(
      tester,
      convocations: _convocations(),
      initialStep: 'effectif',
    );

    expect(
      find.textContaining('jusqu’à ce que tu appuies sur Enregistrer.'),
      findsOneWidget,
    );
    expect(find.byType(ActionChip), findsWidgets);
    expect(
      find.widgetWithText(FilledButton, 'Enregistrer'),
      findsOneWidget,
    );
    expect(find.textContaining('Brouillon'), findsNothing);
    await _capture(tester, 'effectif_compact_enregistrer.png');
  });

  testWidgets('captures the composition with explicit save', (tester) async {
    await _setPhoneViewport(tester);
    await _pumpWorkspace(
      tester,
      convocations: _convocations(),
      initialStep: 'composition',
    );

    expect(
      find.textContaining('puis appuie sur Enregistrer.'),
      findsOneWidget,
    );
    expect(find.text('Remplaçants (3)'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Enregistrer'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Publier la composition'),
      findsNothing,
    );
    expect(find.textContaining('Brouillon'), findsNothing);
    await _capture(tester, 'composition_enregistrer.png');
  });
}

Future<void> _setPhoneViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _pumpWorkspace(
  WidgetTester tester, {
  required MatchConvocations convocations,
  required String initialStep,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: ProviderScope(
        overrides: [
          sportWaitlistRepositoryProvider.overrideWithValue(
            _FakeSportWaitlistRepository(convocations),
          ),
          matchCompositionRepositoryProvider.overrideWithValue(
            _FakeMatchCompositionRepository(),
          ),
          upcomingMatchFixtureProvider(_matchId).overrideWith(
            (ref) async => const UpcomingMatchFixtureData(
              status: 'a_venir',
              location: 'domicile',
              opponentName: 'Olympique Test',
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('fr', 'FR'),
          supportedLocales: const [Locale('fr', 'FR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.dark,
          home: AdminSquadPlanPage(
            initialMatchId: _matchId,
            initialStep: initialStep,
          ),
        ),
      ),
    ),
  );
  await _pumpFrames(tester, count: 20);
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var index = 0; index < count; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _capture(WidgetTester tester, String fileName) async {
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Capture PNG impossible.');
    final directory = Directory('build/visual-review');
    await directory.create(recursive: true);
    await File('${directory.path}/$fileName').writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  });
}

MatchConvocations _convocations() {
  final players = [
    _player(
      id: 'p1',
      seasonPlayerId: 'sp1',
      name: 'Alex',
      isGoalkeeper: true,
      status: ConvocationStatus.convoked,
      waitlistPosition: 1,
    ),
    _player(
      id: 'p2',
      seasonPlayerId: 'sp2',
      name: 'Bruno',
      status: ConvocationStatus.convoked,
      waitlistPosition: 2,
    ),
    _player(
      id: 'p3',
      seasonPlayerId: 'sp3',
      name: 'Clara',
      status: ConvocationStatus.convoked,
      waitlistPosition: 3,
    ),
    _player(
      id: 'p4',
      seasonPlayerId: 'sp4',
      name: 'Diego',
      availabilityStatus: 'absent',
      status: ConvocationStatus.notApplicable,
    ),
    _player(
      id: 'p5',
      seasonPlayerId: 'sp5',
      name: 'Emma',
      availabilityStatus: 'no_response',
      status: ConvocationStatus.notApplicable,
    ),
  ];

  return MatchConvocations(
    matchId: _matchId,
    opponentName: 'Olympique Test',
    kickoffAt: DateTime.now().add(const Duration(days: 2)),
    seasonId: 'season-visual',
    squadSizeLimit: 14,
    publishedSquadSizeLimit: 14,
    convocationState: 'published',
    convocationVersion: 2,
    hasUnpublishedChanges: false,
    lateWithdrawalCutoffAt: null,
    availableCount: players.where((player) => player.isAvailable).length,
    convokedCount: players.where((player) => player.isConvoked).length,
    notConvokedCount: players.where((player) => player.isNotConvoked).length,
    players: players,
  );
}

ConvocationPlayer _player({
  required String id,
  required String seasonPlayerId,
  required String name,
  required ConvocationStatus status,
  String availabilityStatus = 'available',
  bool isGoalkeeper = false,
  int? waitlistPosition,
}) {
  return ConvocationPlayer(
    participantId: id,
    seasonPlayerId: seasonPlayerId,
    firstName: name,
    lastName: 'Grinta',
    availabilityStatus: availabilityStatus,
    convocationStatus: status,
    publishedConvocationStatus: status,
    manualOverride: true,
    waitlistPosition: waitlistPosition,
    recommendedNotConvoked: false,
    turnShouldConsume: status == ConvocationStatus.notConvoked,
    turnState: status == ConvocationStatus.notConvoked
        ? WaitlistTurnState.pending
        : WaitlistTurnState.waived,
    promotedAfterWithdrawalAt: null,
    isGoalkeeper: isGoalkeeper,
  );
}

class _FakeSportWaitlistRepository implements SportWaitlistRepository {
  _FakeSportWaitlistRepository(this.convocations);

  final MatchConvocations convocations;

  @override
  Future<List<AdminSportMatch>> fetchUpcomingMatches() async => [
        AdminSportMatch(
          id: _matchId,
          opponentName: 'Olympique Test',
          kickoffAt: convocations.kickoffAt,
        ),
      ];

  @override
  Future<MatchConvocations> fetchMatchConvocations(String matchId) async =>
      convocations;

  @override
  Future<AvailabilityReminderSummary> fetchReminderSummary(
    String matchId,
  ) async {
    return const AvailabilityReminderSummary(
      matchId: _matchId,
      availabilityState: 'open',
      noResponseCount: 1,
      openSentCount: 1,
      j3SentCount: 0,
      j1SentCount: 0,
      canRemind: true,
      players: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatchCompositionRepository implements MatchCompositionRepository {
  @override
  Future<MatchComposition?> fetchAdminComposition(String matchId) async => null;

  @override
  Future<Set<String>> fetchGoalkeeperSeasonPlayerIds(
    List<String> seasonPlayerIds,
  ) async =>
      {'sp1'};

  @override
  Future<Map<String, String>> fetchCanonicalPlayerIds(
    List<String> seasonPlayerIds,
  ) async =>
      const {};

  @override
  Future<List<PlayedPosition>> fetchPlayerPositionHistory(
    DateTime since,
  ) async =>
      const [];

  @override
  Future<Map<String, int>> fetchFinishedBenchCounts(String matchId) async =>
      const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
