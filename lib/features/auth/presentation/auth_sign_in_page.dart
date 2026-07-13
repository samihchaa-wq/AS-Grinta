import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AuthSignInPage extends ConsumerStatefulWidget {
  const AuthSignInPage({super.key});

  @override
  ConsumerState<AuthSignInPage> createState() => _AuthSignInPageState();
}

class _AuthSignInPageState extends ConsumerState<AuthSignInPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim().toLowerCase();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Renseigne ton identifiant et ton mot de passe.'),
        ),
      );
      return;
    }

    await ref.read(authControllerProvider.notifier).signIn(
          username: username,
          password: password,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if ((next.error ?? '').isNotEmpty &&
          (previous?.error ?? '') != next.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!)),
        );
      }
    });

    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Image.asset(
                          'assets/images/mpg_logo.png',
                          width: double.infinity,
                          fit: BoxFit.fitWidth,
                        ),
                      ),
                      Text(
                        'Le petit prono maison de l’AS Grinta.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _usernameController,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Identifiant',
                          hintText: 'prénom + initiale du nom, ex. samihc',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        onSubmitted: (_) =>
                            authState.isLoading ? null : _submit(),
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: authState.isLoading ? null : _submit,
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Se connecter'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => context.go('/auth/register'),
                        icon: const Icon(Icons.person_add_alt_outlined),
                        label: const Text('Créer mon compte'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Mot de passe oublié ? Demande à l’admin de le '
                        'réinitialiser. Il te transmettra un mot de passe '
                        'temporaire à remplacer après connexion.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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
