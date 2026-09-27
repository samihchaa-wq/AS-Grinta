import 'dart:async';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/domain/feature_flags.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/matches/data/match_edit_schedule_repository.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/matches/domain/convocation_launch.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/match_form_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Formulaire de modification d'un match.
///
/// Deux administrateurs qui modifient le même match en même temps ne doivent
/// pas écraser en silence le travail l'un de l'autre : chaque enregistrement
/// envoie la version du match chargée à l'ouverture du formulaire, et le
/// serveur refuse si le match a changé depuis. Seul un administrateur peut
/// enregistrer ou supprimer.
void main() {
  final loadedVersion = DateTime.utc(2026, 9, 20, 18, 30, 12);

  group('formulaire de modification', () {
    testWidgets('un match entre nous est enregistré avec la version chargée',
        (tester) async {
      final schedule = _RecordingScheduleRepository();
      final match = _match('entre_nous', updatedAt: loadedVersion);

      await _openForm(tester, match: match, schedule: schedule, admin: true);
      await _save(tester);

      expect(schedule.internalUpdates, hasLength(1));
      expect(schedule.internalUpdates.single.id, match.id);
      expect(schedule.internalUpdates.single.expectedUpdatedAt, loadedVersion);
      // Le formulaire se referme une fois l'enregistrement accepté.
      expect(find.byType(MatchFormPage), findsNothing);
    });

    testWidgets(
        'un match de championnat est enregistré avec la version chargée',
        (tester) async {
      // Seule assertion tolérée : la case « Garder cette adresse » est posée
      // sur un fond coloré, ce que Flutter signale en mode test (l'effet
      // d'appui y est invisible). Toute autre erreur fait échouer le test.
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains(
              'ListTile background color or ink splashes may be invisible',
            )) {
          return;
        }
        original?.call(details);
      };
      try {
        final schedule = _RecordingScheduleRepository();
        final match = _match('championnat', updatedAt: loadedVersion);

        await _openForm(tester, match: match, schedule: schedule, admin: true);
        await _save(tester);

        expect(schedule.matchUpdates, hasLength(1));
        expect(schedule.matchUpdates.single.id, match.id);
        expect(schedule.matchUpdates.single.expectedUpdatedAt, loadedVersion);
      } finally {
        FlutterError.onError = original;
      }
    });

    testWidgets('un refus du serveur laisse le formulaire ouvert',
        (tester) async {
      final schedule = _RecordingScheduleRepository()
        ..failure = StateError('Le match a changé.');
      final match = _match('entre_nous', updatedAt: loadedVersion);

      await _openForm(tester, match: match, schedule: schedule, admin: true);
      await _save(tester);

      expect(schedule.internalUpdates, hasLength(1));
      expect(find.byType(MatchFormPage), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('droits', () {
    testWidgets(
        'un joueur non administrateur ne peut ni enregistrer ni '
        'supprimer', (tester) async {
      final schedule = _RecordingScheduleRepository();
      final match = _match('entre_nous', updatedAt: loadedVersion);

      await _openForm(tester, match: match, schedule: schedule, admin: false);

      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Enregistrer'),
      );
      expect(save.onPressed, isNull);
      expect(find.text('Supprimer définitivement le match'), findsNothing);
    });

    testWidgets('un administrateur peut supprimer le match', (tester) async {
      final schedule = _RecordingScheduleRepository();
      final match = _match('entre_nous', updatedAt: loadedVersion);

      await _openForm(tester, match: match, schedule: schedule, admin: true);

      expect(find.text('Supprimer définitivement le match'), findsOneWidget);
    });
  });
}

MatchModel _match(String matchType, {required DateTime updatedAt}) {
  final kickoff = DateTime.now().add(const Duration(days: 10));
  return MatchModel(
    id: 'match-$matchType',
    seasonId: 's1',
    opponentId: matchType == 'entre_nous' ? '' : 'o1',
    kickoffAt: DateTime(kickoff.year, kickoff.month, kickoff.day, 21),
    isHome: true,
    plannedDurationMinutes: 90,
    status: 'a_venir',
    grintaScore: null,
    opponentScore: null,
    matchType: matchType,
    oddsWin: 2,
    oddsDraw: 3,
    oddsLoss: 4,
    opponentName: 'FC Test',
    updatedAt: updatedAt,
  );
}

Future<void> _openForm(
  WidgetTester tester, {
  required MatchModel match,
  required MatchEditScheduleRepository schedule,
  required bool admin,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _SignedInController(admin: admin),
        ),
        matchesRepositoryProvider.overrideWithValue(_FakeMatchesRepository()),
        matchesControllerProvider.overrideWith(
          (ref) => _StaticMatchesController(ref),
        ),
        matchEditScheduleRepositoryProvider.overrideWithValue(schedule),
        featureFlagsControllerProvider.overrideWith(_PendingFlags.new),
        sportsManagementEnabledProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Calendrier')),
      ),
    ),
  );
  unawaited(
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => MatchFormPage(match: match)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  final save = find.widgetWithText(FilledButton, 'Enregistrer');
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

typedef _Update = ({String id, DateTime? expectedUpdatedAt});

class _RecordingScheduleRepository implements MatchEditScheduleRepository {
  final internalUpdates = <_Update>[];
  final matchUpdates = <_Update>[];
  Object? failure;

  @override
  Future<void> updateInternalMatch({
    required String id,
    required String seasonId,
    required DateTime kickoffAt,
    required DateTime? expectedUpdatedAt,
    String? address,
    DateTime? meetingAt,
    ConvocationLaunchMode? launchMode,
    DateTime? customLaunchAt,
  }) async {
    internalUpdates.add((id: id, expectedUpdatedAt: expectedUpdatedAt));
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<void> updateMatch({
    required String id,
    required String seasonId,
    required String opponentId,
    required DateTime kickoffAt,
    required bool isHome,
    required String status,
    required double oddsWin,
    required double oddsDraw,
    required double oddsLoss,
    required DateTime? expectedUpdatedAt,
    int? squadSizeLimit,
    String? address,
    bool rememberAddressAsDefault = false,
    String matchType = 'championnat',
    String? jerseyNote,
    DateTime? meetingAt,
    ConvocationLaunchMode? launchMode,
    DateTime? customLaunchAt,
  }) async {
    matchUpdates.add((id: id, expectedUpdatedAt: expectedUpdatedAt));
    final error = failure;
    if (error != null) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticMatchesController extends MatchesController {
  _StaticMatchesController(Ref ref) : super(_FakeMatchesRepository(), ref) {
    state = const MatchesState(
      isLoading: false,
      seasons: [
        {'id': 's1', 'name': '2026-2027', 'status': 'open'},
      ],
      opponents: [
        {'id': 'o1', 'name': 'FC Test', 'address': ''},
      ],
      selectedSeasonId: 's1',
    );
  }

  @override
  Future<void> load({
    String? seasonId,
    bool allSeasons = false,
    bool forceRefresh = false,
  }) async {}
}

class _FakeMatchesRepository implements MatchesRepository {
  @override
  Future<String?> fetchClubHomeAddress() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingFlags extends FeatureFlagsController {
  @override
  Future<FeatureFlagsSnapshot> build() =>
      Completer<FeatureFlagsSnapshot>().future;
}

class _SignedInController extends AuthController {
  _SignedInController({required bool admin}) : super(_FakeAuthRepository()) {
    state = AuthState(
      isLoading: false,
      isAuthenticated: true,
      hasSession: true,
      profile: AuthProfile(
        id: 'profile-1',
        firstName: 'Samih',
        lastName: 'Test',
        role: admin ? AuthRole.admin : AuthRole.pronostiqueur,
        isGoalkeeper: false,
        isActive: true,
        mustChangePassword: false,
      ),
    );
  }
}

class _FakeAuthRepository implements AuthRepository {
  final _events = StreamController<supabase.AuthState>.broadcast();

  @override
  Stream<supabase.AuthState> get authStateChanges => _events.stream;

  @override
  bool get hasSession => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
