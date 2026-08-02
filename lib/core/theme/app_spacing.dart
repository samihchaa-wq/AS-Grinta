/// Charte d'espacement commune à AS Grinta.
///
/// Principe : marges extérieures minimales pour préserver l'espace utile,
/// avec des espacements internes compacts mais lisibles. Ces constantes sont
/// la source unique de vérité pour les écrans principaux : toute évolution de
/// densité doit partir d'ici afin de rester cohérente dans toute l'application.
abstract final class AppSpacing {
  /// Marge latérale standard des écrans.
  static const double screenGutter = 8;

  /// Marge latérale du cockpit Live, où la largeur du terrain est prioritaire.
  static const double liveScreenGutter = 6;

  /// Padding interne standard d'une carte.
  static const double cardPadding = 12;

  /// Padding interne des cartes denses.
  static const double compactCardPadding = 10;

  /// Espace entre deux blocs principaux.
  static const double sectionGap = 8;

  /// Espace entre des éléments directement liés.
  static const double contentGap = 6;

  /// Micro-ajustement visuel.
  static const double microGap = 4;
}
