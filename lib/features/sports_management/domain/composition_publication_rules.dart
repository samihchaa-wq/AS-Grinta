// Règle d'avertissement avant la mise en ligne d'une composition.
//
// Le serveur envoie « La composition est en ligne » aux joueurs convoqués à la
// première mise en ligne de la feuille, et à celle-là seulement. Ce message
// part sans retour possible : l'écran doit prévenir l'administrateur avant,
// et seulement quand l'envoi aura réellement lieu — sinon l'avertissement
// devient un réflexe qu'on valide sans lire.

/// Vrai quand enregistrer la composition préviendra les joueurs convoqués.
///
/// [alreadyPublished] : une feuille a déjà été mise en ligne pour ce match. Les
/// retouches suivantes ne préviennent personne.
///
/// [sheetNamesPlayers] : la feuille enregistrée désignera au moins un joueur.
/// Un match entre nous ne prévient personne tant que les deux équipes sont
/// vides ; une feuille de match classique, elle, désigne toujours quelqu'un.
///
/// [postMatch] : après le coup d'envoi, la feuille n'est plus une annonce mais
/// un compte rendu, et n'envoie rien.
bool compositionPublicationWillNotify({
  required bool alreadyPublished,
  required bool sheetNamesPlayers,
  required bool postMatch,
}) {
  if (postMatch || alreadyPublished) return false;
  return sheetNamesPlayers;
}
