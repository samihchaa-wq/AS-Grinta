/// Règles d'activation du bouton « Enregistrer » de l'effectif.
///
/// L'onglet Compo exige un effectif publié. Tant que la publication n'a pas eu
/// lieu — ou qu'il reste des changements non publiés — l'admin doit pouvoir
/// enregistrer, même sans avoir rien modifié depuis le chargement de l'écran.
/// Sans cette règle, un effectif jamais publié laissait l'admin coincé : la
/// Compo réclamait une validation que le bouton, grisé, refusait de faire.
bool canPersistEffectif({
  required bool busy,
  required bool locked,
  required bool dirty,
  required bool readyForComposition,
}) {
  if (busy || locked) return false;
  return dirty || !readyForComposition;
}
