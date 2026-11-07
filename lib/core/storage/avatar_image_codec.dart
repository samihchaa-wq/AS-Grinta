import 'dart:typed_data';

import 'package:as_grinta/core/storage/avatar_image.dart';
import 'package:image/image.dart' as img;

// Traitements d'image des envois de photos. Ce fichier est importé en
// différé (`deferred as`) par les écrans qui s'en servent : la bibliothèque
// d'images n'est téléchargée qu'au moment de traiter une photo, pas à
// l'ouverture de l'application.

/// Photo recadrée prête à stocker, depuis les pixels lus avec
/// `ImageByteFormat.rawRgba` (couleurs multipliées par l'opacité).
Uint8List encodeAvatarFromRawRgba(ByteData data, int width, int height) {
  final raw = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: data.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return encodeAvatar(unpremultiplyAlpha(raw));
}

/// JPEG depuis les pixels lus avec `ImageByteFormat.rawRgba` (image opaque).
Uint8List encodeJpegFromRawRgba(
  ByteData data,
  int width,
  int height, {
  required int quality,
}) {
  final raw = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: data.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(raw, quality: quality);
}

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
    decoded = _decodeAcceptedFormat(bytes);
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

/// Lit une photo dans l'un des seuls formats acceptés à l'envoi (JPEG, PNG,
/// WebP, voir `validateImageUpload`).
///
/// `img.decodeImage` reconnaît une quinzaine de formats (TIFF, PSD, EXR…) et
/// embarquait tous leurs lecteurs dans le programme téléchargé par chaque
/// joueur, pour des fichiers que l'envoi refuse de toute façon. Un format non
/// reconnu rend `null` : les octets sont alors laissés à la validation.
img.Image? _decodeAcceptedFormat(Uint8List bytes) {
  if (_startsWith(bytes, const [0xFF, 0xD8, 0xFF])) {
    return img.decodeJpg(bytes);
  }
  if (_startsWith(bytes, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A])) {
    return img.decodePng(bytes);
  }
  if (bytes.length >= 12 &&
      _startsWith(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return img.decodeWebP(bytes);
  }
  return null;
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}
