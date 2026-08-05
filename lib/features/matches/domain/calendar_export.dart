import 'package:as_grinta/features/matches/domain/match_model.dart';

String buildSeasonIcs({
  required String seasonName,
  required Iterable<MatchModel> matches,
  DateTime? generatedAt,
}) {
  final now = (generatedAt ?? DateTime.now()).toUtc();
  final buffer = StringBuffer()
    ..write('BEGIN:VCALENDAR\r\n')
    ..write('VERSION:2.0\r\n')
    ..write('PRODID:-//SportEasy Grinta//Calendrier $seasonName//FR\r\n')
    ..write('CALSCALE:GREGORIAN\r\n')
    ..write('METHOD:PUBLISH\r\n')
    ..write(_foldIcsLine('X-WR-CALNAME:SportEasy Grinta $seasonName'));

  final ordered = matches.where((match) => !match.isCancelled).toList()
    ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));

  for (final match in ordered) {
    final start = match.kickoffAt.toUtc();
    final end = start.add(Duration(minutes: match.plannedDurationMinutes));
    final opponent = match.opponentName?.trim().isNotEmpty == true
        ? match.opponentName!.trim()
        : 'Adversaire';
    final summary = match.isInternal
        ? 'AS Grinta — Match entre nous'
        : match.isHome
        ? 'AS Grinta - $opponent'
        : '$opponent - AS Grinta';

    buffer
      ..write('BEGIN:VEVENT\r\n')
      ..write(_foldIcsLine('UID:${_escapeIcs(match.id)}@sporteasy-grinta'))
      ..write('DTSTAMP:${_formatUtc(now)}\r\n')
      ..write('DTSTART:${_formatUtc(start)}\r\n')
      ..write('DTEND:${_formatUtc(end)}\r\n')
      ..write(_foldIcsLine('SUMMARY:${_escapeIcs(summary)}'))
      ..write(
        _foldIcsLine(
          'DESCRIPTION:${_escapeIcs('SportEasy Grinta — ${match.matchTypeLabel}')}',
        ),
      );

    final address = match.address?.trim();
    if (address != null && address.isNotEmpty) {
      buffer.write(_foldIcsLine('LOCATION:${_escapeIcs(address)}'));
    }

    buffer.write('END:VEVENT\r\n');
  }

  buffer.write('END:VCALENDAR\r\n');
  return buffer.toString();
}

String _formatUtc(DateTime value) {
  final utc = value.toUtc();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}'
      '${two(utc.month)}${two(utc.day)}T'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}

String _escapeIcs(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\r\n', '\\n')
    .replaceAll('\n', '\\n')
    .replaceAll('\r', '\\n');

String _foldIcsLine(String value) {
  const maxChars = 72;
  if (value.length <= maxChars) return '$value\r\n';

  final buffer = StringBuffer();
  var offset = 0;
  while (offset < value.length) {
    final end = (offset + maxChars < value.length)
        ? offset + maxChars
        : value.length;
    if (offset > 0) buffer.write(' ');
    buffer.write(value.substring(offset, end));
    buffer.write('\r\n');
    offset = end;
  }
  return buffer.toString();
}
