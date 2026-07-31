enum MatchLiveState {
  notStarted,
  running,
  paused,
  halftime,
  finished;

  static MatchLiveState fromWire(Object? value) {
    return switch (value?.toString()) {
      'running' => MatchLiveState.running,
      'paused' => MatchLiveState.paused,
      'halftime' => MatchLiveState.halftime,
      'finished' => MatchLiveState.finished,
      _ => MatchLiveState.notStarted,
    };
  }
}

/// État du chronomètre du Tableau Blanc : reproduit le modèle "stopwatch"
/// stocké côté serveur (elapsed_seconds + running_since). Seules les
/// transitions d'état sont synchronisées ; le défilement affiché est
/// recalculé localement via [elapsedAt], jamais poussé seconde par seconde.
class MatchLiveSession {
  const MatchLiveSession({
    required this.matchId,
    required this.sessionExists,
    required this.state,
    required this.planPlannedDurationMinutes,
    required this.half,
    required this.elapsedSeconds,
    required this.scoreAsGrinta,
    required this.scoreAdverse,
    required this.exported,
    required this.lineupRevision,
    this.runningSince,
    this.startedAt,
    this.finishedAt,
    this.exportedAt,
  });

  factory MatchLiveSession.fromJson(Map<String, dynamic> json) {
    return MatchLiveSession(
      matchId: (json['match_id'] ?? '').toString(),
      sessionExists: json['session_exists'] == true,
      state: MatchLiveState.fromWire(json['state']),
      planPlannedDurationMinutes:
          (json['planned_duration_minutes'] as num?)?.toInt() ?? 90,
      half: (json['half'] as num?)?.toInt() ?? 1,
      elapsedSeconds: (json['elapsed_seconds'] as num?)?.toInt() ?? 0,
      runningSince: _dateOrNull(json['running_since']),
      scoreAsGrinta: (json['score_as_grinta'] as num?)?.toInt() ?? 0,
      scoreAdverse: (json['score_adverse'] as num?)?.toInt() ?? 0,
      startedAt: _dateOrNull(json['started_at']),
      finishedAt: _dateOrNull(json['finished_at']),
      exported: json['exported'] == true,
      exportedAt: _dateOrNull(json['exported_at']),
      lineupRevision: (json['lineup_revision'] as num?)?.toInt() ?? 0,
    );
  }

  final String matchId;
  final bool sessionExists;
  final MatchLiveState state;
  final int planPlannedDurationMinutes;
  final int half;
  final int elapsedSeconds;
  final DateTime? runningSince;
  final int scoreAsGrinta;
  final int scoreAdverse;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final bool exported;
  final DateTime? exportedAt;
  final int lineupRevision;

  bool get isLive =>
      state == MatchLiveState.running ||
      state == MatchLiveState.paused ||
      state == MatchLiveState.halftime;

  /// Temps écoulé calculé localement à l'instant [now], sans dépendre d'une
  /// mise à jour réseau seconde par seconde.
  Duration elapsedAt(DateTime now) {
    var seconds = elapsedSeconds;
    if (state == MatchLiveState.running && runningSince != null) {
      seconds += now.difference(runningSince!).inSeconds.clamp(0, 1 << 30);
    }
    return Duration(seconds: seconds);
  }

  int displayMinuteAt(DateTime now) => elapsedAt(now).inMinutes + 1;
}

DateTime? _dateOrNull(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty || text == 'null') return null;
  return DateTime.tryParse(text)?.toLocal();
}
