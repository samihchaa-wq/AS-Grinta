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
    _authSubscription = _repository.authStateChanges.listen((event) {
      _authGeneration += 1;
      if (event.event == supabase.AuthChangeEvent.signedOut) {
        _retryRefreshQueued = false;
        state = const AuthState(isLoading: false);
        return;
      }
      unawaited(_refreshProfile(retryAfterSignIn: true));
    });
    unawaited(_refreshProfile());
  }

  final AuthRepository _repository;
  StreamSubscription<supabase.AuthState>? _authSubscription;
  Future<void>? _refreshInFlight;
  bool _retryRefreshQueued = false;
  int _authGeneration = 0;

  Future<void> _refreshProfile({bool retryAfterSignIn = false}) {
    if (retryAfterSignIn) {
      _retryRefreshQueued = true;
    }

    final existing = _refreshInFlight;
    if (existing != null) return existing;

    final refresh = _drainRefreshQueue(
      initialRetryAfterSignIn: retryAfterSignIn,
    );
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<void> _drainRefreshQueue({
    required bool initialRetryAfterSignIn,
  }) async {
    var retryAfterSignIn = initialRetryAfterSignIn;
    do {
      if (retryAfterSignIn) {
        _retryRefreshQueued = false;
      }
      await _performRefresh(retryAfterSignIn: retryAfterSignIn);
      retryAfterSignIn = _retryRefreshQueued;
    } while (retryAfterSignIn);
  }

  Future<void> _performRefresh({required bool retryAfterSignIn}) async {
    final refreshGeneration = _authGeneration;
    try {
      final profile = await _repository.fetchProfile(
        retryAfterSignIn: retryAfterSignIn,
      );
      if (refreshGeneration != _authGeneration) return;

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: profile != null && profile.isActive,
        profile: profile,
        clearProfile: profile == null,
        clearError: true,
      );
      if (profile != null && !profile.isActive) {
        await _repository.signOut();
        if (refreshGeneration != _authGeneration) return;
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: false,
          clearProfile: true,
          error: 'Ton compte doit être validé par l’admin avant de pouvoir '
              'te connecter.',
        );
      }
    } catch (_) {
      if (refreshGeneration != _authGeneration) return;
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        clearProfile: true,
        error: 'Le profil n’a pas pu être chargé. Réessaie dans un instant.',
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
      await _refreshProfile(retryAfterSignIn: true);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        clearProfile: true,
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
