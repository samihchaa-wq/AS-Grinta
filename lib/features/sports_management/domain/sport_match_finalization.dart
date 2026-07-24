enum SportFinalSelectionStatus {
  starter,
  substitute,
  notSelected;

  static SportFinalSelectionStatus fromWire(Object? value) {
    return switch (value?.toString()) {
      'starter' => SportFinalSelectionStatus.starter,
      'substitute' => SportFinalSelectionStatus.substitute,
      _ => SportFinalSelectionStatus.notSelected,
    };
  }

  String get wireValue => switch (this) {
        SportFinalSelectionStatus.starter => 'starter',
        SportFinalSelectionStatus.substitute => 'substitute',
        SportFinalSelectionStatus.notSelected => 'not_selected',
      };

  String get label => switch (this) {
        SportFinalSelectionStatus.starter => 'Titulaire',
        SportFinalSelectionStatus.substitute => 'Remplaçant',
        SportFinalSelectionStatus.notSelected => 'Présent hors composition',
      };
}

class SportFinalParticipant {
  const SportFinalParticipant({
    required this.participantId,
    required this.displayName,
    required this.isGuest,
    required this.isGoalkeeper,
    required this.plannedZone,
    required this.present,
    required this.selectionStatus,
    required this.goals,
    required this.cleanSheet,
    this.seasonPlayerId,
    this.guestPlayerId,
  });

  factory SportFinalParticipant.fromJson(Map<String, dynamic> json) {
    return SportFinalParticipant(
      participantId: json['participant_id'].toString(),
      seasonPlayerId: _nullableText(json['season_player_id']),
      guestPlayerId: _nullableText(json['guest_player_id']),
      displayName: (json['display_name'] ?? 'Joueur').toString(),
      isGuest: json['is_guest'] == true,
      isGoalkeeper: json['is_goalkeeper'] == true,
      plannedZone: (json['planned_zone'] ?? 'available').toString(),
      present: json['present'] == true,
      selectionStatus: SportFinalSelectionStatus.fromWire(
        json['final_selection_status'],
      ),
      goals: (json['goals'] as num?)?.toInt() ?? 0,
      cleanSheet: json['clean_sheet'] == true,
    );
  }

  final String participantId;
  final String? seasonPlayerId;
  final String? guestPlayerId;
  final String displayName;
  final bool isGuest;
  final bool isGoalkeeper;
  final String plannedZone;
  final bool present;
  final SportFinalSelectionStatus selectionStatus;
  final int goals;
  final bool cleanSheet;

  SportFinalParticipant copyWith({
    bool? present,
    SportFinalSelectionStatus? selectionStatus,
    int? goals,
    bool? cleanSheet,
  }) {
    final nextPresent = present ?? this.present;
    return SportFinalParticipant(
      participantId: participantId,
      seasonPlayerId: seasonPlayerId,
      guestPlayerId: guestPlayerId,
      displayName: displayName,
      isGuest: isGuest,
      isGoalkeeper: isGoalkeeper,
      plannedZone: plannedZone,
      present: nextPresent,
      selectionStatus: nextPresent
          ? (selectionStatus ?? this.selectionStatus)
          : SportFinalSelectionStatus.notSelected,
      goals: nextPresent ? (goals ?? this.goals) : 0,
      cleanSheet: nextPresent ? (cleanSheet ?? this.cleanSheet) : false,
    );
  }

  Map<String, dynamic> toRpcJson() {
    return {
      'participant_id': participantId,
      'present': present,
      'final_selection_status': selectionStatus.wireValue,
      'goals': goals,
      'clean_sheet': cleanSheet,
    };
  }
}

class SportMatchFinalization {
  const SportMatchFinalization({
    required this.matchId,
    required this.opponentName,
    required this.kickoffAt,
    required this.matchStatus,
    required this.isValidated,
    required this.version,
    required this.scoreAsGrinta,
    required this.scoreAdverse,
    required this.compositionVersion,
    required this.presenceState,
    required this.voteState,
    required this.participants,
    this.validatedAt,
    this.correctedAt,
  });

  factory SportMatchFinalization.fromRpc(Object? raw) {
    final json = _map(raw);
    final participantsRaw = json['participants'];
    return SportMatchFinalization(
      matchId: json['match_id'].toString(),
      opponentName: (json['opponent_name'] ?? 'Adversaire').toString(),
      kickoffAt: DateTime.parse(json['kickoff_at'].toString()).toLocal(),
      matchStatus: (json['match_status'] ?? 'a_venir').toString(),
      isValidated: json['is_validated'] == true,
      version: (json['version'] as num?)?.toInt() ?? 0,
      scoreAsGrinta: (json['score_as_grinta'] as num?)?.toInt() ?? 0,
      scoreAdverse: (json['score_adverse'] as num?)?.toInt() ?? 0,
      compositionVersion: (json['composition_version'] as num?)?.toInt() ?? 0,
      presenceState: (json['presence_state'] ?? 'pending').toString(),
      voteState: (json['vote_state'] ?? 'unavailable').toString(),
      validatedAt: _dateOrNull(json['validated_at']),
      correctedAt: _dateOrNull(json['corrected_at']),
      participants: participantsRaw is List
          ? participantsRaw
              .map((row) => SportFinalParticipant.fromJson(_map(row)))
              .toList()
          : const [],
    );
  }

  final String matchId;
  final String opponentName;
  final DateTime kickoffAt;
  final String matchStatus;
  final bool isValidated;
  final int version;
  final int scoreAsGrinta;
  final int scoreAdverse;
  final int compositionVersion;
  final String presenceState;
  final String voteState;
  final DateTime? validatedAt;
  final DateTime? correctedAt;
  final List<SportFinalParticipant> participants;

  int get presentCount => participants.where((p) => p.present).length;
  int get starterCount => participants
      .where(
        (p) =>
            p.present && p.selectionStatus == SportFinalSelectionStatus.starter,
      )
      .length;
  // Tout présent qui n'est pas titulaire est de fait un remplaçant (y compris
  // « présent hors composition »), pour que titulaires + remplaçants = présents.
  int get substituteCount => participants
      .where(
        (p) =>
            p.present &&
            p.selectionStatus != SportFinalSelectionStatus.starter,
      )
      .length;
  int get guestPresentCount =>
      participants.where((p) => p.present && p.isGuest).length;
  int get attributedGoals =>
      participants.fold(0, (sum, participant) => sum + participant.goals);

  SportMatchFinalization copyWith({
    int? scoreAsGrinta,
    int? scoreAdverse,
    List<SportFinalParticipant>? participants,
  }) {
    return SportMatchFinalization(
      matchId: matchId,
      opponentName: opponentName,
      kickoffAt: kickoffAt,
      matchStatus: matchStatus,
      isValidated: isValidated,
      version: version,
      scoreAsGrinta: scoreAsGrinta ?? this.scoreAsGrinta,
      scoreAdverse: scoreAdverse ?? this.scoreAdverse,
      compositionVersion: compositionVersion,
      presenceState: presenceState,
      voteState: voteState,
      validatedAt: validatedAt,
      correctedAt: correctedAt,
      participants: participants ?? this.participants,
    );
  }
}

Map<String, dynamic> _map(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  throw const FormatException('Réponse de finalisation sportive invalide.');
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}

DateTime? _dateOrNull(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty || text == 'null') return null;
  return DateTime.tryParse(text)?.toLocal();
}
