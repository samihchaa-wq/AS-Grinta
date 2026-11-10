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
    'players cannot be dragged to another place in the list',
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
      expect(
        find.byType(LongPressDraggable<SportWaitlistEntry>),
        findsNothing,
      );
      expect(find.byType(DragTarget<SportWaitlistEntry>), findsNothing);
    },
  );

  testWidgets(
    'waitlist has no save, recalculate or refresh button: pull to refresh',
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

      expect(find.text('Recalculer'), findsNothing);
      expect(find.text('Enregistrer l’ordre'), findsNothing);
      expect(find.byTooltip('Actualiser'), findsNothing);
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.text('Saison 2026-2027'), findsNothing);
      expect(find.textContaining('L’application commence'), findsNothing);

      final table = tester.widget<StickyHeaderTableCard>(
        find.byType(StickyHeaderTableCard),
      );
      expect(table.onRefresh, isNotNull);
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
}

class _FakeSportWaitlistRepository implements SportWaitlistRepository {
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
