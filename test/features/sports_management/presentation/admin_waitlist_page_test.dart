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
      expect(find.text('Saison\nprécédente'), findsOneWidget);
      expect(find.text('Tour cette\nsaison'), findsOneWidget);
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
    'manual reordering is no longer available',
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

      expect(find.byKey(const ValueKey('waitlist-drag-alice')), findsNothing);
      expect(find.text('Enregistrer l’ordre'), findsNothing);
      expect(find.text('Recalculer'), findsOneWidget);
      expect(repository.savedOrder, isNull);
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

      expect(repository.returnedOrder, ['bruno', 'alice']);
    },
  );
}

class _FakeSportWaitlistRepository implements SportWaitlistRepository {
  List<String>? savedOrder;
  String? lastManualCountSeasonPlayerId;
  int? lastManualCount;
  int brunoCount = 1;
  List<String>? returnedOrder;

  SportWaitlist get _waitlist => SportWaitlist(
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
            currentSeasonWaitlistCount: brunoCount,
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
    // Le faux serveur ignore l'ordre envoyé et applique les règles 3.
    final entries = List<SportWaitlistEntry>.of(_waitlist.entries)
      ..sort((a, b) {
        final byCount = a.currentSeasonWaitlistCount.compareTo(
          b.currentSeasonWaitlistCount,
        );
        if (byCount != 0) return byCount;
        final byPrevious = a.previousSeasonAttendanceCount.compareTo(
          b.previousSeasonAttendanceCount,
        );
        if (byPrevious != 0) return byPrevious;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    returnedOrder = entries.map((e) => e.seasonPlayerId).toList();
    return SportWaitlist(
      seasonId: seasonId,
      seasonName: _waitlist.seasonName,
      entries: [
        for (var index = 0; index < entries.length; index++)
          SportWaitlistEntry(
            seasonPlayerId: entries[index].seasonPlayerId,
            firstName: entries[index].firstName,
            lastName: entries[index].lastName,
            position: index + 1,
            previousSeasonAttendanceCount:
                entries[index].previousSeasonAttendanceCount,
            previousSeasonMatchCount: entries[index].previousSeasonMatchCount,
            currentSeasonWaitlistCount:
                entries[index].currentSeasonWaitlistCount,
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
    if (seasonPlayerId == 'bruno') brunoCount = count;
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
    Set<String> changedPlayerIds = const {},
    String? reason,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> overrideAvailability({
    required String matchId,
    required String seasonPlayerId,
    required String status,
    String? reason,
  }) {
    throw UnimplementedError();
  }
}
