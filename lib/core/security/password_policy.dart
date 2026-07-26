abstract final class PasswordPolicy {
  static const int minLength = 12;
  static const int maxLength = 72;

  static String? validate(String password) {
    if (password.length < minLength || password.length > maxLength) {
      return 'Le mot de passe doit contenir entre $minLength et $maxLength caractères.';
    }
    if (!RegExp(r'[a-zà-ÿ]').hasMatch(password)) {
      return 'Ajoute au moins une lettre minuscule.';
    }
    if (!RegExp(r'[A-ZÀ-Ÿ]').hasMatch(password)) {
      return 'Ajoute au moins une lettre majuscule.';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Ajoute au moins un chiffre.';
    }
    return null;
  }

  static bool isValid(String password) => validate(password) == null;

  static const String helperText =
      '12 caractères minimum, avec une majuscule, une minuscule et un chiffre.';
}
