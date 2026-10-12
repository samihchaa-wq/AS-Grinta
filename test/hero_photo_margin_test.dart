import 'dart:typed_data';

import 'package:as_grinta/features/players/presentation/hero_photo_margin.dart';
import 'package:flutter_test/flutter_test.dart';

/// Image RGBA dont seules les colonnes [from] à [to] (incluses) sont opaques.
Uint8List _image(int width, int height, {int from = 0, int? to}) {
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = from; x <= (to ?? width - 1); x++) {
      pixels[(y * width + x) * 4 + 3] = 255;
    }
  }
  return pixels;
}

void main() {
  test('une photo pleine ne laisse rien de vide', () {
    expect(photoClearRightShare(_image(10, 10), 10, 10), 0);
  });

  test('une photo détourée laisse vide la droite de son carré', () {
    expect(
      photoClearRightShare(_image(10, 10, from: 2, to: 5), 10, 10),
      closeTo(.4, 1e-9),
    );
  });

  test('quelques pixels isolés ne repoussent pas le bord visible', () {
    final pixels = _image(100, 100, to: 49);
    // Un reste de détourage d'un pixel, tout à droite.
    pixels[(50 * 100 + 99) * 4 + 3] = 255;
    expect(photoClearRightShare(pixels, 100, 100), closeTo(.5, 1e-9));
  });

  test('une image plus large que haute est rognée comme à l’écran', () {
    // Affichée en `cover`, seule sa moitié centrale entre dans le carré.
    expect(
      photoClearRightShare(_image(20, 10, to: 9), 20, 10),
      closeTo(.5, 1e-9),
    );
    expect(photoClearRightShare(_image(20, 10, to: 14), 20, 10), 0);
  });

  test('une image vide ou illisible ne déplace rien', () {
    expect(photoClearRightShare(Uint8List(400), 10, 10), 0);
    expect(photoClearRightShare(Uint8List(0), 10, 10), 0);
  });
}
