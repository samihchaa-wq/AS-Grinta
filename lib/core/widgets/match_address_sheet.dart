import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

enum MatchGpsApp {
  plans,
  googleMaps,
  waze,
}

List<MatchGpsApp> matchGpsAppsForPlatform(TargetPlatform platform) {
  final isApple =
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  return [
    if (isApple) MatchGpsApp.plans,
    MatchGpsApp.googleMaps,
    MatchGpsApp.waze,
  ];
}

Uri matchGpsUri(MatchGpsApp app, String address) {
  final destination = address.trim();

  return switch (app) {
    MatchGpsApp.plans => Uri.https(
        'maps.apple.com',
        '/',
        {'daddr': destination},
      ),
    MatchGpsApp.googleMaps => Uri.https(
        'www.google.com',
        '/maps/dir/',
        {
          'api': '1',
          'destination': destination,
          'dir_action': 'navigate',
        },
      ),
    MatchGpsApp.waze => Uri.https(
        'www.waze.com',
        '/ul',
        {
          'q': destination,
          'navigate': 'yes',
        },
      ),
  };
}

String _gpsAppLabel(MatchGpsApp app) {
  return switch (app) {
    MatchGpsApp.plans => 'Plans',
    MatchGpsApp.googleMaps => 'Google Maps',
    MatchGpsApp.waze => 'Waze',
  };
}

IconData _gpsAppIcon(MatchGpsApp app) {
  return switch (app) {
    MatchGpsApp.plans => Icons.map_outlined,
    MatchGpsApp.googleMaps => Icons.public_outlined,
    MatchGpsApp.waze => Icons.navigation_outlined,
  };
}

Future<MatchGpsApp?> _showGpsPicker(BuildContext context) {
  final apps = matchGpsAppsForPlatform(defaultTargetPlatform);

  return showModalBottomSheet<MatchGpsApp>(
    context: context,
    showDragHandle: true,
    builder: (pickerContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Choisir le GPS',
                    style: Theme.of(pickerContext)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...apps.map(
              (app) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_gpsAppIcon(app)),
                title: Text(
                  _gpsAppLabel(app),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(pickerContext, app),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Feuille d'actions sur l'adresse d'un match : ouvrir dans une appli GPS,
/// copier ou partager.
Future<void> showMatchAddressSheet(BuildContext context, String address) {
  final messenger = ScaffoldMessenger.of(context);
  final trimmed = address.trim();

  Future<void> openMaps(BuildContext sheetContext) async {
    final selectedApp = await _showGpsPicker(sheetContext);
    if (selectedApp == null || !sheetContext.mounted) return;

    Navigator.pop(sheetContext);
    final uri = matchGpsUri(selectedApp, trimmed);
    final ok = kIsWeb
        ? await launchUrl(uri, webOnlyWindowName: '_self')
        : await launchUrl(uri, mode: LaunchMode.externalApplication);

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
              label: const Text('Choisir le GPS'),
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
