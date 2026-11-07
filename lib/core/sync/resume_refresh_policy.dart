/// Retour au premier plan : quand faut-il tout recharger ?
///
/// Un passage par une autre application (lire un message, répondre à un
/// appel) ne change rien aux données du club. Recharger profil, calendrier
/// complet et une vingtaine de blocs à chaque retour faisait clignoter les
/// écrans et coûtait une quinzaine de requêtes.
///
/// Après une courte absence, l'application se contente de relire le petit
/// signal de synchronisation : s'il a bougé pendant l'absence, le
/// rafraîchissement ciblé habituel se déclenche
/// (`sharedDataSyncListenerProvider`). Après une longue absence, le retour
/// compte comme une ouverture et tout est rechargé, comme avant.
const Duration appResumeFullRefreshAfter = Duration(minutes: 30);

/// `true` si le retour au premier plan doit tout recharger. Une durée
/// inconnue est traitée comme une longue absence, par prudence.
bool shouldFullyRefreshOnResume(Duration? awayFor) {
  return awayFor == null || awayFor >= appResumeFullRefreshAfter;
}
