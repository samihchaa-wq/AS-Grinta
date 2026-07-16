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
