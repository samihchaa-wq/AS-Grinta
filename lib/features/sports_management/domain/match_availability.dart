enum MatchAvailabilityStatus {
  noResponse,
  available,
  absent,
  notApplicable;

  static MatchAvailabilityStatus fromWire(Object? value) {
    return switch (value?.toString()) {
      'no_response' => MatchAvailabilityStatus.noResponse,
      'available' => MatchAvailabilityStatus.available,
      'absent' => MatchAvailabilityStatus.absent,
      'not_applicable' => MatchAvailabilityStatus.notApplicable,
      _ => throw const FormatException('Invalid match availability status'),
    };
  }

  String get wireValue => switch (this) {
        MatchAvailabilityStatus.noResponse => 'no_response',
        MatchAvailabilityStatus.available => 'available',
        MatchAvailabilityStatus.absent => 'absent',
        MatchAvailabilityStatus.notApplicable => 'not_applicable',
      };

  String get label => switch (this) {
        MatchAvailabilityStatus.noResponse => 'Sans réponse',
        MatchAvailabilityStatus.available => 'Disponible',
        MatchAvailabilityStatus.absent => 'Absent',
        MatchAvailabilityStatus.notApplicable => 'Non concerné',
      };
}

class MatchAvailability {
  const MatchAvailability({
    required this.matchId,
    required this.participantId,
    required this.seasonPlayerId,
    required this.isEligible,
    required this.status,
    required this.privateComment,
    required this.updatedAt,
    required this.availabilityState,
    required this.opensAt,
    required this.kickoffAt,
    required this.canRespond,
    required this.compositionState,
  });

  final String matchId;
  final String participantId;
  final String seasonPlayerId;
  final bool isEligible;
  final MatchAvailabilityStatus status;
  final String? privateComment;
  final DateTime? updatedAt;
  final String availabilityState;
  final DateTime opensAt;
  final DateTime kickoffAt;
  final bool canRespond;
  final String compositionState;

  bool get compositionAlreadyPublished =>
      compositionState == 'published' ||
      compositionState == 'updated' ||
      compositionState == 'closed';

  factory MatchAvailability.fromRpc(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Availability RPC must return an object');
    }
    final map = Map<String, dynamic>.from(raw);

    String requiredString(String key) {
      final value = map[key]?.toString();
      if (value == null || value.isEmpty) {
        throw FormatException('Missing availability field: $key');
      }
      return value;
    }

    DateTime requiredDate(String key) {
      final parsed = DateTime.tryParse(requiredString(key));
      if (parsed == null) {
        throw FormatException('Invalid availability date: $key');
      }
      return parsed;
    }

    DateTime? optionalDate(String key) {
      final value = map[key]?.toString();
      if (value == null || value.isEmpty) return null;
      return DateTime.tryParse(value);
    }

    return MatchAvailability(
      matchId: requiredString('match_id'),
      participantId: requiredString('participant_id'),
      seasonPlayerId: requiredString('season_player_id'),
      isEligible: map['is_eligible'] == true,
      status: MatchAvailabilityStatus.fromWire(map['availability_status']),
      privateComment: _optionalText(map['private_comment']),
      updatedAt: optionalDate('availability_updated_at'),
      availabilityState: requiredString('availability_state'),
      opensAt: requiredDate('availability_opens_at'),
      kickoffAt: requiredDate('kickoff_at'),
      canRespond: map['can_respond'] == true,
      compositionState: requiredString('composition_state'),
    );
  }

  static String? _optionalText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
