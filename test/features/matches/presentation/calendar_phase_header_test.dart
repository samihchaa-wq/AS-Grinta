import 'dart:async';
import 'dart:typed_data';

import 'package:as_grinta/core/widgets/calendar_scoreline.dart';
import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/matches/data/calendar_history_repository.dart';
import 'package:as_grinta/features/matches/data/club_events_repository.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/matches/domain/club_event.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/predictions/presentation/merged_matches_view.dart';
import 'package:as_grinta/features/sports_management/presentation/match_availability_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// En faisant défiler le calendrier, l'en-tête « Terminés » restait collé
/// au-dessus de « À venir » alors qu'il n'y avait plus rien dessous : l'espace
/// sous la dernière carte terminée appartenait encore au bloc « Terminés ».
void main() {
  testWidgets(
    'l’en-tête « Terminés » ne reste jamais seul au-dessus de « À venir »',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final matches = [
        for (var i = 6; i >= 1; i--)
          _match('past-$i', now.subtract(Duration(days: 7 * i)),
              finished: true),
        for (var i = 1; i <= 6; i++)
          _match('next-$i', now.add(Duration(days: 7 * i)), finished: false),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => AuthController(_FakeAuthRepository()),
            ),
            matchesControllerProvider.overrideWith(
              (ref) => _StaticMatchesController(ref, matches),
            ),
            isAdminViewProvider.overrideWithValue(false),
            sportsManagementEnabledProvider.overrideWithValue(false),
            clubEventsProvider.overrideWith(
              (ref) => Stream.value(const <ClubEvent>[]),
            ),
            allHistoricalMatchesProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            myMatchAvailabilityProvider.overrideWith((ref, id) async => null),
          ],
          child: const MaterialApp(home: Scaffold(body: MergedMatchesView())),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final viewportTop = tester.getRect(scrollable).top;
      position.jumpTo(0);
      await tester.pump();

      var sawPinned = false;
      var sawPushed = false;
      for (var step = 0; step < 600; step += 1) {
        position.jumpTo(position.pixels + 2);
        await tester.pump();

        final finished = find.text('Terminés');
        final upcoming = find.text('À venir');
        if (finished.evaluate().isEmpty) {
          if (sawPinned) break;
          continue;
        }
        if (upcoming.evaluate().isEmpty) continue;
        final finishedHeader = _headerRect(tester, finished);
        final upcomingHeader = _headerRect(tester, upcoming);
        final gap = upcomingHeader.top - finishedHeader.bottom;
        final pinned = (finishedHeader.top - viewportTop).abs() < 0.5;
        if (pinned) {
          sawPinned = true;
        } else if (finishedHeader.top < viewportTop) {
          sawPushed = true;
        }
        // Tant que « Terminés » reste en haut, une carte terminée doit être
        // visible dessous : l'écart jusqu'à « À venir » est alors au moins
        // l'espace normal entre deux phases. Un écart plus petit, c'est un
        // en-tête « Terminés » seul au-dessus du vide.
        expect(
          gap,
          greaterThanOrEqualTo(CalendarCardSpacing.betweenCards - 0.5),
          reason: 'en-tête « Terminés » '
              '${pinned ? 'épinglé' : 'poussé'} au-dessus d’un vide de '
              '${gap.toStringAsFixed(1)} px',
        );
      }
      expect(sawPinned, isTrue, reason: '« Terminés » jamais épinglé');
      expect(sawPushed, isTrue, reason: '« Terminés » jamais poussé');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    },
  );
}

Rect _headerRect(WidgetTester tester, Finder title) => tester.getRect(
      find.ancestor(of: title, matching: find.byType(DecoratedBox)).first,
    );

MatchModel _match(String id, DateTime kickoffAt, {required bool finished}) =>
    MatchModel(
      id: id,
      seasonId: 's1',
      opponentId: 'o-$id',
      kickoffAt: kickoffAt,
      isHome: true,
      plannedDurationMinutes: 90,
      status: finished ? 'termine' : 'a_venir',
      grintaScore: finished ? 2 : null,
      opponentScore: finished ? 1 : null,
      resultValidatedAt:
          finished ? kickoffAt.add(const Duration(hours: 2)) : null,
      opponentName: 'Adversaire $id',
      seasonName: '2026-2027',
    );

class _StaticMatchesController extends MatchesController {
  _StaticMatchesController(Ref ref, List<MatchModel> matches)
      : super(_UnusedMatchesRepository(), ref) {
    state = MatchesState(matches: matches, isLoading: false);
  }

  @override
  Future<void> load({
    String? seasonId,
    bool allSeasons = false,
    bool forceRefresh = false,
  }) async {}
}

class _UnusedMatchesRepository implements MatchesRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthRepository implements AuthRepository {
  final StreamController<supabase.AuthState> _events =
      StreamController<supabase.AuthState>.broadcast();

  @override
  Stream<supabase.AuthState> get authStateChanges => _events.stream;

  @override
  bool get hasSession => false;

  @override
  Future<AuthProfile?> fetchProfile({bool retryAfterSignIn = false}) =>
      Completer<AuthProfile?>().future;

  @override
  Future<void> signInWithUsername({
    required String username,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> updatePassword(String password) async {}

  @override
  Future<AuthProfile> updateProfile({
    required String firstName,
    required String lastName,
    String? surnom,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthProfile> uploadProfilePhoto({
    required Uint8List bytes,
    required String fileExt,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> registerAccount({
    required String firstName,
    required String lastName,
    required String password,
  }) async {
    return 'test-user';
  }
}
