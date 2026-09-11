import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';

/// Match ouvert par défaut par les écrans d'administration sportive.
///
/// La liste reçue du serveur est triée du coup d'envoi le plus lointain au plus
/// ancien. En prendre la première ligne ouvrait donc le match le plus éloigné
/// du calendrier — parfois plusieurs semaines plus tard — alors que l'écran
/// sert à préparer la rencontre qui arrive.
///
/// La règle retenue est celle qu'attend un administrateur : le prochain match à
/// jouer, et à défaut le dernier joué. Le calcul ne suppose aucun ordre
/// particulier dans [matches], pour qu'un changement de tri côté serveur ne
/// puisse pas le fausser en silence.
String? defaultAdminMatchId(
  List<AdminSportMatch> matches, {
  DateTime? now,
}) {
  if (matches.isEmpty) return null;

  final reference = (now ?? DateTime.now()).toUtc();
  AdminSportMatch? next;
  AdminSportMatch? previous;

  for (final match in matches) {
    final kickoff = match.kickoffAt.toUtc();
    if (kickoff.isBefore(reference)) {
      if (previous == null || kickoff.isAfter(previous.kickoffAt.toUtc())) {
        previous = match;
      }
    } else if (next == null || kickoff.isBefore(next.kickoffAt.toUtc())) {
      next = match;
    }
  }

  return (next ?? previous ?? matches.first).id;
}
