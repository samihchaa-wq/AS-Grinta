import 'package:flutter/material.dart';

/// Confirmation avant d'enregistrer un remplacement (échange banc/terrain).
/// Retourne `true` si le coach valide.
Future<bool> confirmMatchLiveSubstitution(
  BuildContext context, {
  required String playerInName,
  required String playerOutName,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Valider le remplacement'),
      content: Text('$playerInName entre, $playerOutName sort.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Valider'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
