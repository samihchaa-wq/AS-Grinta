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
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le droit d'aligner un joueur suit la convocation décidée par
/// l'administrateur, pas la disponibilité que le joueur a déclarée. Le serveur
/// applique la même règle : l'écran ne doit donc écarter que les non convoqués.
const String _matchId = 'match-selection-contract';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Droit d’être aligné', () {
    test('la convocation suffit, quelle que soit la disponibilité', () {
      expect(_entry(convoked: true, availability: 'available').canBeSelected,
          isTrue);
      expect(
          _entry(convoked: true, availability: 'absent').canBeSelected, isTrue);
      expect(_entry(convoked: true, availability: 'no_response').canBeSelected,
          isTrue);
    });

    test('un joueur non convoqué reste hors de la feuille', () {
      expect(_entry(convoked: false, availability: 'available').canBeSelected,
          isFalse);
    });
  });

  testWidgets(
    'un convoqué noté absent est bien enregistré dans la composition',
    (tester) async {
      final repository = _FakeMatchCompositionRepository();
      await _pumpComposition(tester, repository: repository);

      await _tap(tester, OutlinedButton, 'Simuler une composition');
      // Le résumé de la simulation recouvre le bouton d'enregistrement tant
      // qu'il est affiché.
      await tester.pump(const Duration(seconds: 5));
      await _pumpFrames(tester);
      await _tap(tester, FilledButton, 'Enregistrer');

      final saved = repository.savedComposition;
      expect(saved, isNotNull, reason: 'la composition doit être envoyée');

      // Diego est convoqué mais absent, Emma convoquée mais sans réponse :
      // l'administrateur les a retenus, ils partent avec l'équipe.
      expect(_zoneOf(saved!, 'p4'), isNot(MatchCompositionZone.notSelected));
      expect(_zoneOf(saved, 'p5'), isNot(MatchCompositionZone.notSelected));

      // Franck n'est pas convoqué : lui reste non retenu.
      expect(_zoneOf(saved, 'p6'), MatchCompositionZone.notSelected);
    },
  );
}

MatchCompositionEntry _entry({
  required bool convoked,
  required String availability,
}) {
  return MatchCompositionEntry(
    participantId: 'p',
    seasonPlayerId: 'sp',
    displayName: 'Joueur',
    isGoalkeeper: false,
    zone: MatchCompositionZone.bench,
    sortOrder: 0,
    availabilityStatus: availability,
    convocationStatus: convoked ? 'convoked' : 'not_convoked',
    selectionStatus: 'undecided',
  );
}

MatchCompositionZone _zoneOf(MatchComposition composition, String id) {
  return composition.entries
      .firstWhere((entry) => entry.participantId == id)
      .zone;
}

Future<void> _tap(WidgetTester tester, Type type, String label) async {
  final button = find.widgetWithText(type, label);
  expect(button, findsOneWidget, reason: 'bouton « $label » introuvable');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _pumpFrames(tester);
}

Future<void> _pumpComposition(
  WidgetTester tester, {
  required _FakeMatchCompositionRepository repository,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sportWaitlistRepositoryProvider.overrideWithValue(
          _FakeSportWaitlistRepository(_convocations()),
        ),
        matchCompositionRepositoryProvider.overrideWithValue(repository),
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
        home: const AdminSquadPlanPage(
          initialMatchId: _matchId,
          initialStep: 'composition',
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

MatchConvocations _convocations() {
  final players = [
    _player(id: 'p1', name: 'Alex', isGoalkeeper: true),
    _player(id: 'p2', name: 'Bruno'),
    _player(id: 'p3', name: 'Clara'),
    // Convoqués malgré leur indisponibilité : l'effectif l'autorise.
    _player(id: 'p4', name: 'Diego', availabilityStatus: 'absent'),
    _player(id: 'p5', name: 'Emma', availabilityStatus: 'no_response'),
    _player(id: 'p6', name: 'Franck', status: ConvocationStatus.notConvoked),
  ];

  return MatchConvocations(
    matchId: _matchId,
    opponentName: 'Olympique Test',
    kickoffAt: DateTime.now().add(const Duration(days: 2)),
    seasonId: 'season-contract',
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
  required String name,
  String availabilityStatus = 'available',
  ConvocationStatus status = ConvocationStatus.convoked,
  bool isGoalkeeper = false,
}) {
  return ConvocationPlayer(
    participantId: id,
    seasonPlayerId: 's$id',
    firstName: name,
    lastName: 'Grinta',
    availabilityStatus: availabilityStatus,
    convocationStatus: status,
    publishedConvocationStatus: status,
    manualOverride: true,
    waitlistPosition: null,
    recommendedNotConvoked: false,
    turnShouldConsume: false,
    turnState: WaitlistTurnState.waived,
    promotedAfterWithdrawalAt: null,
    isGoalkeeper: isGoalkeeper,
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
