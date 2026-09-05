// Règles d'enregistrement de l'effectif.
//
// L'effectif n'a plus d'étape de validation : chaque décision est écrite dès
// qu'elle est prise, et la composition ne l'attend plus. Le bouton
// « Enregistrer » a disparu, la Compo est ouverte en permanence.
//
// Deux règles subsistent, et elles sont ici parce que le serveur les impose :
// on n'écrit rien après le verrou du coup d'envoi, et la composition ne peut
// être publiée que si l'effectif du match existe déjà côté serveur.

/// Vrai quand une décision d'effectif peut partir vers le serveur maintenant.
///
/// [saving] évite d'empiler deux écritures : la suivante est reprogrammée à la
/// fin de celle en cours.
bool canSaveEffectifNow({
  required bool busy,
  required bool locked,
  required bool postMatch,
  required bool saving,
}) {
  if (busy || locked || postMatch || saving) return false;
  return true;
}

/// Vrai quand l'effectif du match n'a jamais été écrit côté serveur.
///
/// Dans ce cas l'écran l'écrit lui-même au chargement, avec les convocations
/// que le serveur a déjà calculées : sans cette écriture, la composition
/// resterait impubliable alors que plus rien ne la bloque à l'écran.
bool needsInitialEffectifWrite({
  required bool convocationPublished,
  required bool busy,
  required bool locked,
  required bool postMatch,
}) {
  if (convocationPublished || busy || locked || postMatch) return false;
  return true;
}

/// Vrai quand faire passer un joueur dans l'effectif lui enverra une
/// notification « Tu es convoqué ».
///
/// Le serveur prévient le joueur au moment précis où sa convocation passe de
/// « liste d'attente » à « convoqué », sur un match dont l'effectif existe déjà.
/// Comme l'effectif s'écrit maintenant tout seul, ce geste part sans retour
/// possible : l'écran doit donc demander confirmation avant, et seulement dans
/// ce cas-là. Un joueur noté absent ou sans réponse que l'admin convoque ne
/// déclenche rien, pas plus qu'un mouvement dans l'autre sens.
bool convocationPushWillFire({
  required bool wasWaitlisted,
  required bool becomesConvoked,
  required bool effectifWritten,
  required bool postMatch,
}) {
  if (postMatch || !effectifWritten) return false;
  return wasWaitlisted && becomesConvoked;
}
