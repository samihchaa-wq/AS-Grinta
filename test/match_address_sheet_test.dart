import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GPS choices follow the target platform', () {
    expect(matchGpsAppsForPlatform(TargetPlatform.iOS), const [
      MatchGpsApp.plans,
      MatchGpsApp.googleMaps,
      MatchGpsApp.waze,
    ]);
    expect(matchGpsAppsForPlatform(TargetPlatform.macOS), const [
      MatchGpsApp.plans,
      MatchGpsApp.googleMaps,
      MatchGpsApp.waze,
    ]);
    expect(matchGpsAppsForPlatform(TargetPlatform.android), const [
      MatchGpsApp.googleMaps,
      MatchGpsApp.waze,
    ]);
  });

  test('GPS URLs open navigation to the trimmed match address', () {
    const address = '17 Chemin de la Saudrune, 31100 Toulouse, France';

    final plans = matchGpsUri(MatchGpsApp.plans, '  $address  ');
    expect(plans.scheme, 'https');
    expect(plans.host, 'maps.apple.com');
    expect(plans.path, '/');
    expect(plans.queryParameters, {'daddr': address});

    final google = matchGpsUri(MatchGpsApp.googleMaps, '  $address  ');
    expect(google.scheme, 'https');
    expect(google.host, 'www.google.com');
    expect(google.path, '/maps/dir/');
    expect(google.queryParameters, {
      'api': '1',
      'destination': address,
      'dir_action': 'navigate',
    });

    final waze = matchGpsUri(MatchGpsApp.waze, '  $address  ');
    expect(waze.scheme, 'https');
    expect(waze.host, 'www.waze.com');
    expect(waze.path, '/ul');
    expect(waze.queryParameters, {'q': address, 'navigate': 'yes'});
  });

  testWidgets('Apple platforms offer Plans, Google Maps and Waze', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(_harness());

      await tester.tap(find.text('Adresse'));
      await tester.pumpAndSettle();
      expect(find.text('Choisir le GPS'), findsOneWidget);

      await tester.tap(find.text('Choisir le GPS'));
      await tester.pumpAndSettle();

      expect(find.text('Plans'), findsOneWidget);
      expect(find.text('Google Maps'), findsOneWidget);
      expect(find.text('Waze'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('non-Apple platforms offer Google Maps and Waze', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(_harness());

      await tester.tap(find.text('Adresse'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choisir le GPS'));
      await tester.pumpAndSettle();

      expect(find.text('Plans'), findsNothing);
      expect(find.text('Google Maps'), findsOneWidget);
      expect(find.text('Waze'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Widget _harness() {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              await showMatchAddressSheet(
                context,
                '17 Chemin de la Saudrune, 31100 Toulouse, France',
              );
            },
            child: const Text('Adresse'),
          ),
        ),
      ),
    ),
  );
}
