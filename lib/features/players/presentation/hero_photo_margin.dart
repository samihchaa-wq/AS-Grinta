import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:as_grinta/core/storage/profile_photo_urls.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Part de la largeur de la photo, côté droit, que son dessin laisse vide.
///
/// Une photo détourée (fond transparent) ne remplit pas son carré : sur la
/// fiche joueur, le prénom paraissait alors plus loin de la photo que du
/// badge. Cette part permet de le recentrer sur ce qui se voit vraiment.
///
/// [rgba] contient les pixels de l'image, quatre octets par pixel. L'image
/// est supposée affichée en `BoxFit.cover` dans un carré, comme dans
/// `PlayerAvatar`. Renvoie 0 pour une photo pleine ou entièrement vide.
double photoClearRightShare(Uint8List rgba, int width, int height) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) return 0;
  // Un pixel compte à partir d'un quart d'opacité, et une colonne à partir
  // de quelques pixels : un cheveu ou un reste de détourage isolé ne doit
  // pas repousser le bord visible de la photo.
  const minAlpha = 64;
  final minPixels = (height * .02).ceil().clamp(1, height);
  var lastColumn = -1;
  for (var x = width - 1; x >= 0 && lastColumn < 0; x--) {
    var count = 0;
    for (var y = 0; y < height; y++) {
      if (rgba[(y * width + x) * 4 + 3] >= minAlpha && ++count >= minPixels) {
        lastColumn = x;
        break;
      }
    }
  }
  if (lastColumn < 0) return 0;
  // En `cover`, l'image déborde du carré sur son côté le plus long.
  final scale = 1 / (width < height ? width : height);
  final offset = (1 - width * scale) / 2;
  final visibleRight = (offset + (lastColumn + 1) * scale).clamp(0.0, 1.0);
  return 1 - visibleRight;
}

/// [photoClearRightShare] de la photo d'un joueur, lue dans le cache
/// d'images déjà rempli par son avatar.
///
/// `null` quand la photo s'affiche mais ne peut pas être lue pixel par pixel
/// (élément HTML de secours sur le Web) : son carré est alors pris tel quel.
/// En erreur quand la photo ne se charge pas : l'avatar montre alors ses
/// initiales.
final heroPhotoClearRightProvider =
    FutureProvider.autoDispose.family<double?, String>((ref, photoUrl) async {
  final url = await ProfilePhotoUrlCache.instance.resolve(photoUrl);
  if (url == null) throw StateError('Photo indisponible');
  // Même image que celle de l'avatar : elle sort du cache sans nouveau
  // téléchargement.
  final image = await _decode(
    NetworkImage(
      url,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
    ),
  );
  if (image == null) return null;
  try {
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (pixels == null) return null;
    return photoClearRightShare(
      pixels.buffer.asUint8List(),
      image.width,
      image.height,
    );
  } finally {
    image.dispose();
  }
});

Future<ui.Image?> _decode(ImageProvider provider) {
  final completer = Completer<ui.Image?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      if (completer.isCompleted) return;
      ui.Image? image;
      try {
        image = info.image;
      } catch (_) {
        // Sur le Web, une image affichée par un élément HTML n'expose pas
        // ses pixels.
        image = null;
      }
      completer.complete(image);
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  return completer.future;
}
