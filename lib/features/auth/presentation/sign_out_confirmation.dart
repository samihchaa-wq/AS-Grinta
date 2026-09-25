import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Demande confirmation puis déconnecte l'utilisateur.
///
/// Partagé par le Profil et les Paramètres : les deux boutons « Se
/// déconnecter » posent la même question et agissent de la même façon. La
/// redirection vers l'écran de connexion reste portée par le routeur.
Future<void> confirmAndSignOut(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Se déconnecter ?'),
      content: const Text(
        'Tu devras te reconnecter pour accéder à l’application.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Se déconnecter'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await ref.read(authControllerProvider.notifier).signOut();
}
