import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/match_goal_action.dart';
import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';

/// Joueur qu'on peut encore rattacher à l'effectif du compte rendu.
class MatchReportAddablePlayer {
  const MatchReportAddablePlayer({
    required this.displayName,
    required this.isGoalkeeper,
    required this.isGuest,
    this.seasonPlayerId,
    this.guestPlayerId,
    this.photoUrl,
  });

  factory MatchReportAddablePlayer.fromJson(Map<String, dynamic> json) {
    return MatchReportAddablePlayer(
      displayName: (json['display_name'] ?? 'Joueur').toString(),
      isGoalkeeper: json['is_goalkeeper'] == true,
      isGuest: json['is_guest'] == true,
      seasonPlayerId: _nullableText(json['season_player_id']),
      guestPlayerId: _nullableText(json['guest_player_id']),
      photoUrl: _nullableText(json['photo_url']),
    );
  }

  final String displayName;
  final bool isGoalkeeper;
  final bool isGuest;
  final String? seasonPlayerId;
  final String? guestPlayerId;
  final String? photoUrl;
}

/// Tout ce dont l'écran « Compte rendu » a besoin, en un seul chargement :
/// l'effectif rejouable, les faits du match et l'état de la fenêtre de
/// correction.
class MatchSportReport {
  const MatchSportReport({
    required this.finalization,
    required this.lineup,
    required this.goalActions,
    required this.isCorrection,
    required this.isEditable,
    required this.liveFinished,
    required this.liveExported,
    required this.addableRoster,
    required this.addableGuests,
    this.correctionClosesAt,
  });

  factory MatchSportReport.fromRpc(Object? raw) {
    final json = _map(raw);
    final finalization = SportMatchFinalization.fromRpc(json);
    final goalsRaw = json['goal_actions'];
    final options = _map(json['add_player_options']);
    final rosterRaw = options['roster'];
    final guestsRaw = options['guests'];
    return MatchSportReport(
      finalization: finalization,
      lineup: MatchComposition.tryFromRpc(json['lineup']) ??
          MatchComposition.initialFromFinalization(finalization: finalization),
      goalActions: goalsRaw is List
          ? [
              for (var index = 0; index < goalsRaw.length; index += 1)
                MatchGoalAction.fromJson(_map(goalsRaw[index]), index),
            ]
          : const [],
      isCorrection: json['is_correction'] == true,
      isEditable: json['is_editable'] != false,
      liveFinished: json['live_finished'] == true,
      liveExported: json['live_exported'] == true,
      correctionClosesAt: _dateOrNull(json['correction_closes_at']),
      addableRoster: rosterRaw is List
          ? rosterRaw
              .map((row) => MatchReportAddablePlayer.fromJson(_map(row)))
              .toList()
          : const [],
      addableGuests: guestsRaw is List
          ? guestsRaw
              .map((row) => MatchReportAddablePlayer.fromJson(_map(row)))
              .toList()
          : const [],
    );
  }

  final SportMatchFinalization finalization;
  final MatchComposition lineup;
  final List<MatchGoalAction> goalActions;

  /// Vrai quand le match était déjà validé : l'écran corrige au lieu de créer.
  final bool isCorrection;

  /// Faux quand le match est archivé ou la fenêtre de correction fermée.
  final bool isEditable;
  final bool liveFinished;
  final bool liveExported;
  final DateTime? correctionClosesAt;
  final List<MatchReportAddablePlayer> addableRoster;
  final List<MatchReportAddablePlayer> addableGuests;

  String get matchId => finalization.matchId;
  String get opponentName => finalization.opponentName;

  MatchSportReport copyWith({
    MatchComposition? lineup,
    List<MatchGoalAction>? goalActions,
    SportMatchFinalization? finalization,
  }) {
    return MatchSportReport(
      finalization: finalization ?? this.finalization,
      lineup: lineup ?? this.lineup,
      goalActions: goalActions ?? this.goalActions,
      isCorrection: isCorrection,
      isEditable: isEditable,
      liveFinished: liveFinished,
      liveExported: liveExported,
      correctionClosesAt: correctionClosesAt,
      addableRoster: addableRoster,
      addableGuests: addableGuests,
    );
  }
}

Map<String, dynamic> _map(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return <String, dynamic>{};
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}

DateTime? _dateOrNull(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty || text == 'null') return null;
  return DateTime.tryParse(text)?.toLocal();
}
