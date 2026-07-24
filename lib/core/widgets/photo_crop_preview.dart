import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Montre un aperçu du carré tel qu'il apparaîtra sur la composition (mêmes
/// coins arrondis, même recadrage « cover ») posé sur un fond vert imitant le
/// terrain, afin de juger notamment d'un éventuel fond transparent.
///
/// Renvoie `true` si l'utilisateur confirme, `false` sinon.
Future<bool> confirmCompositionPhoto(
  BuildContext context,
  Uint8List bytes,
) async {
  const double previewSize = 132;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Aperçu sur la compo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Voici le carré qui apparaîtra sur le terrain.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF174936),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF6DAD8B)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(previewSize * 0.28),
              child: Image.memory(
                bytes,
                width: previewSize,
                height: previewSize,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Utiliser cette photo'),
        ),
      ],
    ),
  );
  return result ?? false;
}
