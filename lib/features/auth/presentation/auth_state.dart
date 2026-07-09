import 'dart:async';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class AuthState {
  const AuthState({
    this.isLoading = true,
    this.isAuthenticated = false,
    this.profile,
    this.error,
  });

  final bool isLoading;
  final bool isAuthenticated;
  final AuthProfile? profile;
  final String? error;

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    AuthProfile? profile,
    String? error,
    bool clearError = false,
    bool clearProfile = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      profile: clearProfile ? null : (profile ?? this.profile),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthState()) {
    _authSubscription = _repository.authStateChanges.listen((_) => _refreshProfile());
    _initialize();
  }

  final AuthRepository _repository;
  StreamSubscription<supabase.AuthState>? _authSubscription;

  Future<void> _initialize() async {
    await _refreshProfile();
  }

  Future<void> _refreshProfile() async {
    try {
      final profile = await _repository.fetchProfile();
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: profile != null,
        profile: profile,
        clearProfile: profile == null,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.signInWithPassword(email: email, password: password);
      await _refreshProfile();
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.signUp(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
      );
      await _refreshProfile();
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> resetPassword({required String email}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.resetPassword(email: email);
      state = state.copyWith(isLoading: false, clearError: true);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.signOut();
      state = const AuthState(isLoading: false);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> updateProfile({
    required String firstName,
    required String lastName,
    required String avatarPath,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final profile = await _repository.updateProfile(
        firstName: firstName,
        lastName: lastName,
        avatarPath: avatarPath,
      );
      state = state.copyWith(isLoading: false, profile: profile, clearError: true);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthController(repository);
});
