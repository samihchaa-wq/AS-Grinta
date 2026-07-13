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
    _authSubscription =
        _repository.authStateChanges.listen((_) => _refreshProfile());
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
        isAuthenticated: profile != null && profile.isActive,
        profile: profile,
        clearProfile: profile == null,
        clearError: true,
      );
      if (profile != null && !profile.isActive) {
        await _repository.signOut();
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: false,
          clearProfile: true,
          error: 'Ton compte doit être validé par l’admin avant de pouvoir '
              'te connecter.',
        );
      }
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Le profil n’a pas pu être chargé.',
      );
    }
  }

  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.signInWithUsername(
        username: username,
        password: password,
      );
      await _refreshProfile();
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error:
            'Connexion impossible. Vérifie ton identifiant et ton mot de passe.',
      );
    }
  }

  Future<bool> updatePassword(String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.updatePassword(password);
      await _refreshProfile();
      return true;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Le mot de passe n’a pas pu être modifié.',
      );
      return false;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.signOut();
      state = const AuthState(isLoading: false);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'La déconnexion a échoué.',
      );
    }
  }

  Future<void> updateProfile({
    required String firstName,
    required String lastName,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final profile = await _repository.updateProfile(
        firstName: firstName,
        lastName: lastName,
      );
      state = state.copyWith(
        isLoading: false,
        profile: profile,
        clearError: true,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Le profil n’a pas pu être enregistré.',
      );
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthController(repository);
});
