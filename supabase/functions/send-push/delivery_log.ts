/// Types acceptés par le journal de livraison pour les envois à contenu
/// préparé (kind « custom »). Ils doublent la contrainte
/// push_delivery_log_kind_check : un type absent ici est journalisé comme
/// « custom » plutôt que de faire échouer l'écriture du journal.
export const TARGETED_DELIVERY_LOG_KINDS: ReadonlySet<string> = new Set([
  "convocation_promoted",
  "convocation_demoted",
  "composition_published",
  "motm_result_general",
  "motm_result_winner",
  "badge_unlocked",
]);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// Type sous lequel journaliser un envoi ciblé : celui transmis par la base
/// s'il est connu, sinon « custom » (message libre d'un administrateur,
/// notification de test, changement de disponibilité…).
export function targetedDeliveryLogKind(value: unknown): string {
  return typeof value === "string" && TARGETED_DELIVERY_LOG_KINDS.has(value)
    ? value
    : "custom";
}

/// Match rattaché à un envoi ciblé, ou null (badges, message libre). Une
/// valeur qui n'est pas un identifiant de match valide est ignorée : le
/// journal ne doit jamais refuser une ligne pour un match mal formé.
export function optionalMatchId(value: unknown): string | null {
  return typeof value === "string" && UUID.test(value.trim())
    ? value.trim().toLowerCase()
    : null;
}
