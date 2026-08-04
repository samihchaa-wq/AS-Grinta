/// Règles temporelles communes aux écrans liés à un match.
///
/// L'API Supabase reste la source de vérité. Côté interface, les règles qui
/// dépendent d'une heure civile utilisent explicitement Europe/Paris afin que
/// le résultat ne change jamais avec le fuseau réglé sur le téléphone.
const int kMatchOpensDaysBefore = 6;
const int kMatchOpensLocalHour = 12;

/// Le module Live devient accessible quinze minutes avant le coup d'envoi.
const Duration kMatchLiveOpensBeforeKickoff = Duration(minutes: 15);

/// Les pronostics ferment au même instant que l'ouverture du Live. Cette
/// frontière unique évite le chevauchement historique Live + prono.
const Duration kMatchPredictionClosesBeforeKickoff = Duration(minutes: 15);

/// Marge civile ajoutée à la durée sportive planifiée lorsqu'aucune session
/// Live ne nous donne explicitement « fin du match ». Pour un match de 90 min,
/// cela place l'état « À valider » à T+1h45.
const Duration kMatchPostgameBuffer = Duration(minutes: 15);

enum MatchDisplayPhase {
  upcoming,
  next,
  live,
  awaitingValidation,
  past,
  cancelled,
}

/// Instant absolu d'ouverture de l'effectif, de la composition et du prono :
/// J-6 à 12 h, heure de Paris.
DateTime matchFeaturesOpenAt(DateTime kickoffAt) {
  final kickoffUtc = kickoffAt.toUtc();
  final parisKickoff = kickoffUtc.add(_parisOffsetAt(kickoffUtc));
  final localOpenDate = DateTime.utc(
    parisKickoff.year,
    parisKickoff.month,
    parisKickoff.day - kMatchOpensDaysBefore,
    kMatchOpensLocalHour,
  );
  return localOpenDate.subtract(_parisOffsetForLocalNoon(localOpenDate));
}

/// Instant commun d'ouverture du Live et de fermeture des pronostics.
DateTime matchLiveOpensAt(DateTime kickoffAt) =>
    kickoffAt.toUtc().subtract(kMatchLiveOpensBeforeKickoff);

DateTime matchPredictionClosesAt(DateTime kickoffAt) =>
    kickoffAt.toUtc().subtract(kMatchPredictionClosesBeforeKickoff);

/// Heure de repli vers « À valider » si aucun Live n'a explicitement été
/// terminé. La durée sportive ne contient pas la pause, d'où la marge de 15 min.
DateTime matchExpectedValidationAt(
  DateTime kickoffAt,
  int plannedDurationMinutes,
) =>
    kickoffAt.toUtc().add(
          Duration(minutes: plannedDurationMinutes) + kMatchPostgameBuffer,
        );

/// `true` tant que la fiche complète n'est pas encore ouverte.
///
/// Un coup d'envoi inconnu est considéré comme ouvert : mieux vaut afficher
/// la fiche complète que de la vider sur une donnée manquante.
bool isMatchTooFarAway(DateTime? kickoffAt, {DateTime? now}) {
  if (kickoffAt == null) return false;
  final reference = (now ?? DateTime.now()).toUtc();
  return reference.isBefore(matchFeaturesOpenAt(kickoffAt));
}

/// `true` tant que le module Live doit rester masqué et inaccessible.
bool isMatchLiveTooEarly(DateTime? kickoffAt, {DateTime? now}) {
  if (kickoffAt == null) return false;
  final reference = (now ?? DateTime.now()).toUtc();
  return reference.isBefore(matchLiveOpensAt(kickoffAt));
}

/// `true` dès T-15. Utilisé par l'UI en complément du garde-fou Supabase.
bool isMatchPredictionClosed(DateTime? kickoffAt, {DateTime? now}) {
  if (kickoffAt == null) return true;
  final reference = (now ?? DateTime.now()).toUtc();
  return !reference.isBefore(matchPredictionClosesAt(kickoffAt));
}

