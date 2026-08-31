import 'package:as_grinta/core/security/password_policy.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForcedPasswordChangePage extends ConsumerStatefulWidget {
  const ForcedPasswordChangePage({super.key});

  @override
  ConsumerState<ForcedPasswordChangePage> createState() =>
      _ForcedPasswordChangePageState();
}

class _ForcedPasswordChangePageState
    extends ConsumerState<ForcedPasswordChangePage> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _isVerifyingRecovery = false;
  bool _recoveryTokenVerified = false;
  String? _recoveryError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<bool> _verifyRecoveryToken(Uri uri) async {
    if (_recoveryTokenVerified) return true;

    final tokenHash = uri.queryParameters['token_hash'];
    if (tokenHash == null || tokenHash.isEmpty) {
      // Compatibilité avec les anciens liens Supabase implicites : après leur
      // redirection, Supabase Flutter a déjà créé la session depuis le fragment
      // `access_token`. Sans session, la route recovery seule ne donne aucun
      // droit de modifier un mot de passe.
      if (Supabase.instance.client.auth.currentSession != null) return true;
      setState(() {
        _recoveryError =
            'Ce lien de réinitialisation est incomplet ou n’est plus valide. '
            'Demande un nouveau lien à un administrateur.';
      });
      return false;
    }

    setState(() {
      _isVerifyingRecovery = true;
      _recoveryError = null;
    });
    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        tokenHash: tokenHash,
        type: OtpType.recovery,
      );
      if (response.session == null) {
        throw const AuthException(
          'Aucune session créée après validation du lien de récupération.',
        );
      }
      if (!mounted) return false;
      setState(() {
        _isVerifyingRecovery = false;
        _recoveryTokenVerified = true;
      });
      return true;
    } on AuthException {
      if (!mounted) return false;
      setState(() {
        _isVerifyingRecovery = false;
        _recoveryError =
            'Ce lien de réinitialisation a expiré ou a déjà été utilisé. '
            'Demande un nouveau lien à un administrateur.';
      });
      return false;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _isVerifyingRecovery = false;
        _recoveryError =
            'Le lien n’a pas pu être vérifié. Vérifie ta connexion et réessaie.';
      });
      return false;
    }
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final passwordError = PasswordPolicy.validate(password);
    if (passwordError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(passwordError)),
      );
      return;
    }
    if (password != _confirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Les deux mots de passe ne correspondent pas.'),
        ),
      );
      return;
    }

    final uri = GoRouterState.of(context).uri;
    final isRecovery = uri.queryParameters['recovery'] == '1';
    if (isRecovery && !await _verifyRecoveryToken(uri)) return;
    if (!mounted) return;

    final success = await ref
        .read(authControllerProvider.notifier)
        .updatePassword(password);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nouveau mot de passe enregistré.')),
      );
      if (isRecovery) {
        context.go('/matches');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final isRecovery =
        GoRouterState.of(context).uri.queryParameters['recovery'] == '1';
    final isBusy = state.isBusy || _isVerifyingRecovery;
    final error = _recoveryError ?? state.error;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.lock_reset_rounded, size: 54),
                      const SizedBox(height: 16),
                      Text(
                        'Nouveau mot de passe',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isRecovery
                            ? 'Choisis maintenant ton nouveau mot de passe.'
                            : 'Tu es connecté avec un mot de passe temporaire. '
                                'Choisis maintenant ton mot de passe définitif.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      // Un AutofillGroup dédié + un seul champ marqué
                      // "newPassword" : avec deux champs identiquement
                      // tagués, certains navigateurs (Safari en particulier)
                      // confondent les deux champs après la confirmation et
                      // le premier redevient impossible à retoucher (le
                      // clavier ne se réaffiche plus).
                      AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscure,
                              autofocus: true,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: InputDecoration(
                                labelText: 'Nouveau mot de passe',
                                helperText: PasswordPolicy.helperText,
                                helperMaxLines: 2,
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? 'Afficher le mot de passe'
                                      : 'Masquer le mot de passe',
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _confirmController,
                              obscureText: _obscure,
                              decoration: const InputDecoration(
                                labelText: 'Confirmer le mot de passe',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              onSubmitted: (_) {
                                if (!isBusy) _submit();
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: isBusy ? null : _submit,
                        icon: isBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: GrintaProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: Text(
                          _isVerifyingRecovery
                              ? 'Vérification du lien…'
                              : 'Enregistrer mon mot de passe',
                        ),
                      ),
                      if ((error ?? '').isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
