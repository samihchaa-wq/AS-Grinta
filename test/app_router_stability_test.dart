import 'dart:async';

import 'package:as_grinta/app/router/app_router.dart';
import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

void main() {
  test('keeps the same GoRouter instance across authentication changes', () async {
    final controller = _TestAuthController();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((ref) => controller),
      ],
    );
    addTearDown(container.dispose);

    await Future<void>.delayed(Duration.zero);
    final initialRouter = container.read(appRouterProvider);

    controller.emit(
      const AuthState(
        isLoading: false,
        isAuthenticated: true,
        profile: AuthProfile(
          id: 'admin',
          firstName: 'Admin',
          lastName: 'User',
          role: AuthRole.admin,
          isGoalkeeper: false,
          isActive: true,
          mustChangePassword: false,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appRouterProvider), same(initialRouter));

    controller.emit(const AuthState(isLoading: false));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appRouterProvider), same(initialRouter));
  });
}

class _TestAuthController extends AuthController {
  _TestAuthController() : super(_FakeAuthRepository());

  void emit(AuthState value) => state = value;
}

class _FakeAuthRepository implements AuthRepository {
  final StreamController<supabase.AuthState> _events =
      StreamController<supabase.AuthState>.broadcast();

  @override
  Stream<supabase.AuthState> get authStateChanges => _events.stream;

  @override
  Future<AuthProfile?> fetchProfile({bool retryAfterSignIn = false}) async =>
      null;

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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> registerAccount({
    required String firstName,
    required String lastName,
    required String password,
  }) async {
    return 'test';
  }
}
