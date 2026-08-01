enum MatchLiveEventType {
  goalUs,
  goalThem,
  substitution;

  static MatchLiveEventType fromWire(Object? value) {
    return switch (value?.toString()) {
      'goal_us' => MatchLiveEventType.goalUs,
      'goal_them' => MatchLiveEventType.goalThem,
      _ => MatchLiveEventType.substitution,
    };
  }
}

class MatchLiveEvent {
  const MatchLiveEvent({
    required this.id,
    required this.type,
    required this.minute,
    required this.half,
    this.scorerParticipantId,
    this.scorerName,
    this.scoreAsGrintaAfter,
    this.scoreAdverseAfter,
    this.playerInParticipantId,
    this.playerInName,
    this.playerOutParticipantId,
    this.playerOutName,
    this.isOpponentOwnGoal = false,
  });

  factory MatchLiveEvent.fromJson(Map<String, dynamic> json) {
    return MatchLiveEvent(
      id: (json['id'] ?? '').toString(),
      type: MatchLiveEventType.fromWire(json['event_type']),
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      half: (json['half'] as num?)?.toInt() ?? 1,
      scorerParticipantId: _nullableText(json['scorer_participant_id']),
      scorerName: _nullableText(json['scorer_name']),
      scoreAsGrintaAfter: (json['score_as_grinta_after'] as num?)?.toInt(),
      scoreAdverseAfter: (json['score_adverse_after'] as num?)?.toInt(),
      playerInParticipantId: _nullableText(json['player_in_participant_id']),
      playerInName: _nullableText(json['player_in_name']),
      playerOutParticipantId: _nullableText(json['player_out_participant_id']),
      playerOutName: _nullableText(json['player_out_name']),
      isOpponentOwnGoal: json['is_opponent_own_goal'] == true,
    );
  }

  final String id;
  final MatchLiveEventType type;
  final int minute;
  final int half;
  final String? scorerParticipantId;
  final String? scorerName;
  final int? scoreAsGrintaAfter;
  final int? scoreAdverseAfter;
  final String? playerInParticipantId;
  final String? playerInName;
  final String? playerOutParticipantId;
  final String? playerOutName;

  /// But d'AS Grinta marqué contre son camp par l'adversaire : il compte au
  /// score mais n'est crédité à aucun joueur.
  final bool isOpponentOwnGoal;

  /// Un but d'AS Grinta dont le buteur reste à désigner.
  bool get needsScorer =>
      type == MatchLiveEventType.goalUs &&
      scorerParticipantId == null &&
      !isOpponentOwnGoal;
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}
