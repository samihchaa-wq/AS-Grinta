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
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _firstConnection = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
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

    final controller = ref.read(authControllerProvider.notifier);
    if (_firstConnection) {
      if (password.length < 8) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Le mot de passe doit contenir au moins 8 caractÃ¨res.'),
          ),
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
      await controller.claimAndSignIn(username: username, password: password);
    } else {
      await controller.signIn(username: username, password: password);
    }
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
                      if (_firstConnection)
                        Text(
                          'Bienvenue !',
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                      const SizedBox(height: 8),
                      Text(
                        _firstConnection
                            ? 'Active ton compte : entre lâidentifiant donnÃ© '
                                'par l’admin et choisis ton mot de passe.'
                            : 'Le petit prono maison de lâAS Grinta.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _usernameController,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Identifiant',
                          hintText: 'prÃ©nom + initiale du nom, ex. samihc',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: _firstConnection
                              ? 'Choisis ton mot de passe'
                              : 'Mot de passe',
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
                      if (_firstConnection) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _confirmController,
                          obscureText: _obscurePassword,
                          decoration: const InputDecoration(
                            labelText: 'Confirme ton mot de passe',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: authState.isLoading ? null : _submit,
                        icon: Icon(
                          _firstConnection
                              ? Icons.rocket_launch_outlined
                              : Icons.login_rounded,
                        ),
                        label: Text(
                          _firstConnection
                              ? 'Activer mon compte'
                              : 'Se connecter',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!_firstConnection)
                        OutlinedButton.icon(
                          onPressed: () => context.go('/auth/register'),
                          icon: const Icon(Icons.person_add_alt_outlined),
                          label: const Text('CrÃ©er mon compte'),
                        ),
                      TextButton(
                        onPressed: () => setState(
                          () => _firstConnection = !_firstConnection,
                        ),
                        child: Text(
                          _firstConnection
                              ? 'Jâai dÃ©jÃ  un compte â se connecter'
                              : 'PremiÃ¨re connexion ? Active ton compte',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _firstConnection
                            ? 'Ton identifiant tâa Ã©tÃ© communiquÃ© par l’admin.'
                            : 'Mot de passe oubliÃ© ? Demande Ã  l’admin de le '
                                'rÃ©initialiser, puis refais une premiÃ¨re '
                                'connexion.',
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
