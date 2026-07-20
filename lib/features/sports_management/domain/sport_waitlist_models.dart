enum ConvocationStatus {
  notApplicable,
  convoked,
  notConvoked;

  static ConvocationStatus fromWire(Object? value) {
    return switch (value?.toString()) {
      'convoked' => ConvocationStatus.convoked,
      'not_convoked' => ConvocationStatus.notConvoked,
      _ => ConvocationStatus.notApplicable,
    };
  }

  String get wireValue => switch (this) {
        ConvocationStatus.notApplicable => 'not_applicable',
        ConvocationStatus.convoked => 'convoked',
        ConvocationStatus.notConvoked => 'not_convoked',
      };
}

enum WaitlistTurnState {
  notApplicable,
  pending,
  consumed,
  waived;

  static WaitlistTurnState fromWire(Object? value) {
    return switch (value?.toString()) {
      'pending' => WaitlistTurnState.pending,
      'consumed' => WaitlistTurnState.consumed,
      'waived' => WaitlistTurnState.waived,
      _ => WaitlistTurnState.notApplicable,
    };
  }
}

class SportWaitlistEntry {
  const SportWaitlistEntry({
    required this.seasonPlayerId,
    required this.firstName,
    required this.lastName,
    required this.position,
    required this.previousSeasonAttendanceCount,
    required this.previousSeasonMatchCount,
    required this.source,
  });

  factory SportWaitlistEntry.fromJson(Map<String, dynamic> json) {
    return SportWaitlistEntry(
      seasonPlayerId: json['season_player_id'].toString(),
      firstName: (json['first_name'] ?? '').toString(),
      lastName: (json['last_name'] ?? '').toString(),
      position: (json['position'] as num?)?.toInt() ?? 0,
      previousSeasonAttendanceCount:
          (json['previous_season_attendance_count'] as num?)?.toInt() ?? 0,
      previousSeasonMatchCount:
          (json['previous_season_match_count'] as num?)?.toInt() ?? 0,
      source: (json['source'] ?? 'previous_season_attendance').toString(),
    );
  }

  final String seasonPlayerId;
  final String firstName;
  final String lastName;
  final int position;
  final int previousSeasonAttendanceCount;
  final int previousSeasonMatchCount;
  final String source;

  String get displayName => '$firstName $lastName'.trim();
}

class SportWaitlist {
  const SportWaitlist({
    required this.seasonId,
    required this.seasonName,
    required this.entries,
  });

  factory SportWaitlist.fromRpc(Object? raw) {
    final json = _map(raw);
    final entriesRaw = json['entries'];
    return SportWaitlist(
      seasonId: json['season_id'].toString(),
      seasonName: (json['season_name'] ?? '').toString(),
      entries: entriesRaw is List
          ? entriesRaw
              .map((row) => SportWaitlistEntry.fromJson(_map(row)))
              .toList()
          : const [],
    );
  }

  final String seasonId;
  final String seasonName;
  final List<SportWaitlistEntry> entries;
}

class AdminSportMatch {
  const AdminSportMatch({
    required this.id,
    required this.opponentName,
    required this.kickoffAt,
  });

  factory AdminSportMatch.fromJson(Map<String, dynamic> json) {
    return AdminSportMatch(
      id: json['id'].toString(),
      opponentName: (json['opponent_name'] ?? 'Adversaire').toString(),
      kickoffAt: DateTime.parse(json['kickoff_at'].toString()).toLocal(),
    );
  }

  final String id;
  final String opponentName;
  final DateTime kickoffAt;
}

class ConvocationPlayer {
  const ConvocationPlayer({
    required this.participantId,
    required this.seasonPlayerId,
    required this.firstName,
    required this.lastName,
    required this.availabilityStatus,
    required this.convocationStatus,
    required this.manualOverride,
    required this.waitlistPosition,
    required this.recommendedNotConvoked,
    required this.turnShouldConsume,
    required this.turnState,
    required this.promotedAfterWithdrawalAt,
  });

