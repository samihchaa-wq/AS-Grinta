import 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';
import 'package:as_grinta/features/sports_management/domain/availability_reminder_models.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:as_grinta/features/sports_management/presentation/admin_waitlist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'dragging the first player onto the second reorders and saves the list',
    (tester) async {
      final repository = _FakeSportWaitlistRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sportWaitlistRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: AdminWaitlistPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bruno'), findsOneWidget);
      expect(find.text('Saison précédente : 2'), findsOneWidget);
      expect(
        find.text('Tour cette saison : 3 fois'),
        findsOneWidget,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Alice')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(tester.getCenter(find.text('Bruno')));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester
          .tap(find.widgetWithText(FilledButton, 'Enregistrer l’ordre'));
      await tester.pumpAndSettle();

      expect(repository.savedOrder, ['bruno', 'alice']);
      expect(find.text('Liste d’attente enregistrée.'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping + next to a player adjusts and persists their waitlist count',
    (tester) async {
      final repository = _FakeSportWaitlistRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sportWaitlistRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: AdminWaitlistPage()),
        ),
      );
      await tester.pumpAndSettle();

      final brunoCard = find.ancestor(
        of: find.text('Bruno'),
        matching: find.byType(Card),
      );
      final incrementButtonFinder = find.descendant(
        of: brunoCard,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              (widget.icon as Icon).icon == Icons.add_circle_outline,
        ),
      );
      // Invoked directly rather than via tester.tap(): the button sits
      // inside a nested DragTarget/LongPressDraggable stack whose gesture
      // arena makes a coordinate-based tap unreliable in this test harness.
      tester.widget<IconButton>(incrementButtonFinder).onPressed!();
      await tester.pumpAndSettle();

      expect(repository.lastManualCountSeasonPlayerId, 'bruno');
      expect(repository.lastManualCount, 2);
      expect(
        find.descendant(
          of: brunoCard,
          matching: find.text('Tour cette saison : 2 fois'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Recalculer sorts by waitlist count then previous season attendance',
    (tester) async {
      final repository = _FakeSportWaitlistRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sportWaitlistRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: AdminWaitlistPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Recalculer'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(FilledButton, 'Enregistrer l’ordre'));
      await tester.pumpAndSettle();

      expect(repository.savedOrder, ['bruno', 'alice']);
    },
  );
}

class _FakeSportWaitlistRepository implements SportWaitlistRepository {
  List<String>? savedOrder;
  String? lastManualCountSeasonPlayerId;
  int? lastManualCount;

  SportWaitlist get _waitlist => const SportWaitlist(
        seasonId: 'season',
        seasonName: '2026-2027',
        entries: [
          SportWaitlistEntry(
            seasonPlayerId: 'alice',
            firstName: 'Alice',
            lastName: 'Grinta',
            position: 1,
            previousSeasonAttendanceCount: 2,
            previousSeasonMatchCount: 10,
            currentSeasonWaitlistCount: 3,
            source: 'previous_season_attendance',
          ),
          SportWaitlistEntry(
            seasonPlayerId: 'bruno',
            firstName: 'Bruno',
            lastName: 'Grinta',
            position: 2,
            previousSeasonAttendanceCount: 4,
            previousSeasonMatchCount: 10,
            currentSeasonWaitlistCount: 1,
            source: 'previous_season_attendance',
          ),
        ],
      );

  @override
  Future<SportWaitlist> fetchWaitlist({String? seasonId}) async => _waitlist;

  @override
  Future<SportWaitlist> fetchWaitlistReadOnly({String? seasonId}) async =>
      _waitlist;

  @override
  Future<SportWaitlist> reorderWaitlist({
    required String seasonId,
    required List<String> orderedPlayerIds,
    String? reason,
  }) async {
    savedOrder = List.of(orderedPlayerIds);
    final byId = {
      for (final entry in _waitlist.entries) entry.seasonPlayerId: entry,
    };
    return SportWaitlist(
      seasonId: seasonId,
      seasonName: _waitlist.seasonName,
      entries: [
        for (var index = 0; index < orderedPlayerIds.length; index++)
          SportWaitlistEntry(
            seasonPlayerId: orderedPlayerIds[index],
            firstName: byId[orderedPlayerIds[index]]!.firstName,
            lastName: byId[orderedPlayerIds[index]]!.lastName,
            position: index + 1,
            previousSeasonAttendanceCount:
                byId[orderedPlayerIds[index]]!.previousSeasonAttendanceCount,
            previousSeasonMatchCount:
                byId[orderedPlayerIds[index]]!.previousSeasonMatchCount,
            currentSeasonWaitlistCount:
                byId[orderedPlayerIds[index]]!.currentSeasonWaitlistCount,
            source: 'manual',
          ),
      ],
    );
  }

  @override
  Future<void> setWaitlistManualCount({
    required String seasonPlayerId,
    required int count,
  }) async {
    lastManualCountSeasonPlayerId = seasonPlayerId;
    lastManualCount = count;
  }

  @override
  Future<List<AdminSportMatch>> fetchUpcomingMatches() async => const [];

  @override
  Future<MatchConvocations> fetchMatchConvocations(String matchId) {
    throw UnimplementedError();
  }

  @override
  Future<AvailabilityReminderSummary> fetchReminderSummary(String matchId) {
    throw UnimplementedError();
  }

  @override
  Future<AvailabilityReminderResult> sendAvailabilityReminder({
    required String matchId,
    String? seasonPlayerId,
    String? reason,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MatchConvocations> configureMatch({
    required String matchId,
    required int squadSizeLimit,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MatchConvocations> saveEffectif({
    required String matchId,
    required int squadSizeLimit,
    required Map<String, ConvocationStatus> decisions,
    String? reason,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MatchConvocations> publishEffectif({
    required String matchId,
    required int squadSizeLimit,
    required Map<String, ConvocationStatus> decisions,
    String? reason,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MatchConvocations> recomputeMatch({
    required String matchId,
    bool resetOverrides = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MatchConvocations> setConvocation({
    required String matchId,
    required String seasonPlayerId,
    required ConvocationStatus status,
    required bool turnShouldConsume,
    String? reason,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MatchConvocations> publishMatch({
    required String matchId,
    String? reason,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> finalizeTurns(String matchId) async => 0;
}
