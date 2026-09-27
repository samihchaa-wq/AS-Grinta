abstract final class PasswordPolicy {
  static const int minLength = 12;
  static const int maxLength = 72;

  static String? validate(String password) {
    if (password.length < minLength || password.length > maxLength) {
      return 'Le mot de passe doit contenir entre $minLength et $maxLength caractères.';
    }
    // Seules les lettres non accentuées comptent, comme dans la règle de
    // caractères de Supabase : l'ancienne plage `À-Ÿ` contenait aussi les
    // minuscules accentuées, et « aaaaaaaaaaé1 » passait pour avoir une
    // majuscule. Les lettres accentuées restent autorisées.
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Ajoute au moins une minuscule de a à z.';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Ajoute au moins une majuscule de A à Z.';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Ajoute au moins un chiffre.';
    }
    return null;
  }

  static bool isValid(String password) => validate(password) == null;

  static const String helperText =
      '12 caractères minimum, avec une majuscule (A à Z), une minuscule '
      '(a à z) et un chiffre.';
}