/// Les actions qui changent l'identité du match (date, adversaire, annulation,
/// suppression) sont figées à T-15. Les corrections post-match utilisent leur
/// workflow dédié et ne passent pas par l'édition classique du match.
bool isMatchAdminEditLocked(DateTime? kickoffAt, {DateTime? now}) {
  if (kickoffAt == null) return false;
  final reference = (now ?? DateTime.now()).toUtc();
  return !reference.isBefore(matchLiveOpensAt(kickoffAt));
}

/// Phase d'affichage unique pour l'onglet Matchs.
///
/// Une session Live active reste autoritaire même si le match dépasse son heure
/// de fin théorique. `finished` bascule vers « À valider » seulement à partir
/// du coup d'envoi. Sans Live actif, la durée planifiée + 15 minutes sert de repli.
MatchDisplayPhase matchDisplayPhase({
  required DateTime kickoffAt,
  required String status,
  required int plannedDurationMinutes,
  String? liveState,
  DateTime? now,
}) {
  if (status == 'annule') return MatchDisplayPhase.cancelled;
  if (status == 'termine' || status == 'archive') {
    return MatchDisplayPhase.past;
  }

  final reference = (now ?? DateTime.now()).toUtc();
  final kickoff = kickoffAt.toUtc();

  if (reference.isBefore(matchFeaturesOpenAt(kickoff))) {
    return MatchDisplayPhase.upcoming;
  }
  if (reference.isBefore(matchLiveOpensAt(kickoff))) {
    return MatchDisplayPhase.next;
  }
  if (liveState == 'finished' && !reference.isBefore(kickoff)) {
    return MatchDisplayPhase.awaitingValidation;
  }
  if (liveState == 'running' ||
      liveState == 'paused' ||
      liveState == 'halftime') {
    return MatchDisplayPhase.live;
  }
  if (!reference.isBefore(
    matchExpectedValidationAt(kickoff, plannedDurationMinutes),
  )) {
    return MatchDisplayPhase.awaitingValidation;
  }
  return MatchDisplayPhase.live;
}

/// Europe/Paris suit actuellement les règles européennes : UTC+1 en hiver et
/// UTC+2 entre le dernier dimanche de mars à 01:00 UTC et le dernier dimanche
/// d'octobre à 01:00 UTC. Cette conversion est volontairement locale à ce
/// fichier pour éviter que l'interface dépende du fuseau horaire du terminal.
Duration _parisOffsetAt(DateTime instantUtc) {
  final utc = instantUtc.toUtc();
  final marchSunday = _lastSundayOfMonth(utc.year, DateTime.march);
  final octoberSunday = _lastSundayOfMonth(utc.year, DateTime.october);
  final dstStarts = DateTime.utc(utc.year, DateTime.march, marchSunday, 1);
  final dstEnds = DateTime.utc(utc.year, DateTime.october, octoberSunday, 1);
  final isSummer = !utc.isBefore(dstStarts) && utc.isBefore(dstEnds);
  return Duration(hours: isSummer ? 2 : 1);
}

/// Décalage applicable à un midi civil parisien représenté ici sous forme
/// d'un DateTime UTC factice. Midi n'est jamais dans l'heure ambiguë du
/// changement d'heure, donc la règle est déterministe.
Duration _parisOffsetForLocalNoon(DateTime localNoon) {
  final year = localNoon.year;
  final month = localNoon.month;
  final day = localNoon.day;
  if (month < DateTime.march || month > DateTime.october) {
    return const Duration(hours: 1);
  }
  if (month > DateTime.march && month < DateTime.october) {
    return const Duration(hours: 2);
  }
  if (month == DateTime.march) {
    return Duration(
      hours: day >= _lastSundayOfMonth(year, DateTime.march) ? 2 : 1,
    );
  }
  return Duration(
    hours: day < _lastSundayOfMonth(year, DateTime.october) ? 2 : 1,
  );
}

int _lastSundayOfMonth(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0);
  return lastDay.day - (lastDay.weekday % DateTime.daysPerWeek);
}
