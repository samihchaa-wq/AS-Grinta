import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Feuille d'actions sur l'adresse d'un match : ouvrir dans une appli GPS,
/// copier ou partager.
Future<void> showMatchAddressSheet(BuildContext context, String address) {
  final messenger = ScaffoldMessenger.of(context);
  final trimmed = address.trim();

  Future<void> openMaps(BuildContext sheetContext) async {
    final query = Uri.encodeComponent(trimmed);
    final isApple = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (sheetContext.mounted) Navigator.pop(sheetContext);

    if (isApple) {
      // En PWA iOS, ouvrir un NOUVEL onglet (_blank) laisse un onglet vide dans
      // le navigateur intégré. On navigue donc la fenêtre courante (_self) vers
      // un lien Apple Plans : iOS l'intercepte et ouvre l'app native, la PWA
      // reste en place.
      await launchUrl(
        Uri.parse('https://maps.apple.com/?q=$query'),
        webOnlyWindowName: '_self',
      );
      return;
    }

    final ok = await launchUrl(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$query'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir la carte.')),
      );
    }
  }

  Future<void> copy(BuildContext sheetContext) async {
    await Clipboard.setData(ClipboardData(text: trimmed));
    if (sheetContext.mounted) Navigator.pop(sheetContext);
    messenger.showSnackBar(const SnackBar(content: Text('Adresse copiée.')));
  }

  Future<void> share(BuildContext sheetContext) async {
    if (sheetContext.mounted) Navigator.pop(sheetContext);
    await Share.share(trimmed);
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.place_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Adresse du match',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              trimmed,
              style: Theme.of(sheetContext).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => openMaps(sheetContext),
              icon: const Icon(Icons.directions_outlined),
              label: const Text('Ouvrir dans le GPS'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => copy(sheetContext),
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copier l’adresse'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => share(sheetContext),
              icon: const Icon(Icons.ios_share_outlined),
              label: const Text('Partager'),
            ),
          ],
        ),
      ),
    ),
  );
}
