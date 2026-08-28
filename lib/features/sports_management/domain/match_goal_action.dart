/// Camp qui a marqué le but.
enum MatchGoalTeamSide {
  asGrinta,
  opponent;

  static MatchGoalTeamSide fromWire(Object? value) {
    return value?.toString() == 'opponent'
        ? MatchGoalTeamSide.opponent
        : MatchGoalTeamSide.asGrinta;
  }

  String get wireValue => switch (this) {
        MatchGoalTeamSide.asGrinta => 'as_grinta',
        MatchGoalTeamSide.opponent => 'opponent',
      };
}

/// Ce que l'on sait de la passe décisive d'un but.
///
/// « Aucune passe » et « passe non attribuée » sont deux réponses différentes :
/// la première dit qu'il n'y en a pas eu, la seconde qu'on ne l'a pas notée.
enum MatchGoalAssistKind {
  player,
  none,
  unknown;

  static MatchGoalAssistKind fromWire(Object? value) {
    return switch (value?.toString()) {
      'player' => MatchGoalAssistKind.player,
      'none' => MatchGoalAssistKind.none,
      _ => MatchGoalAssistKind.unknown,
    };
  }

  String get wireValue => switch (this) {
        MatchGoalAssistKind.player => 'player',
        MatchGoalAssistKind.none => 'none',
        MatchGoalAssistKind.unknown => 'unknown',
      };
}

/// Minute la plus tardive acceptée. Les arrêts de jeu ne sont pas modélisés :
/// un but à la 90+4 se saisit à la 90ᵉ, ou sans minute.
const int kMatchGoalMaxMinute = 90;

/// Un but du compte rendu, des deux camps.
///
/// C'est le fait sportif définitif : il porte le lien exact but → buteur →
/// passeur, indépendamment du journal du suivi en direct.
class MatchGoalAction {
  const MatchGoalAction({
    required this.localKey,
    required this.teamSide,
    this.id,
    this.minute,
    this.scorerParticipantId,
    this.scorerName,
    this.assistParticipantId,
    this.assistName,
    this.assistKind = MatchGoalAssistKind.unknown,
    this.isOwnGoal = false,
    this.source = 'manual',
    this.sourceLiveEventId,
  });

  factory MatchGoalAction.fromJson(Map<String, dynamic> json, int index) {
    final assistParticipantId = _nullableText(json['assist_participant_id']);
    return MatchGoalAction(
      localKey: _nullableText(json['id']) ?? 'goal-$index',
      id: _nullableText(json['id']),
      minute: (json['minute'] as num?)?.toInt(),
      teamSide: MatchGoalTeamSide.fromWire(json['team_side']),
      scorerParticipantId: _nullableText(json['scorer_participant_id']),
      scorerName: _nullableText(json['scorer_name']),
      assistParticipantId: assistParticipantId,
      assistName: _nullableText(json['assist_name']),
      assistKind: assistParticipantId != null
          ? MatchGoalAssistKind.player
          : MatchGoalAssistKind.fromWire(json['assist_kind']),
      isOwnGoal: json['is_own_goal'] == true,
      source: (json['source'] ?? 'manual').toString(),
      sourceLiveEventId: _nullableText(json['source_live_event_id']),
    );
  }

  /// Nouveau but créé depuis l'écran, pas encore enregistré.
  factory MatchGoalAction.blank({
    required String localKey,
    required MatchGoalTeamSide teamSide,
  }) {
    return MatchGoalAction(
      localKey: localKey,
      teamSide: teamSide,
      assistKind: teamSide == MatchGoalTeamSide.asGrinta
          ? MatchGoalAssistKind.unknown
          : MatchGoalAssistKind.none,
    );
  }

  /// Identité stable dans la liste affichée, y compris avant enregistrement.
  final String localKey;
  final String? id;

  /// Minute du but, facultative. Renseignée, elle vaut de 0 à 90.
  final int? minute;
  final MatchGoalTeamSide teamSide;
  final String? scorerParticipantId;
  final String? scorerName;
  final String? assistParticipantId;
  final String? assistName;
  final MatchGoalAssistKind assistKind;

  /// But contre son camp : côté AS Grinta c'est un CSC adverse, côté adverse
  /// c'est un joueur d'AS Grinta qui marque contre son camp.
  final bool isOwnGoal;
  final String source;
  final String? sourceLiveEventId;

  bool get isAsGrinta => teamSide == MatchGoalTeamSide.asGrinta;

  /// Un but d'AS Grinta dont le buteur reste à désigner.
  bool get hasUnknownScorer =>
      isAsGrinta && !isOwnGoal && scorerParticipantId == null;

