/// Règles temporelles communes aux écrans liés à un match.
///
/// L'API Supabase reste la source de vérité. Côté interface, les règles qui
/// dépendent d'une heure civile utilisent explicitement Europe/Paris afin que
/// le résultat ne change jamais avec le fuseau réglé sur le téléphone.
const int kMatchOpensDaysBefore = 6;
const int kMatchOpensLocalHour = 12;

/// Le module de suivi en direct devient accessible quinze minutes avant le
/// coup d'envoi.
const Duration kMatchLiveOpensBeforeKickoff = Duration(minutes: 15);

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

/// Instant d'ouverture du module Live.
DateTime matchLiveOpensAt(DateTime kickoffAt) =>
    kickoffAt.toUtc().subtract(kMatchLiveOpensBeforeKickoff);

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
