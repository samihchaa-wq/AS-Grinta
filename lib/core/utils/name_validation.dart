/// Validation des noms de personne (prénom, nom, surnom).
///
/// On n'autorise que des lettres (accents compris), espaces, tirets et
/// apostrophes. Pas d'emoji, pas de chiffre, pas de symbole. La même règle
/// est appliquée côté serveur (fonction Edge `register-account` et trigger
/// `validate_profile_names`).
final RegExp _namePattern = RegExp(r"^[\p{L} '’-]+$", unicode: true);
final RegExp _hasLetter = RegExp(r'\p{L}', unicode: true);

bool isValidPersonName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  return _namePattern.hasMatch(trimmed) && _hasLetter.hasMatch(trimmed);
}

/// Message d'erreur unique, réutilisé partout.
const String personNameError = 'Ce champ ne doit contenir que des lettres '
    '(ni emoji, ni chiffre, ni symbole).';

final RegExp _nameWordStart = RegExp(r"(^|[ '’-])(\p{L})", unicode: true);

/// Met une majuscule à l'initiale de chaque partie d'un nom, sans toucher au
/// reste : « romain » devient « Romain », « jean-pierre » devient
/// « Jean-Pierre », mais « CHÂA » et « McDonald » restent tels quels.
///
/// Un prénom saisi en minuscules à l'inscription ne doit pas s'afficher ainsi
/// dans toute l'application ; en ne forçant que l'initiale, on ne défait pas
/// non plus une graphie voulue.
String capitalizePersonName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed.replaceAllMapped(
    _nameWordStart,
    (match) => '${match[1]}${match[2]!.toUpperCase()}',
  );
}

/// Prénom extrait d'un « Prénom Nom » complet. Règle unique réutilisée
/// partout où l'appli doit réduire un nom complet (import historique,
/// statistiques) au même format court que les écrans alimentés directement
/// par un profil (qui n'exposent déjà que le prénom).
String firstNameOf(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return fullName;
  return trimmed.split(RegExp(r'\s+')).first;
}

/// Première lettre du nom de famille, pour départager deux joueurs affichés
/// sous le même prénom (ex : « Julien C. » / « Julien D. »).
String? lastNameInitialOf(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  final lastName = parts.sublist(1).join(' ');
  return lastName.isEmpty ? null : lastName[0].toUpperCase();
}

/// Initiales affichées à la place d'une photo de profil, calculées sur le
/// seul nom affiché (surnom, ou prénom) : les deux premiers mots quand il y
/// en a plusieurs, sinon ses deux premières lettres ; « ? » s'il est vide.
///
/// Le nom de famille n'y entre plus : il donnait « LB » pour « Le Mur » en
/// mélangeant surnom et nom, et les mêmes initiales changeaient selon qu'un
/// écran connaissait ou non ce nom de famille.
String avatarInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return '?';
  if (words.length > 1) return '${words[0][0]}${words[1][0]}'.toUpperCase();
  final word = words.first;
  return (word.length >= 2 ? word.substring(0, 2) : word).toUpperCase();
}

/// Appellation d'un joueur ou d'un membre dans les statistiques : son vrai
/// prénom, suivi de l'initiale de son nom de famille seulement quand un
/// homonyme figure dans le même classement. Les surnoms restent réservés au
/// Calendrier.
String statisticsName(
  String firstName, {
  String? lastInitial,
  bool isHomonym = false,
}) {
  final name = firstName.trim();
  final initial = (lastInitial ?? '').trim();
  if (name.isEmpty) return initial.isEmpty ? '' : initial[0].toUpperCase();
  if (!isHomonym || initial.isEmpty) return name;
  return '$name ${initial[0].toUpperCase()}.';
}

const _accentFolding = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'á': 'a',
  'ã': 'a',
  'å': 'a',
  'ç': 'c',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'î': 'i',
  'ï': 'i',
  'í': 'i',
  'ì': 'i',
  'ñ': 'n',
  'ô': 'o',
  'ö': 'o',
  'ó': 'o',
  'ò': 'o',
  'õ': 'o',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ú': 'u',
  'ÿ': 'y',
  'ý': 'y',
  'œ': 'oe',
  'æ': 'ae',
};

/// Clé de tri alphabétique d'un nom : sans casse ni accents, pour que
/// « Élodie » se range avec les E et « zizou » avec « Zoé ».
String personNameSortKey(String name) {
  final buffer = StringBuffer();
  for (final char in name.trim().toLowerCase().split('')) {
    buffer.write(_accentFolding[char] ?? char);
  }
  return buffer.toString();
}
