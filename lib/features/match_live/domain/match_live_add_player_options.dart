class MatchLiveAddPlayerOption {
  const MatchLiveAddPlayerOption({
    required this.displayName,
    required this.isGoalkeeper,
    required this.isGuest,
    this.participantId,
    this.seasonPlayerId,
    this.guestPlayerId,
    this.photoUrl,
  });

  factory MatchLiveAddPlayerOption.fromJson(Map<String, dynamic> json) {
    return MatchLiveAddPlayerOption(
      participantId: _nullableText(json['participant_id']),
      seasonPlayerId: _nullableText(json['season_player_id']),
      guestPlayerId: _nullableText(json['guest_player_id']),
      displayName: (json['display_name'] ?? 'Joueur').toString().trim(),
      photoUrl: _nullableText(json['photo_url']),
      isGoalkeeper: json['is_goalkeeper'] == true,
      isGuest: json['is_guest'] == true,
    );
  }

  final String? participantId;
  final String? seasonPlayerId;
  final String? guestPlayerId;
  final String displayName;
  final String? photoUrl;
  final bool isGoalkeeper;
  final bool isGuest;
}

class MatchLiveAddPlayerOptions {
  const MatchLiveAddPlayerOptions({
    required this.matchId,
    required this.sessionState,
    required this.roster,
    required this.guests,
  });

  factory MatchLiveAddPlayerOptions.fromRpc(Object? raw) {
    final json = _map(raw);
    return MatchLiveAddPlayerOptions(
      matchId: (json['match_id'] ?? '').toString(),
      sessionState: (json['session_state'] ?? '').toString(),
      roster: _options(json['roster']),
      guests: _options(json['guests']),
    );
  }

  final String matchId;
  final String sessionState;
  final List<MatchLiveAddPlayerOption> roster;
  final List<MatchLiveAddPlayerOption> guests;
}

class MatchLiveAddPlayerRequest {
  const MatchLiveAddPlayerRequest._({
    required this.kind,
    this.seasonPlayerId,
    this.guestPlayerId,
    this.firstName,
    this.lastName,
    this.isGoalkeeper = false,
  });

  factory MatchLiveAddPlayerRequest.roster(String seasonPlayerId) {
    return MatchLiveAddPlayerRequest._(
      kind: 'roster',
      seasonPlayerId: seasonPlayerId,
    );
  }

  factory MatchLiveAddPlayerRequest.guest(String guestPlayerId) {
    return MatchLiveAddPlayerRequest._(
      kind: 'guest',
      guestPlayerId: guestPlayerId,
    );
  }

  factory MatchLiveAddPlayerRequest.newGuest({
    required String firstName,
    String? lastName,
    bool isGoalkeeper = false,
  }) {
    return MatchLiveAddPlayerRequest._(
      kind: 'new_guest',
      firstName: firstName.trim(),
      lastName: _nullableText(lastName),
      isGoalkeeper: isGoalkeeper,
    );
  }

  final String kind;
  final String? seasonPlayerId;
  final String? guestPlayerId;
  final String? firstName;
  final String? lastName;
  final bool isGoalkeeper;

  Map<String, dynamic> toRpcJson() {
    return {
      'kind': kind,
      'season_player_id': seasonPlayerId,
      'guest_player_id': guestPlayerId,
      'first_name': firstName,
      'last_name': lastName,
      'is_goalkeeper': isGoalkeeper,
    };
  }
}

List<MatchLiveAddPlayerOption> _options(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .map((item) => MatchLiveAddPlayerOption.fromJson(_map(item)))
      .toList(growable: false);
}

Map<String, dynamic> _map(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const {};
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}
