import 'dart:typed_data';

import 'package:as_grinta/core/storage/avatar_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _photo(int width, int height) {
  final image = img.Image(width: width, height: height);
  // Un dégradé bruité : une image unie se compresserait si bien qu'elle ne
  // dirait rien du poids réel d'une photo.
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
  group('downscaleAvatar', () {
    test('une photo trop grande est ramenée à la taille de stockage', () {
      final source = _photo(800, 800);
      final prepared = downscaleAvatar(source);

      expect(prepared.reencoded, isTrue);
      final decoded = img.decodeImage(prepared.bytes)!;
      expect(decoded.width, avatarStorageSide);
      expect(decoded.height, avatarStorageSide);
      expect(prepared.bytes.length, lessThan(source.length));
    });

    test('un portrait garde ses proportions', () {
      final prepared = downscaleAvatar(_photo(600, 900));

      expect(prepared.reencoded, isTrue);
      final decoded = img.decodeImage(prepared.bytes)!;
      expect(decoded.height, avatarStorageSide);
      expect(decoded.width, lessThan(avatarStorageSide));
    });

    test('une photo déjà assez petite n’est pas réencodée', () {
      final source = _photo(200, 200);
      final prepared = downscaleAvatar(source);

      expect(prepared.reencoded, isFalse);
      expect(prepared.bytes, same(source));
    });

    test('une photo à la taille exacte n’est pas réencodée', () {
      final source = _photo(avatarStorageSide, avatarStorageSide);
      final prepared = downscaleAvatar(source);

      expect(prepared.reencoded, isFalse);
      expect(prepared.bytes, same(source));
    });

    test('des octets illisibles sont laissés à la validation d’envoi', () {
      final source = Uint8List.fromList([1, 2, 3, 4]);
      final prepared = downscaleAvatar(source);

      expect(prepared.reencoded, isFalse);
      expect(prepared.bytes, same(source));
    });
  });

  test(
    'la taille de stockage couvre le plus grand avatar de l’application',
    () {
      // Le plus grand avatar est celui de la fiche de profil : 76 points. Sur
      // l'écran le plus dense du marché, environ 3,5 pixels par point.
      expect(avatarStorageSide, greaterThanOrEqualTo((76 * 3.5).ceil()));
    },
  );
}
