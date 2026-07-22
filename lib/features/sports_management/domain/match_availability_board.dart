enum MatchAvailabilityBoardStatus {
  present,
  absent,
  noResponse,
  ignored;

  static MatchAvailabilityBoardStatus parse(Object? value) {
    return switch (value?.toString()) {
      'available' => MatchAvailabilityBoardStatus.present,
      'absent' => MatchAvailabilityBoardStatus.absent,
      'no_response' => MatchAvailabilityBoardStatus.noResponse,
      _ => MatchAvailabilityBoardStatus.ignored,
    };
  }
}

class MatchAvailabilityBoardPlayer {
  const MatchAvailabilityBoardPlayer({
    required this.participantId,
    required this.firstName,
    required this.lastName,
    required this.status,
    required this.convocationStatus,
    required this.isGuest,
    this.waitlistPosition,
  });

  factory MatchAvailabilityBoardPlayer.fromJson(Map<String, dynamic> json) {
    return MatchAvailabilityBoardPlayer(
      participantId: (json['participant_id'] ?? '').toString(),
      firstName: (json['first_name'] ?? '').toString().trim(),
      lastName: (json['last_name'] ?? '').toString().trim(),
      status: MatchAvailabilityBoardStatus.parse(json['status']),
      convocationStatus:
          (json['convocation_status'] ?? 'not_applicable').toString(),
      isGuest: json['is_guest'] == true,
      waitlistPosition: (json['waitlist_position'] as num?)?.toInt(),
    );
  }

  final String participantId;
  final String firstName;
  final String lastName;
  final MatchAvailabilityBoardStatus status;
  final String convocationStatus;
  final bool isGuest;
  final int? waitlistPosition;

  String get displayName {
    final fullName = '$firstName $lastName'.trim();
    return fullName.isEmpty ? 'Joueur' : fullName;
  }

  String get firstNameOnly {
    final first = firstName.trim();
    if (first.isNotEmpty) return first;
    return displayName.split(RegExp(r'\s+')).first;
  }

  bool get isConvoked =>
      (isGuest || status == MatchAvailabilityBoardStatus.present) &&
      convocationStatus == 'convoked';
  bool get isWaitlisted =>
      !isGuest &&
      status == MatchAvailabilityBoardStatus.present &&
      convocationStatus != 'convoked';
}

class MatchAvailabilityBoard {
  const MatchAvailabilityBoard({
    required this.matchId,
    required this.kickoffAt,
    required this.opensAt,
    required this.state,
    required this.compositionPublished,
    required this.squadSizeLimit,
    required this.convocationState,
    required this.players,
  });

  factory MatchAvailabilityBoard.fromRpc(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'Availability board RPC must return an object',
      );
    }
    final json = Map<String, dynamic>.from(raw);
    final kickoffAt = DateTime.tryParse('${json['kickoff_at'] ?? ''}');
    final opensAt = DateTime.tryParse('${json['availability_opens_at'] ?? ''}');
    final matchId = json['match_id']?.toString();
    if (matchId == null ||
        matchId.isEmpty ||
        kickoffAt == null ||
        opensAt == null) {
      throw const FormatException('Invalid availability board payload');
    }

    return MatchAvailabilityBoard(
      matchId: matchId,
      kickoffAt: kickoffAt.toLocal(),
      opensAt: opensAt.toLocal(),
      state: (json['availability_state'] ?? 'pending').toString(),
      compositionPublished: json['composition_published'] == true,
      squadSizeLimit: (json['squad_size_limit'] as num?)?.toInt() ?? 14,
      convocationState: (json['convocation_state'] ?? 'draft').toString(),
      players: (json['players'] as List? ?? const [])
          .map(
            (player) => MatchAvailabilityBoardPlayer.fromJson(
              Map<String, dynamic>.from(player as Map),
            ),
          )
          .where(
            (player) =>
                player.status != MatchAvailabilityBoardStatus.ignored ||
                player.isGuest,
          )
          .toList(growable: false),
    );
  }

  final String matchId;
  final DateTime kickoffAt;
  final DateTime opensAt;
  final String state;
  final bool compositionPublished;
  final int squadSizeLimit;
  final String convocationState;
  final List<MatchAvailabilityBoardPlayer> players;

  bool isVisibleAt(DateTime now) =>
      now.isBefore(kickoffAt) && !compositionPublished;

  List<MatchAvailabilityBoardPlayer> get convoked {
    final result = players.where((player) => player.isConvoked).toList();
    result.sort(_byWaitlistThenName);
    return result;
  }

  List<MatchAvailabilityBoardPlayer> get waitlisted {
    final result = players.where((player) => player.isWaitlisted).toList();
    result.sort(_byWaitlistThenName);
    return result;
  }

  List<MatchAvailabilityBoardPlayer> playersWith(
    MatchAvailabilityBoardStatus status,
  ) {
    final result = players.where((player) => player.status == status).toList();
    result.sort((a, b) => a.displayName.compareTo(b.displayName));
    return result;
  }

  static int _byWaitlistThenName(
    MatchAvailabilityBoardPlayer a,
    MatchAvailabilityBoardPlayer b,
  ) {
    final aPosition = a.waitlistPosition ?? 1 << 20;
    final bPosition = b.waitlistPosition ?? 1 << 20;
    final byPosition = aPosition.compareTo(bPosition);
    return byPosition != 0
        ? byPosition
        : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }
}