  factory ConvocationPlayer.fromJson(Map<String, dynamic> json) {
    return ConvocationPlayer(
      participantId: json['participant_id'].toString(),
      seasonPlayerId: json['season_player_id'].toString(),
      firstName: (json['first_name'] ?? '').toString(),
      lastName: (json['last_name'] ?? '').toString(),
      availabilityStatus:
          (json['availability_status'] ?? 'no_response').toString(),
      convocationStatus: ConvocationStatus.fromWire(json['convocation_status']),
      manualOverride: json['manual_override'] == true,
      waitlistPosition: (json['waitlist_position'] as num?)?.toInt(),
      recommendedNotConvoked: json['recommended_not_convoked'] == true,
      turnShouldConsume: json['turn_should_consume'] == true,
      turnState: WaitlistTurnState.fromWire(json['turn_state']),
      promotedAfterWithdrawalAt:
          _dateOrNull(json['promoted_after_withdrawal_at']),
    );
  }

  final String participantId;
  final String seasonPlayerId;
  final String firstName;
  final String lastName;
  final String availabilityStatus;
  final ConvocationStatus convocationStatus;
  final bool manualOverride;
  final int? waitlistPosition;
  final bool recommendedNotConvoked;
  final bool turnShouldConsume;
  final WaitlistTurnState turnState;
  final DateTime? promotedAfterWithdrawalAt;

  String get displayName => '$firstName $lastName'.trim();
  bool get isAvailable => availabilityStatus == 'available';
  bool get isAbsent => availabilityStatus == 'absent';
  bool get isConvoked => convocationStatus == ConvocationStatus.convoked;
  bool get isNotConvoked => convocationStatus == ConvocationStatus.notConvoked;
}

class MatchConvocations {
  const MatchConvocations({
    required this.matchId,
    required this.opponentName,
    required this.kickoffAt,
    required this.seasonId,
    required this.squadSizeLimit,
    required this.convocationState,
    required this.convocationVersion,
    required this.lateWithdrawalCutoffAt,
    required this.availableCount,
    required this.convokedCount,
    required this.notConvokedCount,
    required this.players,
  });

  factory MatchConvocations.fromRpc(Object? raw) {
    final json = _map(raw);
    final playersRaw = json['players'];
    return MatchConvocations(
      matchId: json['match_id'].toString(),
      opponentName: (json['opponent_name'] ?? 'Adversaire').toString(),
      kickoffAt: DateTime.parse(json['kickoff_at'].toString()).toLocal(),
      seasonId: json['season_id'].toString(),
      squadSizeLimit: (json['squad_size_limit'] as num?)?.toInt() ?? 14,
      convocationState: (json['convocation_state'] ?? 'draft').toString(),
      convocationVersion: (json['convocation_version'] as num?)?.toInt() ?? 0,
      lateWithdrawalCutoffAt: _dateOrNull(json['late_withdrawal_cutoff_at']),
      availableCount: (json['available_count'] as num?)?.toInt() ?? 0,
      convokedCount: (json['convoked_count'] as num?)?.toInt() ?? 0,
      notConvokedCount: (json['not_convoked_count'] as num?)?.toInt() ?? 0,
      players: playersRaw is List
          ? playersRaw
              .map((row) => ConvocationPlayer.fromJson(_map(row)))
              .toList()
          : const [],
    );
  }

  final String matchId;
  final String opponentName;
  final DateTime kickoffAt;
  final String seasonId;
  final int squadSizeLimit;
  final String convocationState;
  final int convocationVersion;
  final DateTime? lateWithdrawalCutoffAt;
  final int availableCount;
  final int convokedCount;
  final int notConvokedCount;
  final List<ConvocationPlayer> players;

  bool get isPublished => convocationState == 'published';
  bool get isOverLimit => convokedCount > squadSizeLimit;
}

Map<String, dynamic> _map(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  throw const FormatException('Réponse sportive invalide.');
}

DateTime? _dateOrNull(Object? raw) {
  final value = raw?.toString();
  if (value == null || value.isEmpty || value == 'null') return null;
  return DateTime.tryParse(value)?.toLocal();
}
