import 'dart:async';
import 'dart:typed_data';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

const _signInTimeout = Duration(seconds: 12);
const _invalidCredentialsMessage =
    'Connexion impossible. Vérifie ton identifiant et ton mot de passe.';
const _signInUnavailableMessage =
    'Connexion temporairement indisponible. Vérifie ta connexion et réessaie.';

String authSignInErrorMessage(Object error) {
  if (error is supabase.AuthException) {
    final code = error.code?.toLowerCase();
    final message = error.message.toLowerCase();
    if (code == 'invalid_credentials' ||
        message.contains('invalid login credentials')) {
      return _invalidCredentialsMessage;
    }
  }
  return _signInUnavailableMessage;
}

class AuthState {
  const AuthState({
    this.isLoading = true,
    this.isSaving = false,
    this.isAuthenticated = false,
    this.hasSession = false,
    this.profile,
    this.error,
  });

  /// Résolution de la session : c'est le seul drapeau que le routeur observe.
  /// Le passer à vrai renvoie l'utilisateur sur `/auth/loading`.
  final bool isLoading;

  /// Écriture en cours sur le profil. Volontairement distinct de [isLoading] :
  /// enregistrer un surnom ne doit pas faire sortir l'utilisateur de l'écran
  /// où il se trouve.
  final bool isSaving;
  final bool isAuthenticated;
  final bool hasSession;
  final AuthProfile? profile;
  final String? error;

  /// Pour les écrans : désactive les actions pendant un chargement comme
  /// pendant un enregistrement.
  bool get isBusy => isLoading || isSaving;

