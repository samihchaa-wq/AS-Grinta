/// Qui pilote le Live d'un match, d'après l'état renvoyé par le serveur.
enum LivePilot {
  /// Personne ne pilote : le coach peut prendre la place.
  nobody,

  /// Ce téléphone pilote.
  me,

  /// Un autre téléphone pilote.
  other,
}
