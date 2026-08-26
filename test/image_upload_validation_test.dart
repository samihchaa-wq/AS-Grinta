import 'dart:typed_data';

import 'package:as_grinta/core/storage/image_mime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateImageUpload', () {
    test('détecte un JPEG sans faire confiance à l’extension', () {
      final result = validateImageUpload(
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00]),
        fileExt: 'png',
      );

      expect(result.extension, 'jpg');
      expect(result.mimeType, 'image/jpeg');
    });

    test('détecte un PNG', () {
      final result = validateImageUpload(
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        fileExt: 'png',
      );

      expect(result.extension, 'png');
      expect(result.mimeType, 'image/png');
    });

    test('détecte un WebP', () {
      final result = validateImageUpload(
        Uint8List.fromList('RIFF0000WEBP'.codeUnits),
        fileExt: 'webp',
      );

      expect(result.extension, 'webp');
      expect(result.mimeType, 'image/webp');
    });

    test('refuse un contenu qui n’est pas une image autorisée', () {
      expect(
        () => validateImageUpload(
          Uint8List.fromList('faux fichier'.codeUnits),
          fileExt: 'jpg',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('refuse une image vide', () {
      expect(
        () => validateImageUpload(Uint8List(0), fileExt: 'jpg'),
        throwsA(isA<FormatException>()),
      );
    });

    test('refuse une image supérieure à 5 Mo', () {
      final oversized = Uint8List(maxImageUploadBytes + 1)
        ..setAll(0, const [0xFF, 0xD8, 0xFF]);

      expect(
        () => validateImageUpload(oversized, fileExt: 'jpg'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
