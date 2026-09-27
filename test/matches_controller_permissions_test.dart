import 'dart:async';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Seul un administrateur gère les matchs : pour tout autre compte, la
/// demande s'arrête dans l'application, avant même d'atteindre le serveur.
void main() {
  ProviderContainer containerFor(
    AuthRole role,
    _RecordingMatchesRepository repository,
  ) {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((ref) => _SignedInController(role)),
        matchesRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('un joueur ne peut pas supprimer un match', () async {
    final repository = _RecordingMatchesRepository();
    final container = containerFor(AuthRole.pronostiqueur, repository);

    final failure = await container
        .read(matchesControllerProvider.notifier)
        .deleteMatch('m1');

    expect(failure, 'Seul le staff peut supprimer un match.');
    expect(repository.deleted, isEmpty);
  });

  test('un administrateur supprime le match puis recharge le calendrier',
      () async {
    final repository = _RecordingMatchesRepository();
    final container = containerFor(AuthRole.admin, repository);

    final failure = await container
        .read(matchesControllerProvider.notifier)
        .deleteMatch('m1');

    expect(failure, isNull);
    expect(repository.deleted, ['m1']);
    expect(repository.seasonLoads, 1);
  });
}

class _RecordingMatchesRepository implements MatchesRepository {
  final deleted = <String>[];
  int seasonLoads = 0;

  @override
  Future<void> deleteMatch(String id) async => deleted.add(id);

  @override
  Future<List<Map<String, dynamic>>> fetchSeasons() async {
    seasonLoads += 1;
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchOpponents() async => const [];

  @override
  Future<List<MatchModel>> fetchMatches({String? seasonId}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedInController extends AuthController {
  _SignedInController(AuthRole role) : super(_FakeAuthRepository()) {
    state = AuthState(
      isLoading: false,
      isAuthenticated: true,
      hasSession: true,
      profile: AuthProfile(
        id: 'profile-1',
        firstName: 'Karim',
        lastName: 'Test',
        role: role,
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
