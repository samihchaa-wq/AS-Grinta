/// Charte d'espacement commune à AS Grinta.
///
/// Principe : chaque bloc doit être séparé du suivant assez nettement pour
/// être lu comme un bloc. Ces constantes sont la source unique de vérité pour
/// les écrans principaux : toute évolution de densité doit partir d'ici afin
/// de rester cohérente dans toute l'application.
///
/// Règle de mise en page associée : regrouper les éléments dans un conteneur
/// qui porte l'espacement (`Column` + `spacing`, `separated`) plutôt que de
/// poser une marge sur chaque élément. L'espacement survit alors aux ajouts
/// et aux suppressions.
abstract final class AppSpacing {
  /// Marge latérale standard des écrans.
  static const double screenGutter = 16;

  /// Marge latérale du cockpit Live, où la largeur du terrain est prioritaire.
  static const double liveScreenGutter = 10;

  /// Padding interne standard d'une carte.
  static const double cardPadding = 18;

  /// Padding interne des rangées de liste et des cartes denses.
  static const double compactCardPadding = 15;

  /// Espace entre deux blocs principaux ou deux sections.
  static const double sectionGap = 22;

  /// Espace entre des éléments directement liés.
  static const double contentGap = 8;

  /// Micro-ajustement visuel.
  static const double microGap = 4;
}
