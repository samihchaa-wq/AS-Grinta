/// Règles temporelles communes aux écrans liés à un match.
///
/// Les fonctionnalités de préparation s'ouvrent à midi, heure locale du
/// calendrier du match, six jours avant sa date. Les coups d'envoi reçus par
/// l'application sont des instants absolus convertis en heure locale par Dart ;
/// l'API Supabase reste la source de vérité avec le fuseau Europe/Paris.
const int kMatchOpensDaysBefore = 6;
const int kMatchOpensLocalHour = 12;

/// Le module de suivi en direct devient accessible quinze minutes avant le
/// coup d'envoi.
const Duration kMatchLiveOpensBeforeKickoff = Duration(minutes: 15);

/// Instant local d'ouverture de l'effectif, de la composition et du prono.
DateTime matchFeaturesOpenAt(DateTime kickoffAt) {
  final localKickoff = kickoffAt.toLocal();
  return DateTime(
    localKickoff.year,
    localKickoff.month,
    localKickoff.day - kMatchOpensDaysBefore,
    kMatchOpensLocalHour,
  );
}

/// Instant d'ouverture du module Live.
DateTime matchLiveOpensAt(DateTime kickoffAt) =>
    kickoffAt.subtract(kMatchLiveOpensBeforeKickoff);

/// `true` tant que la fiche complète n'est pas encore ouverte.
///
/// Un coup d'envoi inconnu est considéré comme ouvert : mieux vaut afficher
/// la fiche complète que de la vider sur une donnée manquante.
bool isMatchTooFarAway(DateTime? kickoffAt, {DateTime? now}) {
  if (kickoffAt == null) return false;
  final reference = now ?? DateTime.now();
  return reference.isBefore(matchFeaturesOpenAt(kickoffAt));
}

/// `true` tant que le module Live doit rester masqué et inaccessible.
bool isMatchLiveTooEarly(DateTime? kickoffAt, {DateTime? now}) {
  if (kickoffAt == null) return false;
  final reference = now ?? DateTime.now();
  return reference.isBefore(matchLiveOpensAt(kickoffAt));
}
