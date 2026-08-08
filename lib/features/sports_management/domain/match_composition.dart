import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';

enum MatchCompositionZone {
  available,
  field,
  bench,
  notSelected;

  static MatchCompositionZone fromWire(Object? value) {
    return switch (value?.toString()) {
      'field' => MatchCompositionZone.field,
      'bench' => MatchCompositionZone.bench,
      'not_selected' => MatchCompositionZone.notSelected,
      _ => MatchCompositionZone.available,
    };
  }

  String get wireValue => switch (this) {
        MatchCompositionZone.available => 'available',
        MatchCompositionZone.field => 'field',
        MatchCompositionZone.bench => 'bench',
        MatchCompositionZone.notSelected => 'not_selected',
      };

  String get label => switch (this) {
        MatchCompositionZone.available => 'À placer',
        MatchCompositionZone.field => 'Titulaire',
        MatchCompositionZone.bench => 'Banc',
        MatchCompositionZone.notSelected => 'Non convoqué',
      };
}

class MatchCompositionEntry {
  const MatchCompositionEntry({
    required this.participantId,
    required this.seasonPlayerId,
    required this.displayName,
    required this.isGoalkeeper,
    required this.zone,
    required this.sortOrder,
    required this.availabilityStatus,
    required this.convocationStatus,
    required this.selectionStatus,
    this.guestPlayerId,
    this.isGuest = false,
    this.x,
    this.y,
    this.slotLabel,
    this.photoUrl,
    this.goals = 0,
    this.isMotm = false,
  });

  factory MatchCompositionEntry.fromJson(Map<String, dynamic> json) {
    final guestPlayerId = _nullableText(json['guest_player_id']);
    return MatchCompositionEntry(
      participantId: json['participant_id'].toString(),
      seasonPlayerId: json['season_player_id']?.toString() ?? '',
      guestPlayerId: guestPlayerId,
      displayName: capitalizePersonName(
        (json['display_name'] ?? 'Joueur').toString(),
      ),
      isGuest: json['is_guest'] == true || guestPlayerId != null,
      isGoalkeeper: json['is_goalkeeper'] == true,
      zone: MatchCompositionZone.fromWire(json['zone']),
      x: (json['x'] as num?)?.toDouble(),
      y: (json['y'] as num?)?.toDouble(),
      slotLabel: _nullableText(json['slot_label']),
      photoUrl: _nullableText(json['photo_url']),
      goals: (json['goals'] as num?)?.toInt() ?? 0,
      isMotm: json['is_motm'] == true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      availabilityStatus:
          (json['availability_status'] ?? 'no_response').toString(),
      convocationStatus:
          (json['convocation_status'] ?? 'not_applicable').toString(),
      selectionStatus: (json['selection_status'] ?? 'undecided').toString(),
    );
  }

  final String participantId;
  final String seasonPlayerId;
  final String? guestPlayerId;
  final String displayName;
  final bool isGuest;
  final bool isGoalkeeper;
  final MatchCompositionZone zone;
  final double? x;
  final double? y;
  final String? slotLabel;
  final String? photoUrl;
  final int goals;
  final bool isMotm;
  final int sortOrder;
  final String availabilityStatus;
  final String convocationStatus;
  final String selectionStatus;

  /// Vrai quand le joueur peut être aligné.
  ///
  /// Seule la convocation compte : l'effectif autorise à convoquer un joueur
  /// noté absent ou sans réponse, et cette décision d'administrateur prime sur
  /// la disponibilité déclarée. Le serveur applique la même règle.
  bool get canBeSelected => convocationStatus == 'convoked';

  MatchCompositionEntry moveTo(
    MatchCompositionZone nextZone, {
    double? x,
    double? y,
    int? sortOrder,
  }) {
    final isField = nextZone == MatchCompositionZone.field;
    return MatchCompositionEntry(
      participantId: participantId,
      seasonPlayerId: seasonPlayerId,
      guestPlayerId: guestPlayerId,
      displayName: displayName,
      isGuest: isGuest,
      isGoalkeeper: isGoalkeeper,
      zone: nextZone,
      x: isField ? x : null,
      y: isField ? y : null,
      slotLabel: slotLabel,
      photoUrl: photoUrl,
      goals: goals,
      isMotm: isMotm,
      sortOrder: sortOrder ?? this.sortOrder,
      availabilityStatus: availabilityStatus,
      convocationStatus: convocationStatus,
      selectionStatus: switch (nextZone) {
        MatchCompositionZone.field => 'starter',
        MatchCompositionZone.bench => 'substitute',
        MatchCompositionZone.notSelected => 'not_selected',
        MatchCompositionZone.available => 'undecided',
      },
    );
  }

  Map<String, dynamic> toRpcJson() {
    return {
      'participant_id': participantId,
      'zone': zone.wireValue,
      'x': zone == MatchCompositionZone.field ? x : null,
      'y': zone == MatchCompositionZone.field ? y : null,
      'slot_label': slotLabel,
      'sort_order': sortOrder,
    };
  }
}

class MatchComposition {
  const MatchComposition({
    required this.matchId,
    required this.formationCode,
    required this.status,
    required this.version,
    required this.hasUnpublishedChanges,
    required this.squadSizeExceptionApproved,
    required this.entries,
    this.publishedAt,
    this.lastModifiedAt,
  });

