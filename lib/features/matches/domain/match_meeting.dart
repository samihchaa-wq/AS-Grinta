const defaultMatchMeetingOffset = Duration(minutes: 30);

DateTime resolvedMatchMeetingAt({
  required DateTime kickoffAt,
  DateTime? customMeetingAt,
}) {
  return customMeetingAt ?? kickoffAt.subtract(defaultMatchMeetingOffset);
}

DateTime matchMeetingAtOnKickoffDate({
  required DateTime kickoffAt,
  required int hour,
  required int minute,
}) {
  return DateTime(kickoffAt.year, kickoffAt.month, kickoffAt.day, hour, minute);
}

DateTime? preserveCustomMeetingTime({
  required DateTime kickoffAt,
  required DateTime? customMeetingAt,
  DateTime? previousKickoffAt,
}) {
  if (customMeetingAt == null) return null;

  // A custom rendez-vous is now a real date + time, not just a clock time.
  // When the kickoff date moves, keep the same calendar-day offset so a
  // rendez-vous chosen the day before the match follows the match naturally.
  if (previousKickoffAt == null) {
    return customMeetingAt.isBefore(kickoffAt) ? customMeetingAt : null;
  }

  final oldKickoffDay = DateTime.utc(
    previousKickoffAt.year,
    previousKickoffAt.month,
    previousKickoffAt.day,
  );
  final oldMeetingDay = DateTime.utc(
    customMeetingAt.year,
    customMeetingAt.month,
    customMeetingAt.day,
  );
  final dayOffset = oldKickoffDay.difference(oldMeetingDay).inDays;
  final shifted = DateTime(
    kickoffAt.year,
    kickoffAt.month,
    kickoffAt.day - dayOffset,
    customMeetingAt.hour,
    customMeetingAt.minute,
    customMeetingAt.second,
    customMeetingAt.millisecond,
    customMeetingAt.microsecond,
  );
  return shifted.isBefore(kickoffAt) ? shifted : null;
}

String? validateCustomMeetingAt({
  required DateTime kickoffAt,
  required DateTime? customMeetingAt,
}) {
  if (customMeetingAt == null) return null;
  if (!customMeetingAt.isBefore(kickoffAt)) {
    return 'L’heure de rendez-vous doit être avant le coup d’envoi.';
  }
  return null;
}
