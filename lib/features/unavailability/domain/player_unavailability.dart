import 'package:flutter/material.dart';

/// Une période pendant laquelle un joueur s'est déclaré indisponible.
///
/// Les bornes sont des dates pleines, incluses toutes les deux, lues en heure
/// de Paris côté serveur. On ne manipule donc jamais d'heure ici : « du 12 au
/// 25 » veut dire du 12 au 25 inclus.
@immutable
class PlayerUnavailability {
  const PlayerUnavailability({
    required this.id,
    required this.startsOn,
    required this.endsOn,
    required this.reason,
    required this.createdAt,
    required this.isPast,
    required this.isCurrent,
    this.profileId,
    this.displayName,
    this.firstName,
    this.lastName,
    this.photoUrl,
  });

  final String id;
  final DateTime startsOn;
  final DateTime endsOn;
  final String reason;
  final DateTime createdAt;

  /// La période est entièrement passée : elle n'est plus modifiable.
  final bool isPast;

  /// Aujourd'hui tombe dans la période.
  final bool isCurrent;

  /// Renseignés uniquement par la lecture d'ensemble réservée aux admins.
  final String? profileId;
  final String? displayName;
  final String? firstName;
  final String? lastName;
  final String? photoUrl;

  bool get isUpcoming => !isPast && !isCurrent;

  static DateTime _requiredDate(Map<String, dynamic> map, String key) {
    final raw = map[key]?.toString();
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    if (parsed == null) {
      throw FormatException('Date d’indisponibilité illisible : $key');
    }
    return parsed;
  }

  static String? _optionalText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  factory PlayerUnavailability.fromRpc(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Indisponibilité illisible');
    }
    final map = Map<String, dynamic>.from(raw);
    final id = map['id']?.toString();
    final reason = map['reason']?.toString().trim();
    if (id == null || id.isEmpty || reason == null || reason.isEmpty) {
      throw const FormatException('Indisponibilité incomplète');
    }

    return PlayerUnavailability(
      id: id,
      startsOn: _requiredDate(map, 'starts_on'),
      endsOn: _requiredDate(map, 'ends_on'),
      reason: reason,
      createdAt: _requiredDate(map, 'created_at'),
      isPast: map['is_past'] == true,
      isCurrent: map['is_current'] == true,
      profileId: _optionalText(map['profile_id']),
      displayName: _optionalText(map['display_name']),
      firstName: _optionalText(map['first_name']),
      lastName: _optionalText(map['last_name']),
      photoUrl: _optionalText(map['photo_url']),
    );
  }

  static List<PlayerUnavailability> listFromRpc(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw const FormatException('Liste d’indisponibilités illisible');
    }
    return raw.map(PlayerUnavailability.fromRpc).toList(growable: false);
  }
}

/// « 12 octobre » ou « 12 octobre 2027 » si l'année n'est pas celle en cours.
String formatUnavailabilityDay(DateTime day, {DateTime? today}) {
  const months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];
  final reference = today ?? DateTime.now();
  final label = '${day.day} ${months[day.month - 1]}';
  return day.year == reference.year ? label : '$label ${day.year}';
}

/// « le 12 octobre » quand la période tient sur un jour, « du 12 au 25
/// octobre » sinon.
String formatUnavailabilityPeriod(
  DateTime startsOn,
  DateTime endsOn, {
  DateTime? today,
}) {
  if (startsOn.year == endsOn.year &&
      startsOn.month == endsOn.month &&
      startsOn.day == endsOn.day) {
    return 'le ${formatUnavailabilityDay(startsOn, today: today)}';
  }
  return 'du ${formatUnavailabilityDay(startsOn, today: today)} '
      'au ${formatUnavailabilityDay(endsOn, today: today)}';
}
