import 'package:as_grinta/core/security/password_policy.dart';
import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:as_grinta/core/widgets/grinta_adaptive_form.dart';
import 'package:as_grinta/core/widgets/grinta_auth_surface.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRegisterPage extends ConsumerStatefulWidget {
  const AuthRegisterPage({super.key});

  @override
  ConsumerState<AuthRegisterPage> createState() => _AuthRegisterPageState();
}

class _AuthRegisterPageState extends ConsumerState<AuthRegisterPage> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty) {
      _showError('Renseigne ton prénom, ton nom et ton adresse e-mail.');
      return;
    }
    if (!isValidPersonName(firstName) || !isValidPersonName(lastName)) {
      _showError('Le prénom et le nom ne doivent contenir que des lettres.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      _showError('Entre une adresse e-mail valide.');
      return;
    }
    final passwordError = PasswordPolicy.validate(password);
    if (passwordError != null) {
      _showError(passwordError);
      return;
    }
    if (password != _confirmController.text) {
      _showError('Les deux mots de passe ne correspondent pas.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(authRepositoryProvider).registerAccount(
            firstName: firstName,
            lastName: lastName,
            email: email,
            password: password,
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Vérifie ton e-mail'),
          content: const Text(
            'Un lien de confirmation vient de t’être envoyé. Après confirmation, '
            'ton compte restera en attente jusqu’à sa validation par un admin.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Compris'),
            ),
          ],
        ),
      );
      if (mounted) context.go('/auth/sign-in');
    } on AuthException catch (error) {
      _showError(error.message);
    } on StateError catch (error) {
      _showError(error.message);
    } on ArgumentError catch (error) {
      _showError(error.message?.toString() ?? PasswordPolicy.helperText);
    } catch (_) {
      _showError('La création du compte a échoué.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GrintaAuthSurface(
      maxWidth: 760,
      title: 'Créer mon compte',
      subtitle:
          'Le compte sera accessible après confirmation de l’e-mail et validation par un admin.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GrintaAdaptiveForm(
            children: [
              TextField(
                controller: _firstNameController,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.givenName],
                decoration: const InputDecoration(
                  labelText: 'Prénom',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              TextField(
                controller: _lastNameController,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.familyName],
                decoration: const InputDecoration(
                  labelText: 'Nom',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Adresse e-mail',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              helperText: PasswordPolicy.helperText,
              helperMaxLines: 2,
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscurePassword
                    ? 'Afficher le mot de passe'
                    : 'Masquer le mot de passe',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(
                  () => _obscurePassword = !_obscurePassword,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) => _submitting ? null : _submit(),
            decoration: const InputDecoration(
              labelText: 'Confirme ton mot de passe',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: GrintaProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sports_soccer),
            label:
                Text(_submitting ? 'Création en cours…' : 'Créer mon compte'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _submitting ? null : () => context.go('/auth/sign-in'),
            child: const Text('J’ai déjà un compte — se connecter'),
          ),
        ],
      ),
    );
  }
}
