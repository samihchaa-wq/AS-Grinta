class GuestPlayer {
  const GuestPlayer({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.displayName,
    required this.isGoalkeeper,
    required this.isReusable,
    this.archivedAt,
    this.photoUrl,
  });

  factory GuestPlayer.fromJson(Map<String, dynamic> json) {
    final rawPhoto = json['photo_url']?.toString().trim();
    return GuestPlayer(
      id: json['guest_player_id'].toString(),
      firstName: (json['first_name'] ?? '').toString(),
      lastName: (json['last_name'] ?? '').toString(),
      displayName: (json['display_name'] ?? 'Invité').toString(),
      isGoalkeeper: json['is_goalkeeper'] == true,
      isReusable: json['is_reusable'] == true,
      archivedAt: _dateOrNull(json['archived_at']),
      photoUrl: (rawPhoto != null && rawPhoto.isNotEmpty) ? rawPhoto : null,
    );
  }

  final String id;
  final String firstName;
  final String lastName;
  final String displayName;
  final bool isGoalkeeper;
  final bool isReusable;
  final DateTime? archivedAt;
  final String? photoUrl;
}

class GuestCatalog {
  const GuestCatalog({required this.guests});

  factory GuestCatalog.fromRpc(Object? raw) {
    final json = _map(raw);
    final rows = json['guests'];
    return GuestCatalog(
      guests: rows is List
          ? rows
              .map((row) => GuestPlayer.fromJson(_map(row)))
              .toList(growable: false)
          : const [],
    );
  }

  final List<GuestPlayer> guests;

  List<GuestPlayer> get active =>
      guests.where((guest) => guest.isReusable).toList(growable: false);

  List<GuestPlayer> get archived =>
      guests.where((guest) => !guest.isReusable).toList(growable: false);
}

class MatchGuestParticipant {
  const MatchGuestParticipant({
    required this.participantId,
    required this.guestPlayerId,
    required this.firstName,
    required this.lastName,
    required this.displayName,
    required this.isGoalkeeper,
    required this.isReusable,
    required this.selectionStatus,
    this.archivedAt,
  });

  factory MatchGuestParticipant.fromJson(Map<String, dynamic> json) {
    return MatchGuestParticipant(
      participantId: json['participant_id'].toString(),
      guestPlayerId: json['guest_player_id'].toString(),
      firstName: (json['first_name'] ?? '').toString(),
      lastName: (json['last_name'] ?? '').toString(),
      displayName: (json['display_name'] ?? 'Invité').toString(),
      isGoalkeeper: json['is_goalkeeper'] == true,
      isReusable: json['is_reusable'] == true,
      selectionStatus: (json['selection_status'] ?? 'undecided').toString(),
      archivedAt: _dateOrNull(json['archived_at']),
    );
  }

  final String participantId;
  final String guestPlayerId;
  final String firstName;
  final String lastName;
  final String displayName;
  final bool isGoalkeeper;
  final bool isReusable;
  final String selectionStatus;
  final DateTime? archivedAt;
}

class MatchGuests {
  const MatchGuests({required this.matchId, required this.guests});

  factory MatchGuests.fromRpc(Object? raw) {
    final json = _map(raw);
    final rows = json['guests'];
    return MatchGuests(
      matchId: (json['match_id'] ?? '').toString(),
      guests: rows is List
          ? rows
              .map((row) => MatchGuestParticipant.fromJson(_map(row)))
              .toList(growable: false)
          : const [],
    );
  }

  final String matchId;
  final List<MatchGuestParticipant> guests;
}

Map<String, dynamic> _map(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const {};
}

DateTime? _dateOrNull(Object? raw) {
  final value = raw?.toString();
  if (value == null || value.isEmpty || value == 'null') return null;
  return DateTime.tryParse(value)?.toLocal();
}
