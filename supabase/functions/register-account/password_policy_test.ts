import { validatePassword } from "./password_policy.ts";

function assertEquals<T>(actual: T, expected: T): void {
  if (!Object.is(actual, expected)) {
    throw new Error(`Expected ${String(expected)}, got ${String(actual)}`);
  }
}

Deno.test("accepte un mot de passe avec les trois catégories", () => {
  assertEquals(validatePassword("GrandePhrase2026"), null);
});

Deno.test("refuse une longueur hors limites", () => {
  assertEquals(
    validatePassword("Court2026A"),
    "Le mot de passe doit contenir entre 12 et 72 caractères.",
  );
  assertEquals(
    validatePassword(`${"A".repeat(72)}1a`),
    "Le mot de passe doit contenir entre 12 et 72 caractères.",
  );
});

Deno.test("une minuscule accentuée ne compte pas comme une majuscule", () => {
  assertEquals(
    validatePassword("aaaaaaaaaaé1"),
    "Ajoute au moins une majuscule de A à Z.",
  );
});

Deno.test("une majuscule accentuée ne compte pas comme une majuscule", () => {
  assertEquals(
    validatePassword("Écoledufoot2026"),
    "Ajoute au moins une majuscule de A à Z.",
  );
});

Deno.test("une minuscule accentuée ne compte pas comme une minuscule", () => {
  assertEquals(
    validatePassword("ÉCOLEDUFOOTé2026"),
    "Ajoute au moins une minuscule de a à z.",
  );
});

Deno.test("refuse un mot de passe sans chiffre", () => {
  assertEquals(
    validatePassword("GrandePhraseSolide"),
    "Ajoute au moins un chiffre.",
  );
});

Deno.test("les lettres accentuées restent autorisées", () => {
  assertEquals(validatePassword("ÉlèveDuFoot2026"), null);
});
