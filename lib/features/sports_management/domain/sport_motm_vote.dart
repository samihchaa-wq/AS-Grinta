enum SportMotmVoteState {
  unavailable,
  draft,
  open,
  closed,
  cancelled;

  static SportMotmVoteState parse(Object? value) {
    return switch (value?.toString()) {
      'draft' => SportMotmVoteState.draft,
      'open' => SportMotmVoteState.open,
      'closed' => SportMotmVoteState.closed,
      'cancelled' => SportMotmVoteState.cancelled,
      _ => SportMotmVoteState.unavailable,
    };
  }
}

class SportMotmCandidate {
  const SportMotmCandidate({
    required this.participantId,
    required this.displayName,
    required this.isGuest,
    required this.isGoalkeeper,
    required this.isSelf,
    required this.canChoose,
    required this.votesCount,
    required this.isWinner,
  });

  factory SportMotmCandidate.fromJson(Map<String, dynamic> json) {
    return SportMotmCandidate(
      participantId: json['participant_id'].toString(),
      displayName: (json['display_name'] ?? 'Joueur').toString(),
      isGuest: json['is_guest'] == true,
      isGoalkeeper: json['is_goalkeeper'] == true,
      isSelf: json['is_self'] == true,
      canChoose: json['can_choose'] == true,
      votesCount: (json['votes_count'] as num?)?.toInt(),
      isWinner: json['is_winner'] == true,
    );
  }

  final String participantId;
  final String displayName;
  final bool isGuest;
  final bool isGoalkeeper;
  final bool isSelf;
  final bool canChoose;
  final int? votesCount;
  final bool isWinner;
}

class SportMotmVote {
  const SportMotmVote({
    required this.matchId,
    required this.opponentName,
    required this.isHome,
    required this.scoreAsGrinta,
    required this.scoreAdverse,
    required this.state,
    required this.opensAt,
    required this.closesAt,
    required this.closedAt,
    required this.finalizationVersion,
    required this.hasVoted,
    required this.canVote,
    required this.isEligibleVoter,
    required this.totalVotes,
    required this.maxVotes,
    required this.candidates,
  });

  factory SportMotmVote.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? value) {
      final text = value?.toString();
      return text == null || text.isEmpty ? null : DateTime.tryParse(text);
    }

    return SportMotmVote(
      matchId: json['match_id'].toString(),
      opponentName: (json['opponent_name'] ?? 'Adversaire').toString(),
      isHome: json['is_home'] != false,
      scoreAsGrinta: (json['score_as_grinta'] as num?)?.toInt(),
      scoreAdverse: (json['score_adverse'] as num?)?.toInt(),
      state: SportMotmVoteState.parse(json['state']),
      opensAt: parseDate(json['opens_at']),
      closesAt: parseDate(json['closes_at']),
      closedAt: parseDate(json['closed_at']),
      finalizationVersion: (json['finalization_version'] as num?)?.toInt() ?? 0,
      hasVoted: json['has_voted'] == true,
      canVote: json['can_vote'] == true,
      isEligibleVoter: json['is_eligible_voter'] == true,
      totalVotes: (json['total_votes'] as num?)?.toInt(),
      maxVotes: (json['max_votes'] as num?)?.toInt(),
      candidates: (json['candidates'] as List? ?? const [])
          .map(
            (candidate) => SportMotmCandidate.fromJson(
              Map<String, dynamic>.from(candidate as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  final String matchId;
  final String opponentName;
  final bool isHome;
  final int? scoreAsGrinta;
  final int? scoreAdverse;
  final SportMotmVoteState state;
  final DateTime? opensAt;
  final DateTime? closesAt;
  final DateTime? closedAt;
  final int finalizationVersion;
  final bool hasVoted;
  final bool canVote;
  final bool isEligibleVoter;
  final int? totalVotes;
  final int? maxVotes;
  final List<SportMotmCandidate> candidates;

  List<SportMotmCandidate> get winners => candidates
      .where((candidate) => candidate.isWinner)
      .toList(growable: false);

  bool get isOpen => state == SportMotmVoteState.open;
  bool get isClosed => state == SportMotmVoteState.closed;

  /// Le score n'est connu qu'une fois la feuille de match validée.
  bool get hasScore => scoreAsGrinta != null && scoreAdverse != null;

  /// Intitulé du match avec l'équipe qui reçoit affichée en premier, comme sur
  /// le reste de l'app (domicile à gauche).
  String get matchTitle {
    const grinta = 'AS Grinta';
    if (!hasScore) {
      return isHome ? '$grinta – $opponentName' : '$opponentName – $grinta';
    }
    return isHome
        ? '$grinta $scoreAsGrinta – $scoreAdverse $opponentName'
        : '$opponentName $scoreAdverse – $scoreAsGrinta $grinta';
  }
}
