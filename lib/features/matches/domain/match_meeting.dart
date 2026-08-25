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
  return DateTime(
    kickoffAt.year,
    kickoffAt.month,
    kickoffAt.day,
    hour,
    minute,
  );
}

DateTime? preserveCustomMeetingTime({
  required DateTime kickoffAt,
  required DateTime? customMeetingAt,
}) {
  if (customMeetingAt == null) return null;
  final shifted = matchMeetingAtOnKickoffDate(
    kickoffAt: kickoffAt,
    hour: customMeetingAt.hour,
    minute: customMeetingAt.minute,
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
