import 'dart:async';
import 'dart:typed_data';

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
    // Filet de sécurité : l'écran de chargement ne doit JAMAIS rester bloqué.
    // Si le profil n'est pas résolu au bout de 15 s (réponse jamais reçue en
    // mode PWA standalone, boucle de retry…), on bascule sur l'écran de
    // connexion pour que l'utilisateur puisse repartir.
    _loadingFallback = Timer(const Duration(seconds: 15), () {
      if (state.isLoading) {
        state = const AuthState(isLoading: false);
      }
    });
  }

  final AuthRepository _repository;
  StreamSubscription<supabase.AuthState>? _authSubscription;
  Timer? _loadingFallback;
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
      _loadingFallback?.cancel();

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
      _loadingFallback?.cancel();
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
    String? surnom,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final profile = await _repository.updateProfile(
        firstName: firstName,
        lastName: lastName,
        surnom: surnom,
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

  Future<void> uploadPhoto({
    required Uint8List bytes,
    required String fileExt,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final profile = await _repository.uploadProfilePhoto(
        bytes: bytes,
        fileExt: fileExt,
      );
      state = state.copyWith(
        isLoading: false,
        profile: profile,
        clearError: true,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'La photo n’a pas pu être enregistrée.',
      );
    }
  }

  @override
  void dispose() {
    _loadingFallback?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthController(repository);
});

/// Aperçu « utilisateur lambda » : quand actif, l'admin voit l'application
/// sans aucun contrôle réservé à l'admin, pour vérifier ce que voient les
/// joueurs. N'affecte QUE l'affichage — les droits côté serveur restent ceux
/// de l'admin.
final viewAsUserProvider = StateProvider<bool>((ref) => false);

/// Vrai si le compte connecté est réellement admin, sans tenir compte de
/// l'aperçu. Sert à afficher le bouton d'aperçu et la bannière de sortie.
final isRealAdminProvider = Provider<bool>((ref) {
  return ref.watch(authControllerProvider).profile?.role.isStaff == true;
});

/// Vrai si les contrôles admin doivent être visibles : compte admin ET pas en
/// mode aperçu utilisateur. À utiliser pour TOUTE décision d'affichage admin.
final isAdminViewProvider = Provider<bool>((ref) {
  return ref.watch(isRealAdminProvider) && !ref.watch(viewAsUserProvider);
});
