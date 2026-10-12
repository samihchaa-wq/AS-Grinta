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

Uint8List _cutout(int side) {
  final image = img.Image(width: side, height: side, numChannels: 4);
  final center = side / 2;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final inside = (x - center) * (x - center) + (y - center) * (y - center) <
          (side / 3) * (side / 3);
      image.setPixelRgba(x, y, 200, 40, 40, inside ? 255 : 0);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Future<Uint8List?> _crop(WidgetTester tester, Uint8List source) async {
  Uint8List? exported;

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            exported = await cropProfilePhoto(context, source);
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
  return exported;
}

void main() {
  testWidgets(
    'une photo détourée garde sa transparence au lieu d’un fond blanc',
    (tester) async {
      final exported = await _crop(tester, _cutout(400));

      expect(exported, isNotNull);
      final decoded = img.decodeImage(exported!)!;
      expect(decoded.width, avatarStorageSide);
      final corner = decoded.getPixel(2, 2);
      expect(corner.a, 0);
      final middle =
          decoded.getPixel(avatarStorageSide ~/ 2, avatarStorageSide ~/ 2);
      expect(middle.a, 255);
      expect(middle.r, closeTo(200, 3));
    },
  );

  testWidgets(
    'la photo recadrée est exportée à la taille de stockage, pas plus grande',
    (tester) async {
      final exported = await _crop(tester, _photo(800, 800));

      expect(exported, isNotNull);
      // Une photo opaque reste en JPEG, plus léger qu'un PNG.
      expect(exported!.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
      final decoded = img.decodeImage(exported)!;
      expect(decoded.width, avatarStorageSide);
      expect(decoded.height, avatarStorageSide);
    },
  );
}
