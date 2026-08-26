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
