/// Charte d'espacement commune à AS Grinta.
///
/// Principe : petites marges extérieures pour préserver l'espace utile,
/// puis davantage d'air à l'intérieur des cartes. Les valeurs spécifiques
/// au Live restent volontairement plus serrées. Ces constantes servent de
/// référence aux écrans principaux afin de conserver les mêmes axes visuels.
abstract final class AppSpacing {
  /// Marge latérale standard des écrans.
  static const double screenGutter = 12;

  /// Marge latérale du cockpit Live, où la largeur du terrain est prioritaire.
  static const double liveScreenGutter = 10;

  /// Padding interne standard d'une carte.
  static const double cardPadding = 14;

  /// Padding interne des cartes denses.
  static const double compactCardPadding = 12;

  /// Espace entre deux blocs principaux.
  static const double sectionGap = 12;

  /// Espace entre des éléments directement liés.
  static const double contentGap = 8;

  /// Micro-ajustement visuel.
  static const double microGap = 4;
}
