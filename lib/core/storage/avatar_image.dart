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
/// fichier est alors un JPEG, quel qu'ait été son format d'entrée.
typedef PreparedAvatar = ({Uint8List bytes, bool reencoded});

/// Ramène une photo à la taille d'affichage et la réencode en JPEG.
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
    bytes: img.encodeJpg(resized, quality: avatarStorageJpegQuality),
    reencoded: true,
  );
}