  AuthState copyWith({
    bool? isLoading,
    bool? isSaving,
    bool? isAuthenticated,
    bool? hasSession,
    AuthProfile? profile,
    String? error,
    bool clearError = false,
    bool clearProfile = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      hasSession: hasSession ?? this.hasSession,
      profile: clearProfile ? null : (profile ?? this.profile),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthState()) {
    _authSubscription = _repository.authStateChanges.listen((event) {
      // Supabase.initialize a déjà restauré la session avant que l'application
      // soit montée et le constructeur lance son propre refresh juste après
      // l'abonnement. Traiter `initialSession` ici invalidait ce refresh en
      // cours et laissait l'écran bloqué jusqu'au fallback de 15 secondes.
      if (event.event == supabase.AuthChangeEvent.initialSession) return;

      _authGeneration += 1;
      if (event.event == supabase.AuthChangeEvent.signedOut) {
        _retryRefreshQueued = false;
        state = const AuthState(isLoading: false);
        return;
      }
      // La boucle de réessai n'a de sens qu'après une vraie connexion, le
      // temps que le profil devienne visible.
      final isFreshSignIn = event.event == supabase.AuthChangeEvent.signedIn;
      unawaited(_refreshProfile(retryAfterSignIn: isFreshSignIn));
    });
    unawaited(_refreshProfile());
    _loadingFallback = Timer(const Duration(seconds: 15), () {
      if (!state.isLoading) return;
      final hasSession = _repository.hasSession;
      if (hasSession) {
        state = state.copyWith(
          isLoading: false,
          hasSession: true,
          isAuthenticated: state.profile?.isActive == true,
          error:
              'Connexion temporairement indisponible. Réessaie dans un instant.',
        );
      } else {
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

  Future<void> refreshProfile() => _refreshProfile();

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

      final hasSession = _repository.hasSession;
      if (profile == null && hasSession) {
        state = state.copyWith(
          isLoading: false,
          hasSession: true,
          isAuthenticated: state.profile?.isActive == true,
          error:
              'Connexion temporairement indisponible. Réessaie dans un instant.',
        );
        return;
      }

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: profile != null && profile.isActive,
        hasSession: hasSession,
        profile: profile,
        clearProfile: profile == null,
        clearError: true,
      );

      // Un compte en attente conserve sa session Supabase. Il reste cantonné
      // à l'écran d'attente par le routeur jusqu'à validation par un admin.
      if (profile?.isPending == true) return;

      // Un compte archivé/inactif ne doit en revanche conserver aucune session.
      if (profile != null && !profile.isActive) {
        await _repository.signOut();
        if (refreshGeneration != _authGeneration) return;
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: false,
          hasSession: false,
          clearProfile: true,
          error: 'Ce compte n’est pas actif.',
        );
      }
    } catch (_) {
      if (refreshGeneration != _authGeneration) return;
      _loadingFallback?.cancel();
      final hasSession = _repository.hasSession;
      if (hasSession) {
        state = state.copyWith(
          isLoading: false,
          hasSession: true,
          isAuthenticated: state.profile?.isActive == true,
          error:
              'Connexion temporairement indisponible. Réessaie dans un instant.',
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: false,
          hasSession: false,
          clearProfile: true,
          error: 'Le profil n’a pas pu être chargé. Réessaie dans un instant.',
        );
      }
    }
  }

  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository
          .signInWithUsername(
            username: username,
            password: password,
          )
          .timeout(_signInTimeout);
      await _refreshProfile(retryAfterSignIn: true);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        hasSession: _repository.hasSession,
        clearProfile: true,
        error: authSignInErrorMessage(error),
      );
    }
  }

  Future<bool> updatePassword(String password) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repository.updatePassword(password);
      await _refreshProfile();
      state = state.copyWith(isSaving: false);
      return true;
    } catch (_) {
      state = state.copyWith(
        isSaving: false,
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
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final profile = await _repository.updateProfile(
        firstName: firstName,
        lastName: lastName,
        surnom: surnom,
      );
      state = state.copyWith(
        isSaving: false,
        isAuthenticated: profile.isActive,
        hasSession: _repository.hasSession,
        profile: profile,
        clearError: true,
      );
    } catch (_) {
      state = state.copyWith(
        isSaving: false,
        error: 'Le profil n’a pas pu être enregistré.',
      );
    }
  }

  Future<void> uploadPhoto({
    required Uint8List bytes,
    required String fileExt,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final profile = await _repository.uploadProfilePhoto(
        bytes: bytes,
        fileExt: fileExt,
      );
      state = state.copyWith(
        isSaving: false,
        isAuthenticated: profile.isActive,
        hasSession: _repository.hasSession,
        profile: profile,
        clearError: true,
      );
    } on ProfilePhotoWriteConfirmedButRefreshFailed {
      state = state.copyWith(
        isSaving: false,
        error: 'Photo enregistrée, mais le profil n’a pas pu être actualisé. '
            'Actualise la page.',
      );
    } on ProfilePhotoUploadOutcomeUnknown {
      state = state.copyWith(
        isSaving: false,
        error: 'Connexion interrompue pendant l’envoi de la photo. '
            'Actualise le profil avant de réessayer.',
      );
    } on ProfilePhotoWriteOutcomeUnknown {
      state = state.copyWith(
        isSaving: false,
        error: 'Connexion interrompue : la photo a peut-être été enregistrée. '
            'Actualise le profil avant de réessayer.',
      );
    } catch (_) {
      state = state.copyWith(
        isSaving: false,
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

const _viewAsUserPreferenceKey = 'as_grinta.view_as_user';

/// Mode « Aperçu utilisateur » d'un administrateur.
///
/// À modifier via [setViewAsUser], qui le mémorise : sans persistance, un
/// simple rechargement rendait ses boutons d'administration à l'admin sans le
/// prévenir, alors qu'il se croyait toujours en aperçu.
final viewAsUserProvider = StateProvider<bool>((ref) => false);

/// Bascule le mode aperçu et le mémorise localement.
Future<void> setViewAsUser(WidgetRef ref, bool value) async {
  ref.read(viewAsUserProvider.notifier).state = value;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_viewAsUserPreferenceKey, value);
  } catch (_) {
    // Stockage local indisponible (navigation privée, quota) : l'aperçu reste
    // simplement non persistant.
  }
}

/// Restaure le mode aperçu mémorisé. Appelé une fois au démarrage.
Future<void> restoreViewAsUserPreference(WidgetRef ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_viewAsUserPreferenceKey) == true) {
      ref.read(viewAsUserProvider.notifier).state = true;
    }
  } catch (_) {
    // Ignoré : l'aperçu reprend simplement sa valeur par défaut.
  }
}

final isRealAdminProvider = Provider<bool>((ref) {
  return ref.watch(authControllerProvider).profile?.role.isAdmin == true;
});

final isAdminViewProvider = Provider<bool>((ref) {
  return ref.watch(isRealAdminProvider) && !ref.watch(viewAsUserProvider);
});
