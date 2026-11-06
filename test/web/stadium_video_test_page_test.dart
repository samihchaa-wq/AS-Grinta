import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la page de test lit les mêmes vidéos que l’appli', () {
    final app = File(
      'lib/features/sports_management/presentation/widgets/'
      'composition_presentation.dart',
    ).readAsStringSync();
    final page = File('web/test-video.js').readAsStringSync();
    final html = File('web/test-video.html').readAsStringSync();

    for (final asset in [
      'assets/composition/stade.mp4',
      'assets/composition/stade-720.mp4',
    ]) {
      expect(app, contains("'$asset'"));
      expect(File(asset).existsSync(), isTrue, reason: asset);
      // Flutter publie les assets sous « assets/ ».
      expect(page, contains("'assets/$asset'"));
    }
    // Mêmes réglages que l'appli : vidéo muette, lue dans la page.
    expect(html, contains('muted playsinline webkit-playsinline'));
    // La page autorise la lecture depuis la mémoire du téléphone (blob:).
    expect(html, contains("media-src 'self' blob:"));
  });
}
