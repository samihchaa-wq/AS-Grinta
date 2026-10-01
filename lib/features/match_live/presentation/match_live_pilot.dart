import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Qui pilote le Live d'un match, d'après l'état renvoyé par le serveur.
enum LivePilot {
  /// Personne ne pilote : un coach peut prendre la place.
  nobody,

  /// Ce téléphone pilote.
  me,

  /// Un autre téléphone pilote.
  other,
}

/// Onglet choisi par un coach sous « Live » : suivre le match ou le piloter.
/// Ce choix d'affichage reste local ; la place de pilote, elle, est tenue par
/// le serveur et ne dépend jamais de ce provider.
enum LiveViewMode { spectator, pilot }

final liveViewModeProvider = StateProvider.family<LiveViewMode, String>(
  (ref, matchId) => LiveViewMode.spectator,
);
