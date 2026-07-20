import 'package:as_grinta/features/sports_management/domain/sport_motm_vote.dart';

DateTime? _parseDate(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : DateTime.tryParse(text);
}

class AdminMotmListItem {
  const AdminMotmListItem({
    required this.matchId,
    required this.opponentName,
    required this.kickoffAt,
    required this.scoreAsGrinta,
    required this.scoreAdverse,
    required this.state,
    required this.opensAt,
    required this.closesAt,
    required this.closedAt,
    required this.finalizationVersion,
    required this.eligibleVoterCount,
    required this.votesReceived,
    required this.candidateCount,
    required this.participationRate,
    required this.openNotificationSent,
    required this.reminderNotificationSent,
    required this.resultsNotificationSent,
  });

  factory AdminMotmListItem.fromJson(Map<String, dynamic> json) {
    return AdminMotmListItem(
      matchId: json['match_id'].toString(),
      opponentName: (json['opponent_name'] ?? 'Adversaire').toString(),
      kickoffAt: _parseDate(json['kickoff_at']),
      scoreAsGrinta: (json['score_as_grinta'] as num?)?.toInt(),
      scoreAdverse: (json['score_adverse'] as num?)?.toInt(),
      state: SportMotmVoteState.parse(json['state']),
      opensAt: _parseDate(json['opens_at']),
      closesAt: _parseDate(json['closes_at']),
      closedAt: _parseDate(json['closed_at']),
      finalizationVersion: (json['finalization_version'] as num?)?.toInt() ?? 0,
      eligibleVoterCount: (json['eligible_voter_count'] as num?)?.toInt() ?? 0,
      votesReceived: (json['votes_received'] as num?)?.toInt() ?? 0,
      candidateCount: (json['candidate_count'] as num?)?.toInt() ?? 0,
      participationRate: (json['participation_rate'] as num?)?.toDouble() ?? 0,
      openNotificationSent: json['open_notification_sent'] == true,
      reminderNotificationSent: json['reminder_notification_sent'] == true,
      resultsNotificationSent: json['results_notification_sent'] == true,
    );
  }

  final String matchId;
  final String opponentName;
  final DateTime? kickoffAt;
  final int? scoreAsGrinta;
  final int? scoreAdverse;
  final SportMotmVoteState state;
  final DateTime? opensAt;
  final DateTime? closesAt;
  final DateTime? closedAt;
  final int finalizationVersion;
  final int eligibleVoterCount;
  final int votesReceived;
  final int candidateCount;
  final double participationRate;
  final bool openNotificationSent;
  final bool reminderNotificationSent;
  final bool resultsNotificationSent;
}

class AdminMotmAction {
  const AdminMotmAction({
    required this.action,
    required this.reason,
    required this.createdAt,
    required this.actorName,
  });

  factory AdminMotmAction.fromJson(Map<String, dynamic> json) {
    return AdminMotmAction(
      action: (json['action'] ?? '').toString(),
      reason: json['reason']?.toString(),
      createdAt: _parseDate(json['created_at']),
      actorName: (json['actor_name'] ?? 'Système').toString(),
    );
  }

  final String action;
  final String? reason;
  final DateTime? createdAt;
  final String actorName;
}

class AdminMotmWinner {
  const AdminMotmWinner({
    required this.displayName,
    required this.isGuest,
    required this.votesCount,
  });

  factory AdminMotmWinner.fromJson(Map<String, dynamic> json) {
    return AdminMotmWinner(
      displayName: (json['display_name'] ?? 'Joueur').toString(),
      isGuest: json['is_guest'] == true,
      votesCount: (json['votes_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String displayName;
  final bool isGuest;
  final int votesCount;
}

class AdminMotmDashboard {
  const AdminMotmDashboard({
    required this.summary,
    required this.totalVotes,
    required this.maxVotes,
    required this.openNotificationSent,
    required this.reminderNotificationSent,
    required this.resultsNotificationSent,
    required this.winners,
    required this.actions,
  });

  factory AdminMotmDashboard.fromJson(Map<String, dynamic> json) {
    final notifications = Map<String, dynamic>.from(
      (json['notifications'] as Map?) ?? const {},
    );
    return AdminMotmDashboard(
      summary: AdminMotmListItem.fromJson({
        ...json,
        'open_notification_sent': notifications['open'],
        'reminder_notification_sent': notifications['reminder'],
        'results_notification_sent': notifications['results'],
      }),
      totalVotes: (json['total_votes'] as num?)?.toInt(),
      maxVotes: (json['max_votes'] as num?)?.toInt(),
      openNotificationSent: notifications['open'] == true,
      reminderNotificationSent: notifications['reminder'] == true,
      resultsNotificationSent: notifications['results'] == true,
      winners: (json['winners'] as List? ?? const [])
          .map(
            (item) => AdminMotmWinner.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      actions: (json['actions'] as List? ?? const [])
          .map(
            (item) => AdminMotmAction.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  final AdminMotmListItem summary;
  final int? totalVotes;
  final int? maxVotes;
  final bool openNotificationSent;
  final bool reminderNotificationSent;
  final bool resultsNotificationSent;
  final List<AdminMotmWinner> winners;
  final List<AdminMotmAction> actions;
}

class SportStatisticsIntegrity {
  const SportStatisticsIntegrity({
    required this.matchId,
    required this.finalizationVersion,
    required this.attendanceOk,
    required this.goalsOk,
    required this.cleanSheetsOk,
    required this.motmOk,
    required this.allOk,
  });

  factory SportStatisticsIntegrity.fromJson(Map<String, dynamic> json) {
    return SportStatisticsIntegrity(
      matchId: json['match_id'].toString(),
      finalizationVersion: (json['finalization_version'] as num?)?.toInt() ?? 0,
      attendanceOk: json['attendance_ok'] == true,
      goalsOk: json['goals_ok'] == true,
      cleanSheetsOk: json['clean_sheets_ok'] == true,
      motmOk: json['motm_ok'] == true,
      allOk: json['all_ok'] == true,
    );
  }

  final String matchId;
  final int finalizationVersion;
  final bool attendanceOk;
  final bool goalsOk;
  final bool cleanSheetsOk;
  final bool motmOk;
  final bool allOk;
}
