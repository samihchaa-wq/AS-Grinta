import 'dart:typed_data';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Page publique d'auto-inscription : le lien est partagé dans la
/// conversation du club. Le compte créé reste « en attente de validation »
/// jusqu'à ce que Samih le valide dans Administration.
class AuthRegisterPage extends ConsumerStatefulWidget {
  const AuthRegisterPage({super.key});

  @override
  ConsumerState<AuthRegisterPage> createState() => _AuthRegisterPageState();
}

class _AuthRegisterPageState extends ConsumerState<AuthRegisterPage> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  Uint8List? _photoBytes;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (picked == null) return;

      final original = await picked.readAsBytes();
      final decoded = img.decodeImage(original);
      if (decoded == null) {
        throw StateError('Format non pris en charge.');
      }
      final resized = decoded.width > 1024 || decoded.height > 1024
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? 1024 : null,
              height: decoded.height > decoded.width ? 1024 : null,
              interpolation: img.Interpolation.average,
            )
          : decoded;
      final compressed = Uint8List.fromList(
        img.encodeJpg(resized, quality: 82),
      );
      if (!mounted) return;
      setState(() => _photoBytes = compressed);
    } catch (_) {
      if (mounted) _showError('La photo n’a pas pu être préparée.');
    }
  }

  Future<void> _submit() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final password = _passwordController.text;

    if (firstName.isEmpty || lastName.isEmpty) {
      _showError('Renseigne ton prénom et ton nom.');
      return;
    }
    if (password.length < 8) {
      _showError('Le mot de passe doit contenir au moins 8 caractères.');
      return;
    }
    if (password != _confirmController.text) {
      _showError('Les deux mots de passe ne correspondent pas.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final username = await ref.read(authRepositoryProvider).registerAccount(
            firstName: firstName,
            lastName: lastName,
            password: password,
            photoJpegBytes: _photoBytes,
          );
      if (!mounted) return;
      await _showSuccessDialog(username);
      if (mounted) context.go('/auth/sign-in');
    } on FunctionException catch (error) {
      final details = error.details;
      final message =
          details is Map ? details['error']?.toString() : null;
      _showError(message ?? 'La création du compte a échoué.');
    } on StateError catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('La création du compte a échoué.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showSuccessDialog(String username) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Compte créé ! 🎉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Retiens bien ton identifiant :'),
            const SizedBox(height: 12),
            Center(
              child: SelectableText(
                username,
                style: Theme.of(dialogContext)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ton compte doit maintenant être validé par Samih. '
              'Tu pourras te connecter dès que c’est fait.',
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                          height: 90,
                          fit: BoxFit.contain,
                        ),
                      ),
                      Text(
                        'Créer mon compte',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ton identifiant sera généré automatiquement '
                        '(prénom + initiale du nom).',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 44,
                              backgroundImage: _photoBytes != null
                                  ? MemoryImage(_photoBytes!)
                                  : null,
                              child: _photoBytes == null
                                  ? const Icon(Icons.person_outline, size: 40)
                                  : null,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Material(
                                shape: const CircleBorder(),
                                color: Theme.of(context).colorScheme.primary,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _submitting ? null : _pickPhoto,
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.photo_camera_outlined,
                                      size: 18,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _firstNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Prénom',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _lastNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nom',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Mot de passe (8 caractères min.)',
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
                      const SizedBox(height: 16),
                      TextField(
                        controller: _confirmController,
                        obscureText: _obscurePassword,
                        decoration: const InputDecoration(
                          labelText: 'Confirme ton mot de passe',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sports_soccer),
                        label: const Text('Créer mon compte'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => context.go('/auth/sign-in'),
                        child: const Text('J’ai déjà un compte — se connecter'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Après validation par Samih, tu pourras te connecter '
                        'avec ton identifiant et ton mot de passe.',
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
