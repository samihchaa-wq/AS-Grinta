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

/// Keeps an explicit rendez-vous coherent when the kickoff changes.
///
/// With [previousKickoffAt], the selected day offset relative to the match is
/// preserved as well as the local clock time. This matters now that the admin
/// may deliberately choose the day before the match. Without it, the function
/// keeps the historical same-day behavior for older callers.
DateTime? preserveCustomMeetingTime({
  required DateTime kickoffAt,
  required DateTime? customMeetingAt,
  DateTime? previousKickoffAt,
}) {
  if (customMeetingAt == null) return null;

  if (previousKickoffAt == null) {
    final shifted = matchMeetingAtOnKickoffDate(
      kickoffAt: kickoffAt,
      hour: customMeetingAt.hour,
      minute: customMeetingAt.minute,
    );
    return shifted.isBefore(kickoffAt) ? shifted : null;
  }

  final previousKickoffDate = DateTime(
    previousKickoffAt.year,
    previousKickoffAt.month,
    previousKickoffAt.day,
  );
  final customDate = DateTime(
    customMeetingAt.year,
    customMeetingAt.month,
    customMeetingAt.day,
  );
  final dayOffset = customDate.difference(previousKickoffDate).inDays;
  final newMeetingDate = DateTime(
    kickoffAt.year,
    kickoffAt.month,
    kickoffAt.day,
  ).add(Duration(days: dayOffset));
  final shifted = DateTime(
    newMeetingDate.year,
    newMeetingDate.month,
    newMeetingDate.day,
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
