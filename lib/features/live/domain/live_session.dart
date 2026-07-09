class LiveSessionState {
  const LiveSessionState({
    required this.id,
    required this.matchId,
    required this.status,
    required this.elapsedSeconds,
    required this.controllerProfileId,
    required this.controllerSessionId,
    required this.controllerDisconnectedAt,
    required this.clockStartedAt,
    required this.formation,
  });

  final String? id;
  final String? matchId;
  final String status;
  final int elapsedSeconds;
  final String? controllerProfileId;
  final String? controllerSessionId;
  final DateTime? controllerDisconnectedAt;
  final DateTime? clockStartedAt;
  final String? formation;

  factory LiveSessionState.fromJson(Map<String, dynamic> json) {
    return LiveSessionState(
      id: json['id']?.toString(),
      matchId: json['match_id']?.toString(),
      status: (json['status'] ?? 'not_started').toString(),
      elapsedSeconds: int.tryParse('${json['elapsed_seconds'] ?? 0}') ?? 0,
      controllerProfileId: json['controller_profile_id']?.toString(),
      controllerSessionId: json['controller_session_id']?.toString(),
      controllerDisconnectedAt:
          DateTime.tryParse('${json['controller_disconnected_at'] ?? ''}'),
      clockStartedAt: DateTime.tryParse(
        '${json['clock_started_at'] ?? json['started_at'] ?? ''}',
      ),
      formation: json['formation']?.toString(),
    );
  }
}
