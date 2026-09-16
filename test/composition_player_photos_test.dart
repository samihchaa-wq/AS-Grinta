import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';
import 'package:as_grinta/features/sports_management/domain/availability_reminder_models.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_history.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:as_grinta/features/sports_management/presentation/admin_squad_plan_page.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// La photo d'un joueur doit survivre à tout l'écran de composition : au
/// premier brouillon, où rien n'est encore enregistré, comme après chaque
/// déplacement sur le terrain. Elle avait disparu parce que l'écran recopiait
/// les vignettes champ par champ et en oubliait un.
const String _matchId = 'match-composition-photos';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'le brouillon initial et la simulation gardent la photo des joueurs',
    (tester) async {
      await HttpOverrides.runZoned(
        () async {
          await _pumpComposition(tester);

          expect(_photoOf(tester, 'Alex'), 'https://photos.test/p1.jpg');
          expect(_photoOf(tester, 'Bruno'), 'https://photos.test/p2.jpg');

          await _tap(tester, OutlinedButton, 'Simuler une composition');
          await tester.pump(const Duration(seconds: 5));
          await _pumpFrames(tester);

          // Les joueurs sont passés du banc au terrain : la pastille doit
          // toujours porter leur photo.
          expect(_photoOf(tester, 'Alex'), 'https://photos.test/p1.jpg');
          expect(_photoOf(tester, 'Bruno'), 'https://photos.test/p2.jpg');
        },
        createHttpClient: (_) => _TransparentPixelHttpClient(),
      );
    },
  );
}

String? _photoOf(WidgetTester tester, String name) {
  final avatars = tester
      .widgetList<PlayerAvatar>(find.byType(PlayerAvatar))
      .where((avatar) => avatar.name == name);
  expect(avatars, isNotEmpty, reason: 'pastille de $name introuvable');
  return avatars.first.photoUrl;
}

Future<void> _tap(WidgetTester tester, Type type, String label) async {
  final button = find.widgetWithText(type, label);
  expect(button, findsOneWidget, reason: 'bouton « $label » introuvable');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _pumpFrames(tester);
}

Future<void> _pumpComposition(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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
    // Une URL externe complète est affichable telle quelle : le test reste
    // ainsi hors du cache d'URLs signées, qui a besoin de Supabase.
    photoUrl: 'https://photos.test/$id.jpg',
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

/// Sert un pixel transparent à toute requête d'image : sans cela, le client
/// HTTP des tests répond 400 et l'erreur de chargement masquerait ce que le
/// test veut vérifier.
final Uint8List _transparentPixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8'
  'BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class _TransparentPixelHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _TransparentPixelHttpRequest(url);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _TransparentPixelHttpRequest(url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TransparentPixelHttpRequest implements HttpClientRequest {
  _TransparentPixelHttpRequest(this.uri);

  @override
  final Uri uri;

  @override
  final HttpHeaders headers = _EmptyHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _TransparentPixelHttpResponse();

  @override
  Future<HttpClientResponse> get done => close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TransparentPixelHttpResponse implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _transparentPixel.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  final HttpHeaders headers = _EmptyHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_transparentPixel).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyHttpHeaders implements HttpHeaders {
  @override
  List<String>? operator [](String name) => null;

  @override
  String? value(String name) => null;

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