  static MatchComposition? tryFromRpc(Object? raw) {
    if (raw == null) return null;
    final json = _map(raw);
    if (json.isEmpty || json['match_id'] == null) return null;
    final entriesRaw = json['entries'];
    return MatchComposition(
      matchId: json['match_id'].toString(),
      formationCode: _nullableText(json['formation_code']),
      status: (json['status'] ?? 'draft').toString(),
      version: (json['version'] as num?)?.toInt() ?? 0,
      hasUnpublishedChanges: json['has_unpublished_changes'] == true,
      squadSizeExceptionApproved: json['squad_size_exception_approved'] == true,
      publishedAt: _dateOrNull(json['published_at']),
      lastModifiedAt: _dateOrNull(json['last_modified_at']),
      entries: entriesRaw is List
          ? entriesRaw
              .map((row) => MatchCompositionEntry.fromJson(_map(row)))
              .toList()
          : const [],
    );
  }

  factory MatchComposition.initial({
    required MatchConvocations convocations,
    required Set<String> goalkeeperSeasonPlayerIds,
  }) {
    return MatchComposition(
      matchId: convocations.matchId,
      formationCode: null,
      status: 'draft',
      version: 0,
      hasUnpublishedChanges: true,
      squadSizeExceptionApproved: false,
      entries: [
        for (var index = 0; index < convocations.players.length; index += 1)
          _initialEntry(
            convocations.players[index],
            index,
            goalkeeperSeasonPlayerIds,
          ),
      ],
    );
  }

  factory MatchComposition.initialFromFinalization({
    required SportMatchFinalization finalization,
  }) {
    return MatchComposition(
      matchId: finalization.matchId,
      formationCode: null,
      status: 'draft',
      version: 0,
      hasUnpublishedChanges: true,
      squadSizeExceptionApproved: false,
      entries: [
        for (var index = 0;
            index < finalization.participants.length;
            index += 1)
          _initialPostMatchEntry(finalization.participants[index], index),
      ],
    );
  }

  final String matchId;
  final String? formationCode;
  final String status;
  final int version;
  final bool hasUnpublishedChanges;
  final bool squadSizeExceptionApproved;
  final DateTime? publishedAt;
  final DateTime? lastModifiedAt;
  final List<MatchCompositionEntry> entries;

  List<MatchCompositionEntry> entriesFor(MatchCompositionZone zone) {
    final result = entries.where((entry) => entry.zone == zone).toList();
    result.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return result;
  }

  int get fieldCount => entriesFor(MatchCompositionZone.field).length;
  int get benchCount => entriesFor(MatchCompositionZone.bench).length;
  int get availableCount => entriesFor(MatchCompositionZone.available).length;
  int get notSelectedCount =>
      entriesFor(MatchCompositionZone.notSelected).length;
  int get selectedCount => fieldCount + benchCount;
  bool get isPublished => version > 0;
  bool get hasGoalkeeperWarning => !entries.any(
        (entry) =>
            entry.zone == MatchCompositionZone.field && entry.isGoalkeeper,
      );

  String get publicationLabel {
    if (!isPublished) return 'Brouillon';
    if (hasUnpublishedChanges) return 'Modifications non publiées';
    return version == 1 ? 'Publié' : 'Publié · version $version';
  }

  MatchComposition copyWith({
    String? formationCode,
    String? status,
    int? version,
    bool? hasUnpublishedChanges,
    bool? squadSizeExceptionApproved,
    DateTime? publishedAt,
    DateTime? lastModifiedAt,
    List<MatchCompositionEntry>? entries,
  }) {
    return MatchComposition(
      matchId: matchId,
      formationCode: formationCode ?? this.formationCode,
      status: status ?? this.status,
      version: version ?? this.version,
      hasUnpublishedChanges:
          hasUnpublishedChanges ?? this.hasUnpublishedChanges,
      squadSizeExceptionApproved:
          squadSizeExceptionApproved ?? this.squadSizeExceptionApproved,
      publishedAt: publishedAt ?? this.publishedAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      entries: entries ?? this.entries,
    );
  }
}

MatchCompositionEntry _initialEntry(
  ConvocationPlayer player,
  int index,
  Set<String> goalkeeperSeasonPlayerIds,
) {
  final selectable = player.canBeSelected;
  return MatchCompositionEntry(
    participantId: player.participantId,
    seasonPlayerId: player.seasonPlayerId,
    guestPlayerId: player.guestPlayerId,
    displayName: player.displayName.trim(),
    isGuest: player.isGuest,
    isGoalkeeper: player.isGoalkeeper ||
        goalkeeperSeasonPlayerIds.contains(player.seasonPlayerId),
    zone: selectable
        ? MatchCompositionZone.available
        : MatchCompositionZone.notSelected,
    sortOrder: index,
    availabilityStatus: player.availabilityStatus,
    convocationStatus: player.convocationStatus.wireValue,
    selectionStatus: selectable ? 'undecided' : 'not_selected',
  );
}

MatchCompositionEntry _initialPostMatchEntry(
  SportFinalParticipant participant,
  int index,
) {
  final selected = participant.present;
  return MatchCompositionEntry(
    participantId: participant.participantId,
    seasonPlayerId: participant.seasonPlayerId ?? '',
    guestPlayerId: participant.guestPlayerId,
    displayName: participant.displayName.trim(),
    isGuest: participant.isGuest,
    isGoalkeeper: participant.isGoalkeeper,
    zone: selected
        ? MatchCompositionZone.bench
        : MatchCompositionZone.notSelected,
    photoUrl: participant.photoUrl,
    goals: participant.goals,
    isMotm: participant.isMotm,
    sortOrder: index,
    availabilityStatus: selected ? 'available' : 'absent',
    convocationStatus: selected ? 'convoked' : 'not_convoked',
    selectionStatus: selected ? 'substitute' : 'not_selected',
  );
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

DateTime? _dateOrNull(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}
