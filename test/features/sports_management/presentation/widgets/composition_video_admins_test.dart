import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';
import 'package:as_grinta/features/sports_management/domain/availability_reminder_models.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_history.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:as_grinta/features/sports_management/presentation/admin_squad_plan_page.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_presentation.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/player_composition_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support_composition_landing.dart';

/// Les admins qui n'ont pas publié la compo voient sa vidéo comme les
/// joueurs ; celui qui l'a publiée depuis ce téléphone garde son « Aperçu ».
const String _matchId = 'match-video-admins';

void main() {
  setUp(() => debugPresentationBackground = _plainBackground);
  tearDown(() => debugPresentationBackground = null);

  testWidgets('un autre admin voit la vidéo à sa première visite',
      (tester) async {
    await _pumpPublished(tester, store: _MemoryStore());
    expect(find.byType(CompositionPresentationPage), findsOneWidget);
    expect(find.text('Aperçu : personne n’a été prévenu.'), findsNothing);
  });

  testWidgets('la vidéo se pose sur l’écran admin et rend la main',
      (tester) async {
    await _pumpPublished(tester, store: _MemoryStore());
    final page = tester.widget<CompositionPresentationPage>(
      find.byType(CompositionPresentationPage),
    );
    expect(page.landing, isNotNull, reason: 'la vidéo vise le vrai écran');
    await tester.tap(find.text('Passer'));
    for (var index = 0; index < 10; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CompositionPresentationPage), findsNothing);
    final edit = find.widgetWithText(OutlinedButton, 'Modifier la composition');
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    for (var index = 0; index < 5; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.widgetWithText(OutlinedButton, 'Aperçu'), findsOneWidget);
  });

  testWidgets('les joueurs se posent exactement sur ceux de l’écran admin',
      (tester) async {
    await _pumpPublished(tester, store: _MemoryStore());
    await expectLandsOnPage(tester);
  });

  testWidgets('aperçu pendant une modification : retour à l’éditeur',
      (tester) async {
    await _pumpPublished(
      tester,
      store: _MemoryStore()..seen.add(_matchId),
    );
    final edit = find.widgetWithText(OutlinedButton, 'Modifier la composition');
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    for (var index = 0; index < 5; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final preview = find.widgetWithText(OutlinedButton, 'Aperçu');
    await tester.ensureVisible(preview);
    await tester.pump();
    await tester.tap(preview);
    for (var index = 0; index < 10; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final page = tester.widget<CompositionPresentationPage>(
      find.byType(CompositionPresentationPage),
    );
    expect(page.endsOnPage, isTrue);
    expect(page.landing, isNull, reason: 'l’éditeur n’a pas la même forme');

    // Jusqu'au bout, sans « Passer » : ni copie ni « Revoir » à la fin.
    for (var index = 0; index < 500; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Revoir'), findsNothing);
    }
    expect(find.byType(CompositionPresentationPage), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Aperçu'), findsOneWidget);
    expect(find.text('Simuler une composition'), findsOneWidget);
  });

  testWidgets('un autre admin, déjà vue : compo normale', (tester) async {
    await _pumpPublished(
      tester,
      store: _MemoryStore()..seen.add(_matchId),
    );
    expect(find.byType(CompositionPresentationPage), findsNothing);
  });

  testWidgets('un autre admin, depuis la notification : vidéo même déjà vue',
      (tester) async {
    await _pumpPublished(
      tester,
      store: _MemoryStore()..seen.add(_matchId),
      fromNotification: true,
    );
    expect(find.byType(CompositionPresentationPage), findsOneWidget);
  });

  testWidgets('celui qui a publié : jamais d’elle-même, même par la notif',
      (tester) async {
    await _pumpPublished(
      tester,
      store: _MemoryStore()..published.add(_matchId),
      fromNotification: true,
    );
    expect(find.byType(CompositionPresentationPage), findsNothing);
    expect(find.text('Aperçu de la vidéo'), findsOneWidget);
  });
}

final MatchComposition _published = MatchComposition(
  matchId: _matchId,
  formationCode: null,
  status: 'published',
  version: 1,
  hasUnpublishedChanges: false,
  squadSizeExceptionApproved: false,
  entries: [
    _entry('p1', 'Alex', MatchCompositionZone.field, goalkeeper: true),
    _entry('p2', 'Bruno', MatchCompositionZone.field),
    _entry('p3', 'Clara', MatchCompositionZone.bench),
  ],
);

MatchCompositionEntry _entry(
  String id,
  String name,
  MatchCompositionZone zone, {
  bool goalkeeper = false,
}) =>
    MatchCompositionEntry(
      participantId: id,
      seasonPlayerId: 's$id',
      displayName: name,
      isGoalkeeper: goalkeeper,
      zone: zone,
      sortOrder: 0,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'selected',
      x: zone == MatchCompositionZone.field ? .5 : null,
      y: zone == MatchCompositionZone.field ? (goalkeeper ? .9 : .5) : null,
    );

class _MemoryStore extends CompositionVideoSeenStore {
  final Set<String> seen = {};
  final Set<String> published = {};

  @override
  Future<bool> hasSeen(String matchId) async => seen.contains(matchId);

  @override
  Future<void> markSeen(String matchId) async => seen.add(matchId);

  @override
  Future<bool> publishedHere(String matchId) async =>
      published.contains(matchId);

  @override
  Future<void> markPublishedHere(String matchId) async =>
      published.add(matchId);
}

Widget _plainBackground(BuildContext context, PresentationCue cue) {
  WidgetsBinding.instance.addPostFrameCallback((_) => cue.onReady());
  return const ColoredBox(color: Colors.black);
}

Future<void> _pumpPublished(
  WidgetTester tester, {
  required _MemoryStore store,
  bool fromNotification = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        compositionVideoSeenStoreProvider.overrideWithValue(store),
        sportWaitlistRepositoryProvider.overrideWithValue(
          _FakeSportWaitlistRepository(_convocations()),
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
          initialStep: 'composition',
          fromNotification: fromNotification,
        ),
      ),
    ),
  );
  for (var index = 0; index < 30; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

MatchConvocations _convocations() {
  final players = [
    _player(id: 'p1', name: 'Alex', isGoalkeeper: true),
    _player(id: 'p2', name: 'Bruno'),
    _player(id: 'p3', name: 'Clara'),
  ];

  return MatchConvocations(
    matchId: _matchId,
    opponentName: 'Olympique Test',
    kickoffAt: DateTime.now().add(const Duration(days: 2)),
    seasonId: 'season-photos',
    squadSizeLimit: 14,
    publishedSquadSizeLimit: 14,
    convocationState: 'published',
    convocationVersion: 2,
    hasUnpublishedChanges: false,
    lateWithdrawalCutoffAt: null,
    availableCount: players.length,
    convokedCount: players.length,
    notConvokedCount: 0,
    players: players,
  );
}

ConvocationPlayer _player({
  required String id,
  required String name,
  bool isGoalkeeper = false,
}) {
  return ConvocationPlayer(
    participantId: id,
    seasonPlayerId: 's$id',
    firstName: name,
    lastName: 'Grinta',
    availabilityStatus: 'available',
    convocationStatus: ConvocationStatus.convoked,
    publishedConvocationStatus: ConvocationStatus.convoked,
    manualOverride: true,
    waitlistPosition: null,
    recommendedNotConvoked: false,
    turnShouldConsume: false,
    turnState: WaitlistTurnState.waived,
    promotedAfterWithdrawalAt: null,
    isGoalkeeper: isGoalkeeper,
    photoUrl: null,
  );
}

class _FakeSportWaitlistRepository implements SportWaitlistRepository {
  _FakeSportWaitlistRepository(this._convocations);

  final MatchConvocations _convocations;

  @override
  Future<List<AdminSportMatch>> fetchUpcomingMatches() async => [
        AdminSportMatch(
          id: _matchId,
          opponentName: 'Olympique Test',
          kickoffAt: _convocations.kickoffAt,
        ),
      ];

  @override
  Future<MatchConvocations> fetchMatchConvocations(String matchId) async =>
      _convocations;

  @override
  Future<AvailabilityReminderSummary> fetchReminderSummary(
    String matchId,
  ) async =>
      const AvailabilityReminderSummary(
        matchId: _matchId,
        availabilityState: 'open',
        noResponseCount: 0,
        openSentCount: 0,
        j3SentCount: 0,
        j1SentCount: 0,
        canRemind: false,
        players: [],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatchCompositionRepository implements MatchCompositionRepository {
  MatchComposition? savedComposition;

  @override
  Future<MatchComposition?> fetchAdminComposition(String matchId) async =>
      _published;

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
  Future<FinishedBenchHistory> fetchFinishedBenchHistory(
    String matchId,
  ) async =>
      FinishedBenchHistory.empty;

  @override
  Future<MatchComposition> saveComposition({
    required MatchComposition composition,
    required bool allowSquadSizeException,
    String? reason,
  }) async {
    savedComposition = composition;
    return composition;
  }

  @override
  Future<MatchComposition> publishComposition({
    required String matchId,
    required bool allowSquadSizeException,
    String? reason,
  }) async {
    return savedComposition!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
