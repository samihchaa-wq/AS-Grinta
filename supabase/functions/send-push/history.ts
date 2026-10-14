/// Historique des notifications : chaque envoi du club est rangé pour chacun
/// de ses destinataires (public.internal_record_notification_history), même
/// sans téléphone abonné. La fonction rend le nombre de notifications non
/// lues de chacun, glissé dans la notification (app_badge) pour que l'icône
/// de l'application affiche le même chiffre que la cloche.
///
/// Le champ s'appelle app_badge et non badge : dans les options d'une
/// notification, badge désigne déjà l'image monochrome de la barre d'état.

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const KIND = /^[a-z][a-z0-9_]{0,63}$/;

/// Un envoi est rangé dans l'historique sauf s'il le refuse explicitement
/// (notifications d'essai : record_history = false).
export function shouldRecordHistory(body: { record_history?: unknown }): boolean {
  return body.record_history !== false;
}

/// Type rangé dans l'historique : celui transmis s'il est bien formé, sinon
/// « custom ».
export function historyKind(value: unknown): string {
  return typeof value === "string" && KIND.test(value) ? value : "custom";
}

/// Identifiants de profil valides et distincts : un identifiant mal formé
/// ferait échouer tout l'enregistrement.
export function profileIdList(values: unknown): string[] {
  if (!Array.isArray(values)) return [];
  const ids = new Set<string>();
  for (const value of values) {
    if (typeof value === "string" && UUID.test(value.trim())) {
      ids.add(value.trim().toLowerCase());
    }
  }
  return [...ids];
}

/// Destinataires de l'historique : la liste préparée par la base sans tenir
/// compte des téléphones. Une base plus ancienne ne la fournit pas ; on se
/// rabat alors sur les profils des téléphones abonnés.
export function historyRecipients(
  dispatch: { recipient_profile_ids?: unknown },
  subscriptions: { profile_id?: string }[],
): string[] {
  if (Array.isArray(dispatch.recipient_profile_ids)) {
    return profileIdList(dispatch.recipient_profile_ids);
  }
  return profileIdList(subscriptions.map((sub) => sub.profile_id));
}

/// Nombres de non-lues renvoyés par la base, par profil. Toute valeur qui
/// n'est pas un entier positif ou nul est ignorée.
export function unreadCounts(data: unknown): Map<string, number> {
  const counts = new Map<string, number>();
  if (!data || typeof data !== "object" || Array.isArray(data)) return counts;
  for (const [profileId, value] of Object.entries(data)) {
    if (Number.isInteger(value) && (value as number) >= 0) {
      counts.set(profileId.toLowerCase(), value as number);
    }
  }
  return counts;
}

/// Contenu envoyé à un téléphone : le contenu commun, plus le nombre de
/// non-lues de son propriétaire quand il est connu.
export function payloadForProfile(
  payload: Record<string, unknown>,
  profileId: string | undefined,
  unread: Map<string, number>,
): string {
  const count = profileId ? unread.get(profileId.toLowerCase()) : undefined;
  return JSON.stringify(
    count === undefined ? payload : { ...payload, app_badge: count },
  );
}

/// Texte d'un champ du contenu, ou chaîne vide.
export function payloadText(value: unknown): string {
  return typeof value === "string" ? value : "";
}
