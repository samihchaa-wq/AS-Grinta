class AvailabilityReminderPlayer {
  const AvailabilityReminderPlayer({
    required this.seasonPlayerId,
    this.lastReminderAt,
    this.manualCooldownUntil,
  });

  factory AvailabilityReminderPlayer.fromJson(Map<String, dynamic> json) {
    return AvailabilityReminderPlayer(
      seasonPlayerId: (json['season_player_id'] ?? '').toString(),
      lastReminderAt: _dateOrNull(json['last_reminder_at']),
      manualCooldownUntil: _dateOrNull(json['manual_cooldown_until']),
    );
  }

  final String seasonPlayerId;
  final DateTime? lastReminderAt;
  final DateTime? manualCooldownUntil;

  bool isInCooldownAt(DateTime now) {
    final cooldown = manualCooldownUntil;
    return cooldown != null && cooldown.isAfter(now);
  }
}

class AvailabilityReminderSummary {
  const AvailabilityReminderSummary({
    required this.matchId,
    required this.availabilityState,
    required this.noResponseCount,
    required this.openSentCount,
    required this.j3SentCount,
    required this.j1SentCount,
    required this.canRemind,
    required this.players,
    this.lastManualAt,
  });

  factory AvailabilityReminderSummary.fromRpc(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Résumé de relance invalide.');
    }
    final json = Map<String, dynamic>.from(value);
    final rawPlayers = json['players'];
    final players = rawPlayers is List
        ? rawPlayers
            .whereType<Map>()
            .map(
              (row) => AvailabilityReminderPlayer.fromJson(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList(growable: false)
        : const <AvailabilityReminderPlayer>[];

    return AvailabilityReminderSummary(
      matchId: (json['match_id'] ?? '').toString(),
      availabilityState: (json['availability_state'] ?? 'pending').toString(),
      noResponseCount: (json['no_response_count'] as num?)?.toInt() ?? 0,
      openSentCount: (json['open_sent_count'] as num?)?.toInt() ?? 0,
      j3SentCount: (json['j3_sent_count'] as num?)?.toInt() ?? 0,
      j1SentCount: (json['j1_sent_count'] as num?)?.toInt() ?? 0,
      lastManualAt: _dateOrNull(json['last_manual_at']),
      canRemind: json['can_remind'] == true,
      players: players,
    );
  }

  final String matchId;
  final String availabilityState;
  final int noResponseCount;
  final int openSentCount;
  final int j3SentCount;
  final int j1SentCount;
  final DateTime? lastManualAt;
  final bool canRemind;
  final List<AvailabilityReminderPlayer> players;

  AvailabilityReminderPlayer? playerFor(String seasonPlayerId) {
    for (final player in players) {
      if (player.seasonPlayerId == seasonPlayerId) return player;
    }
    return null;
  }
}

class AvailabilityReminderResult {
  const AvailabilityReminderResult({
    required this.targetCount,
    required this.createdCount,
    required this.skippedRecentCount,
  });

  factory AvailabilityReminderResult.fromRpc(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Résultat de relance invalide.');
    }
    final json = Map<String, dynamic>.from(value);
    return AvailabilityReminderResult(
      targetCount: (json['target_count'] as num?)?.toInt() ?? 0,
      createdCount: (json['created_count'] as num?)?.toInt() ?? 0,
      skippedRecentCount: (json['skipped_recent_count'] as num?)?.toInt() ?? 0,
    );
  }

  final int targetCount;
  final int createdCount;
  final int skippedRecentCount;
}

DateTime? _dateOrNull(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
