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

/// Photo détourée : un disque opaque sur fond transparent.
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

bool _isPng(Uint8List bytes) =>
    bytes.length > 4 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47;

void main() {
  group('encodeAvatar', () {
    test('une photo opaque part en JPEG', () {
      final image = img.decodeImage(_photo(64, 64))!;
      final bytes = encodeAvatar(image);
      expect(bytes.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
    });

    test('une photo détourée part en PNG et garde sa transparence', () {
      final image = img.decodeImage(_cutout(64))!;
      final bytes = encodeAvatar(image);

      expect(_isPng(bytes), isTrue);
      final decoded = img.decodeImage(bytes)!;
      expect(decoded.getPixel(0, 0).a, 0);
      expect(decoded.getPixel(32, 32).a, 255);
    });
  });

  test('unpremultiplyAlpha rend leur couleur aux pixels semi-transparents', () {
    final image = img.Image(width: 1, height: 1, numChannels: 4)
      // Rouge 200 à moitié transparent, tel que rawRgba le livre : 200 × 128
      // / 255 ≈ 100.
      ..setPixelRgba(0, 0, 100, 0, 0, 128);
    final pixel = unpremultiplyAlpha(image).getPixel(0, 0);
    expect(pixel.r, closeTo(199, 1));
    expect(pixel.a, 128);
  });

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

    test('une photo détourée trop grande reste transparente', () {
      final prepared = downscaleAvatar(_cutout(800));

      expect(prepared.reencoded, isTrue);
      expect(_isPng(prepared.bytes), isTrue);
      final decoded = img.decodeImage(prepared.bytes)!;
      expect(decoded.width, avatarStorageSide);
      expect(decoded.getPixel(0, 0).a, 0);
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
