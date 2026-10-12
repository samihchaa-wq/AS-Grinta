import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Côté, en pixels, auquel une photo de joueur est stockée.
///
/// Le plus grand avatar de l'application fait 76 points (la fiche de profil).
/// Sur l'écran le plus dense du marché (environ 3,5 pixels par point), il faut
/// donc 266 pixels : 320 laisse de la marge sans jamais rien télécharger
/// d'inutile. Les photos étaient stockées en 720 pixels, soit près de cinq
/// fois plus de données pour un résultat identique à l'œil.
const int avatarStorageSide = 320;

/// Qualité JPEG des photos de joueurs.
const int avatarStorageJpegQuality = 85;

/// Photo prête à être envoyée, et si elle a dû être réencodée.
///
/// [reencoded] vaut `true` quand les octets ne sont plus ceux d'origine : le
/// fichier est alors un JPEG, ou un PNG s'il garde des zones transparentes
/// (voir [encodeAvatar]). Son format se lit dans sa signature.
typedef PreparedAvatar = ({Uint8List bytes, bool reencoded});

/// Encode une photo de joueur prête à stocker.
///
/// JPEG par défaut, pour le poids. Mais le JPEG n'a pas de transparence : une
/// photo détourée (fond transparent) y prenait un fond blanc ou noir. Dès
/// qu'un pixel n'est pas totalement opaque, la photo part donc en PNG, qui
/// garde la transparence ; le terrain ou la carte apparaît alors derrière.
Uint8List encodeAvatar(img.Image image) {
  if (_hasTransparency(image)) return img.encodePng(image, level: 9);
  return img.encodeJpg(image, quality: avatarStorageJpegQuality);
}

/// Rend leur vraie couleur aux pixels semi-transparents d'une image lue avec
/// `ImageByteFormat.rawRgba`, dont les couleurs sont multipliées par
/// l'opacité. Écrits tels quels dans un PNG, les bords d'une photo détourée
/// ressortiraient assombris. Modifie [image] et la renvoie.
img.Image unpremultiplyAlpha(img.Image image) {
  final max = image.maxChannelValue;
  for (final pixel in image) {
    final a = pixel.a;
    if (a <= 0 || a >= max) continue;
    pixel
      ..r = (pixel.r * max / a).round().clamp(0, max)
      ..g = (pixel.g * max / a).round().clamp(0, max)
      ..b = (pixel.b * max / a).round().clamp(0, max);
  }
  return image;
}

bool _hasTransparency(img.Image image) {
  if (!image.hasAlpha) return false;
  final opaque = image.maxChannelValue;
  for (final pixel in image) {
    if (pixel.a < opaque) return true;
  }
  return false;
}

/// Ramène une photo à la taille d'affichage et la réencode (voir
/// [encodeAvatar]).
///
/// Utilisé pour les envois qui ne passent pas par le recadrage (les invités) :
/// la photo arrive alors telle que la galerie l'a fournie, jusqu'à 800 pixels
/// de côté. Une image déjà plus petite que la cible est renvoyée telle quelle,
/// pour ne pas la réencoder — donc la dégrader — sans rien gagner. Une image
/// illisible l'est aussi : la validation d'envoi reste seule juge du refus.
PreparedAvatar downscaleAvatar(Uint8List bytes) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    // Un fichier tronqué ou trompeur fait lever les décodeurs. Le redimension-
    // nement n'est pas le bon endroit pour refuser un envoi : on laisse passer
    // les octets, la validation d'envoi rendra un message clair.
    return (bytes: bytes, reencoded: false);
  }
  if (decoded == null) return (bytes: bytes, reencoded: false);
  if (decoded.width <= avatarStorageSide &&
      decoded.height <= avatarStorageSide) {
    return (bytes: bytes, reencoded: false);
  }
  final landscape = decoded.width >= decoded.height;
  final resized = img.copyResize(
    decoded,
    width: landscape ? avatarStorageSide : null,
    height: landscape ? null : avatarStorageSide,
    interpolation: img.Interpolation.cubic,
  );
  return (
    bytes: encodeAvatar(resized),
    reencoded: true,
  );
}
