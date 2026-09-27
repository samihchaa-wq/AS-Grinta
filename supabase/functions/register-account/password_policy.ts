// Règle de mot de passe de l'inscription publique, identique à
// lib/core/security/password_policy.dart.
//
// Seules les lettres non accentuées comptent pour la majuscule et la
// minuscule, comme dans la règle de caractères de Supabase : l'ancienne plage
// `À-Ÿ` contenait aussi les minuscules accentuées, et « aaaaaaaaaaé1 »
// passait pour avoir une majuscule. Les lettres accentuées restent autorisées.

export const MIN_PASSWORD_LENGTH = 12;
export const MAX_PASSWORD_LENGTH = 72;

export function validatePassword(password: string): string | null {
  if (
    password.length < MIN_PASSWORD_LENGTH ||
    password.length > MAX_PASSWORD_LENGTH
  ) {
    return `Le mot de passe doit contenir entre ${MIN_PASSWORD_LENGTH} et ${MAX_PASSWORD_LENGTH} caractères.`;
  }
  if (!/[a-z]/.test(password)) {
    return "Ajoute au moins une minuscule de a à z.";
  }
  if (!/[A-Z]/.test(password)) {
    return "Ajoute au moins une majuscule de A à Z.";
  }
  if (!/[0-9]/.test(password)) {
    return "Ajoute au moins un chiffre.";
  }
  return null;
}
