import 'dart:typed_data';

import 'package:as_grinta/core/storage/avatar_image.dart';
import 'package:as_grinta/core/widgets/photo_crop_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _photo(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        (x * 7 + y * 3) % 256,
        (x * 3 + y * 11) % 256,
        (x * 13 + y * 5) % 256,
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}

void main() {
  testWidgets(
    'la photo recadrée est exportée à la taille de stockage, pas plus grande',
    (tester) async {
      Uint8List? exported;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                exported = await cropProfilePhoto(context, _photo(800, 800));
              },
              child: const Text('recadrer'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('recadrer'));
      await tester.pumpAndSettle();
      // Le décodage et l'encodage sont de vraies opérations asynchrones : elles
      // ne se terminent pas sur l'horloge simulée des tests.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('Utiliser cette photo'));
        for (var i = 0; i < 40 && exported == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();

      expect(exported, isNotNull);
      final decoded = img.decodeImage(exported!)!;
      expect(decoded.width, avatarStorageSide);
      expect(decoded.height, avatarStorageSide);
    },
  );
}
