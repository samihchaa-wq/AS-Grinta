import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';
import 'package:as_grinta/features/sports_management/domain/availability_reminder_models.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:as_grinta/features/sports_management/presentation/admin_waitlist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'waitlist uses the sticky statistics table layout',
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

      expect(find.byType(StickyHeaderTableCard), findsOneWidget);
      expect(find.text('Joueurs'), findsOneWidget);
      expect(find.text('Présence saison\nprécédente'), findsOneWidget);
      expect(find.text('Liste d’attente cette\nsaison'), findsOneWidget);
      expect(find.text('Prénoms'), findsNothing);
      expect(find.text('#'), findsNothing);
      expect(find.text('Tours'), findsNothing);
      expect(find.text('Actions'), findsNothing);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bruno'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsNothing);

      final table = tester.widget<StickyHeaderTableCard>(
        find.byType(StickyHeaderTableCard),
      );
      expect(table.rows, hasLength(2));
    },
  );

  testWidgets(
    'dragging the first table row onto the second reorders and saves the list',
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

      final aliceDrag = find.byKey(const ValueKey('waitlist-drag-alice'));
      final gesture = await tester.startGesture(tester.getCenter(aliceDrag));
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
    'waitlist opens directly on recalculate without the explanatory card',
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

      expect(find.text('Recalculer'), findsOneWidget);
      expect(find.text('Saison 2026-2027'), findsNothing);
      expect(find.textContaining('L’application commence'), findsNothing);
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

      Text countText() => tester.widget<Text>(
            find.byKey(const ValueKey('waitlist-count-bruno')),
          );

      expect(countText().data, '1');

      await tester.tap(
        find.byKey(const ValueKey('waitlist-increment-bruno')),
      );
      await tester.pumpAndSettle();

      expect(repository.lastManualCountSeasonPlayerId, 'bruno');
      expect(repository.lastManualCount, 2);
      expect(countText().data, '2');
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
  Future<MatchConvocations> publishEffectif({
    required String matchId,
    required int squadSizeLimit,
    required Map<String, ConvocationStatus> decisions,
    String? reason,
  }) {
    throw UnimplementedError();
  }
}