  /// Seul un but d'AS Grinta réellement marqué par un joueur peut porter une
  /// passe décisive.
  bool get canCarryAssist => isAsGrinta && !isOwnGoal;

  MatchGoalAction _copy({
    Object? minute = _keep,
    String? scorerParticipantId,
    String? scorerName,
    String? assistParticipantId,
    String? assistName,
    MatchGoalAssistKind? assistKind,
    bool? isOwnGoal,
  }) {
    return MatchGoalAction(
      localKey: localKey,
      id: id,
      minute: identical(minute, _keep) ? this.minute : minute as int?,
      teamSide: teamSide,
      scorerParticipantId: scorerParticipantId,
      scorerName: scorerName,
      assistParticipantId: assistParticipantId,
      assistName: assistName,
      assistKind: assistKind ?? this.assistKind,
      isOwnGoal: isOwnGoal ?? this.isOwnGoal,
      source: source,
      sourceLiveEventId: sourceLiveEventId,
    );
  }

  MatchGoalAction withMinute(int? minute) => _copy(
        minute: minute,
        scorerParticipantId: scorerParticipantId,
        scorerName: scorerName,
        assistParticipantId: assistParticipantId,
        assistName: assistName,
      );

  /// Attribue le but à un joueur. Si ce joueur était le passeur, la passe
  /// redevient « non attribuée » : personne ne se fait de passe à soi-même.
  MatchGoalAction withScorer(String participantId, String displayName) {
    final keepsAssist =
        assistParticipantId != null && assistParticipantId != participantId;
    return _copy(
      scorerParticipantId: participantId,
      scorerName: displayName,
      assistParticipantId: keepsAssist ? assistParticipantId : null,
      assistName: keepsAssist ? assistName : null,
      assistKind: keepsAssist
          ? MatchGoalAssistKind.player
          : (assistKind == MatchGoalAssistKind.none
              ? MatchGoalAssistKind.none
              : MatchGoalAssistKind.unknown),
      isOwnGoal: false,
    );
  }

  /// Buteur inconnu : le but reste au score, sans être crédité à personne.
  /// Sans buteur, aucune passe décisive n'est possible.
  MatchGoalAction withUnknownScorer() => _copy(
        assistKind: MatchGoalAssistKind.unknown,
        isOwnGoal: false,
      );

  /// Contre-son-camp : CSC adverse côté AS Grinta, CSC AS Grinta côté adverse.
  MatchGoalAction withOwnGoal() => _copy(
        assistKind: MatchGoalAssistKind.none,
        isOwnGoal: true,
      );

  /// But adverse ordinaire, sans contre-son-camp.
  MatchGoalAction withoutOwnGoal() => _copy(
        assistKind:
            isAsGrinta ? MatchGoalAssistKind.unknown : MatchGoalAssistKind.none,
        isOwnGoal: false,
      );

  MatchGoalAction withAssist(String participantId, String displayName) {
    if (!canCarryAssist ||
        scorerParticipantId == null ||
        participantId == scorerParticipantId) {
      return this;
    }
    return _copy(
      scorerParticipantId: scorerParticipantId,
      scorerName: scorerName,
      assistParticipantId: participantId,
      assistName: displayName,
      assistKind: MatchGoalAssistKind.player,
    );
  }

  MatchGoalAction withNoAssist() => _copy(
        scorerParticipantId: scorerParticipantId,
        scorerName: scorerName,
        assistKind: MatchGoalAssistKind.none,
      );

  MatchGoalAction withUnknownAssist() => _copy(
        scorerParticipantId: scorerParticipantId,
        scorerName: scorerName,
        assistKind: canCarryAssist
            ? MatchGoalAssistKind.unknown
            : MatchGoalAssistKind.none,
      );

  /// Un joueur retiré de l'effectif perd ses attributions, mais le but reste.
  MatchGoalAction withoutParticipant(String participantId) {
    final losesScorer = scorerParticipantId == participantId;
    final losesAssist = assistParticipantId == participantId;
    if (!losesScorer && !losesAssist) return this;
    if (losesScorer) return withUnknownScorer();
    return withUnknownAssist();
  }

  Map<String, dynamic> toRpcJson() {
    return {
      'minute': minute,
      'team_side': teamSide.wireValue,
      'scorer_participant_id': scorerParticipantId,
      'assist_participant_id': assistParticipantId,
      'assist_kind': assistKind.wireValue,
      'is_own_goal': isOwnGoal,
      'source': source,
      'source_live_event_id': sourceLiveEventId,
    };
  }
}

const Object _keep = Object();

String? _nullableText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}
