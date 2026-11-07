import 'dart:typed_data';

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
/// (voir `encodeAvatar` dans avatar_image_codec.dart). Son format se lit dans sa signature.
typedef PreparedAvatar = ({Uint8List bytes, bool reencoded});

// Les traitements d'image (lecture, redimensionnement, encodage JPEG/PNG) sont
// dans avatar_image_codec.dart, chargé seulement au moment de traiter une
// photo : la bibliothèque d'images pèse environ 150 Ko et ne sert qu'aux
// envois de photos.
