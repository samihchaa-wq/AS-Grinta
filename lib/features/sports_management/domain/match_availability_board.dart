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
    required this.firstName,
    required this.lastName,
    required this.status,
  });

  factory MatchAvailabilityBoardPlayer.fromJson(Map<String, dynamic> json) {
    return MatchAvailabilityBoardPlayer(
      firstName: (json['first_name'] ?? '').toString().trim(),
      lastName: (json['last_name'] ?? '').toString().trim(),
      status: MatchAvailabilityBoardStatus.parse(json['status']),
    );
  }

  final String firstName;
  final String lastName;
  final MatchAvailabilityBoardStatus status;

  String get displayName {
    final fullName = '$firstName $lastName'.trim();
    return fullName.isEmpty ? 'Joueur' : fullName;
  }
}

class MatchAvailabilityBoard {
  const MatchAvailabilityBoard({
    required this.matchId,
    required this.kickoffAt,
    required this.opensAt,
    required this.state,
    required this.compositionPublished,
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
      players: (json['players'] as List? ?? const [])
          .map(
            (player) => MatchAvailabilityBoardPlayer.fromJson(
              Map<String, dynamic>.from(player as Map),
            ),
          )
          .where(
            (player) => player.status != MatchAvailabilityBoardStatus.ignored,
          )
          .toList(growable: false),
    );
  }

  final String matchId;
  final DateTime kickoffAt;
  final DateTime opensAt;
  final String state;
  final bool compositionPublished;
  final List<MatchAvailabilityBoardPlayer> players;

  bool isVisibleAt(DateTime now) =>
      state == 'open' && now.isBefore(kickoffAt) && !compositionPublished;

  List<MatchAvailabilityBoardPlayer> playersWith(
    MatchAvailabilityBoardStatus status,
  ) =>
      players
          .where((player) => player.status == status)
          .toList(growable: false);
}
