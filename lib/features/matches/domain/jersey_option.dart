/// Maillots proposés au choix de l'admin pour un match (remplace la
/// description libre par une sélection visuelle parmi un jeu fixe
/// d'illustrations). La valeur stockée en base (`jersey_note`) est
/// simplement l'identifiant du maillot choisi.
enum JerseyOption {
  orange('orange', 'assets/images/jerseys/jersey_orange.png', 'Orange'),
  blue('blue', 'assets/images/jerseys/jersey_blue.png', 'Bleu');

  const JerseyOption(this.id, this.assetPath, this.label);

  final String id;
  final String assetPath;
  final String label;

  static JerseyOption? fromId(String? id) {
    if (id == null) return null;
    for (final option in values) {
      if (option.id == id) return option;
    }
    return null;
  }
}
