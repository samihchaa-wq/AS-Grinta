/// Un joueur convoqué pour un « match entre nous », éventuellement déjà
/// affecté à une des deux équipes (`teamNo` = 1 ou 2, null = non affecté).
class InternalCompositionEntry {
  const InternalCompositionEntry({
    required this.participantId,
    required this.displayName,
    required this.isGuest,
    required this.isGoalkeeper,
    this.seasonPlayerId,
    this.guestPlayerId,
    this.photoUrl,
    this.lastInitial,
    this.teamNo,
    this.sortOrder = 0,
  });

  final String participantId;
  final String? seasonPlayerId;
  final String? guestPlayerId;
  final String displayName;

  /// Initiale du nom de famille, pour la pastille des joueurs sans photo.
  final String? lastInitial;
  final String? photoUrl;
  final bool isGuest;
  final bool isGoalkeeper;
  final int? teamNo;
  final int sortOrder;

  InternalCompositionEntry copyWith({int? teamNo, bool clearTeam = false}) {
    return InternalCompositionEntry(
      participantId: participantId,
      seasonPlayerId: seasonPlayerId,
      guestPlayerId: guestPlayerId,
      displayName: displayName,
      lastInitial: lastInitial,
      photoUrl: photoUrl,
      isGuest: isGuest,
      isGoalkeeper: isGoalkeeper,
      teamNo: clearTeam ? null : (teamNo ?? this.teamNo),
      sortOrder: sortOrder,
    );
  }

  factory InternalCompositionEntry.fromJson(Map<String, dynamic> json) {
    return InternalCompositionEntry(
      participantId: json['participant_id'].toString(),
      seasonPlayerId: json['season_player_id']?.toString(),
      guestPlayerId: json['guest_player_id']?.toString(),
      displayName: (json['display_name'] ?? 'Joueur').toString(),
      lastInitial: json['last_initial']?.toString(),
      photoUrl: json['photo_url']?.toString(),
      isGuest: json['is_guest'] == true,
      isGoalkeeper: json['is_goalkeeper'] == true,
      teamNo: (json['team_no'] as num?)?.toInt(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toRpcJson() => {
        'participant_id': participantId,
        'team_no': teamNo,
        'sort_order': sortOrder,
      };
}

class InternalMatchComposition {
  const InternalMatchComposition({
    required this.matchId,
    required this.team1Name,
    required this.team2Name,
    required this.entries,
    this.team1JerseyId = 'orange',
    this.team2JerseyId = 'blue',
    this.notificationSent = false,
  });

  final String matchId;
  final String team1Name;
  final String team2Name;
  final String team1JerseyId;
  final String team2JerseyId;
  final List<InternalCompositionEntry> entries;

  /// La notification « La composition est en ligne » est-elle déjà partie pour
  /// ce match ? Le serveur en garde la trace : elle ne part qu'une fois.
  final bool notificationSent;

  List<InternalCompositionEntry> get unassigned =>
      entries.where((e) => e.teamNo == null).toList();
  List<InternalCompositionEntry> get team1 =>
      entries.where((e) => e.teamNo == 1).toList();
  List<InternalCompositionEntry> get team2 =>
      entries.where((e) => e.teamNo == 2).toList();

  static InternalMatchComposition? tryFromRpc(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final entriesRaw = json['entries'];
    return InternalMatchComposition(
      matchId: json['match_id']?.toString() ?? '',
      team1Name: (json['team1_name'] ?? 'Équipe 1').toString(),
      team2Name: (json['team2_name'] ?? 'Équipe 2').toString(),
      team1JerseyId: (json['team1_jersey'] ?? 'orange').toString(),
      team2JerseyId: (json['team2_jersey'] ?? 'blue').toString(),
      notificationSent: json['notification_sent'] == true,
      entries: entriesRaw is List
          ? entriesRaw
              .map(
                (e) => InternalCompositionEntry.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList()
          : const [],
    );
  }
}
