import 'dart:async';
import 'dart:typed_data';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Une action ratée (annuler un match, clôturer un match entre nous, créer un
/// adversaire) renvoie son message. Elle ne doit plus écrire `state.error`,
/// qui remplaçait tout le calendrier par la carte « Matchs indisponibles ».
void main() {
  late ProviderContainer container;
  late _FailingMatchesRepository repository;

  setUp(() {
    repository = _FailingMatchesRepository();
    container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((ref) => _AdminAuthController()),
        matchesRepositoryProvider.overrideWithValue(repository),
      ],
    );
  });

  tearDown(() => container.dispose());

  MatchesController controller() =>
      container.read(matchesControllerProvider.notifier);

  test('annuler un match : le message revient, le calendrier reste', () async {
    final failure = await controller().cancelMatch('m1');

    expect(failure, 'Tu n’as pas les droits pour cette action.');
    expect(container.read(matchesControllerProvider).error, isNull);
    expect(container.read(matchesControllerProvider).isLoading, isFalse);
  });

  test('clôturer un match entre nous : le message revient', () async {
    final failure = await controller().finishInternalMatch('m1');

    expect(failure, 'Tu n’as pas les droits pour cette action.');
    expect(container.read(matchesControllerProvider).error, isNull);
    expect(container.read(matchesControllerProvider).isLoading, isFalse);
  });

  test('créer un adversaire : le message revient, sans identifiant', () async {
    final created = await controller().createOpponent('FC Test');

    expect(created.id, isNull);
    expect(created.error, 'Tu n’as pas les droits pour cette action.');
    expect(container.read(matchesControllerProvider).error, isNull);
  });

  test('un nom d’adversaire trop court est refusé sans toucher au calendrier',
      () async {
    final created = await controller().createOpponent('F');

    expect(created.error, 'Nom d’adversaire invalide.');
    expect(repository.calls, isEmpty);
    expect(container.read(matchesControllerProvider).error, isNull);
  });
}

const _permissionDenied = supabase.PostgrestException(
  message: 'permission denied for function cancel_match',
  code: '42501',
);

class _FailingMatchesRepository implements MatchesRepository {
  final calls = <String>[];

  @override
  Future<void> cancelMatch(String id) async {
    calls.add('cancel');
    throw _permissionDenied;
  }

  @override
  Future<void> updateMatchStatus({
    required String id,
    required String status,
  }) async {
    calls.add('status');
    throw _permissionDenied;
  }

  @override
  Future<String> createOpponent(String name) async {
    calls.add('opponent');
    throw _permissionDenied;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AdminAuthController extends AuthController {
  _AdminAuthController() : super(_FakeAuthRepository()) {
    state = const AuthState(
      isLoading: false,
      isAuthenticated: true,
      hasSession: true,
      profile: AuthProfile(
        id: 'admin',
        firstName: 'Admin',
        lastName: 'Test',
        role: AuthRole.admin,
        isGoalkeeper: false,
        isActive: true,
        mustChangePassword: false,
      ),
    );
  }
}

class _FakeAuthRepository implements AuthRepository {
  final StreamController<supabase.AuthState> _events =
      StreamController<supabase.AuthState>.broadcast();

  @override
  Stream<supabase.AuthState> get authStateChanges => _events.stream;

  @override
  bool get hasSession => true;

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
