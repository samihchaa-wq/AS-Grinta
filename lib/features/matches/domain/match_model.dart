import 'package:as_grinta/core/utils/match_window.dart';

class MatchModel {
  const MatchModel({
    required this.id,
    required this.seasonId,
    required this.opponentId,
    required this.kickoffAt,
    required this.isHome,
    required this.plannedDurationMinutes,
    required this.status,
    required this.grintaScore,
    required this.opponentScore,
    this.predictionsClosedAt,
    this.liveState,
    this.liveFinishedAt,
    this.liveExported = false,
    this.oddsWin,
    this.oddsDraw,
    this.oddsLoss,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.opponentName,
    this.seasonName,
    this.address,
    this.matchType = 'championnat',
    this.jerseyNote,
  });

  final String id;
  final String seasonId;
  final String opponentId;
  final DateTime kickoffAt;
  final bool isHome;
  final int plannedDurationMinutes;
  final String status;
  final int? grintaScore;
  final int? opponentScore;
  final DateTime? predictionsClosedAt;

  /// État du Tableau Blanc, s'il a été ouvert pour ce match.
  final String? liveState;
  final DateTime? liveFinishedAt;
  final bool liveExported;

  final double? oddsWin;
  final double? oddsDraw;
  final double? oddsLoss;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? opponentName;
  final String? seasonName;

  /// Adresse du lieu de la rencontre (facultative).
  final String? address;

  /// « amical » ou « championnat », à titre informatif (onglet Info).
  final String matchType;

  /// Commentaire libre sur le maillot à porter, à titre informatif.
  final String? jerseyNote;

  String get locationLabel => isHome ? 'Domicile' : 'Extérieur';
  bool get isArchived => status == 'archive';
  bool get isFinished => status == 'termine' || status == 'archive';
  bool get isCancelled => status == 'annule';
  bool get isFriendly => matchType == 'amical';
  bool get isInternal => matchType == 'entre_nous';
  bool get isLiveSessionFinished => liveState == 'finished';

  String get matchTypeLabel {
    if (isInternal) return 'Match entre nous';
    return isFriendly ? 'Match amical' : 'Championnat';
  }

  /// Pronostics fermés manuellement par l'admin (avant l'heure limite).
  bool get pronosClosed => predictionsClosedAt != null;

  MatchDisplayPhase phase({DateTime? now}) => matchDisplayPhase(
        kickoffAt: kickoffAt,
        status: status,
        plannedDurationMinutes: plannedDurationMinutes,
        liveState: liveState,
        now: now,
      );

  /// Le match est fini sportivement mais son compte rendu n'est pas encore
  /// validé. On ne le mélange plus avec les matchs passés.
  bool get isAwaitingResult => phase() == MatchDisplayPhase.awaitingValidation;

  String get statusLabel {
    switch (phase()) {
      case MatchDisplayPhase.upcoming:
        return 'À venir';
      case MatchDisplayPhase.next:
        return 'Prochain';
      case MatchDisplayPhase.live:
        return 'En direct';
      case MatchDisplayPhase.awaitingValidation:
        return 'À valider';
      case MatchDisplayPhase.past:
        return isArchived ? 'Archivé' : 'Terminé';
      case MatchDisplayPhase.cancelled:
        return 'Annulé';
    }
  }

  factory MatchModel.fromJson(Map<String, dynamic> json) {
    final serverKickoff = DateTime.tryParse(
      '${json['kickoff_at'] ?? ''}',
    )?.toLocal();
    final date = (json['match_date'] ?? '').toString();
    final time = (json['match_time'] ?? '00:00:00').toString();
    final kickoffAt =
        serverKickoff ?? DateTime.tryParse('${date}T$time') ?? DateTime(1970);
    final oddsRaw = json['match_odds'];
    final odds = oddsRaw is List && oddsRaw.isNotEmpty
        ? Map<String, dynamic>.from(oddsRaw.first as Map)
        : oddsRaw is Map
            ? Map<String, dynamic>.from(oddsRaw)
            : const <String, dynamic>{};
    final liveRaw = json['match_live_sessions'];
    final live = liveRaw is List && liveRaw.isNotEmpty
        ? Map<String, dynamic>.from(liveRaw.first as Map)
        : liveRaw is Map
            ? Map<String, dynamic>.from(liveRaw)
            : const <String, dynamic>{};

    return MatchModel(
      id: json['id']?.toString() ?? '',
      seasonId: json['season_id']?.toString() ?? '',
      opponentId: json['opponent_id']?.toString() ?? '',
      kickoffAt: kickoffAt,
      isHome: json['location'] == 'domicile',
      plannedDurationMinutes:
          int.tryParse('${json['planned_duration_minutes']}') ?? 90,
      status: (json['status'] ?? 'a_venir').toString(),
      grintaScore: json['score_as_grinta'] == null
          ? null
          : int.tryParse('${json['score_as_grinta']}'),
      opponentScore: json['score_adverse'] == null
          ? null
          : int.tryParse('${json['score_adverse']}'),
      predictionsClosedAt: DateTime.tryParse(
        '${json['predictions_closed_at'] ?? ''}',
      )?.toLocal(),
      liveState: live['state']?.toString(),
      liveFinishedAt:
          DateTime.tryParse('${live['finished_at'] ?? ''}')?.toLocal(),
      liveExported: live['exported'] == true,
      oddsWin: (odds['odds_victoire_as_grinta'] as num?)?.toDouble(),
      oddsDraw: (odds['odds_nul'] as num?)?.toDouble(),
      oddsLoss: (odds['odds_victoire_adverse'] as num?)?.toDouble(),
      createdBy: json['created_by']?.toString(),
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
      updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}')?.toLocal(),
      opponentName: json['opponents'] is Map
          ? json['opponents']['name']?.toString()
          : null,
      seasonName:
          json['seasons'] is Map ? json['seasons']['name']?.toString() : null,
      address: (json['address']?.toString().trim().isNotEmpty ?? false)
          ? json['address'].toString()
          : null,
      matchType: (json['match_type'] ?? 'championnat').toString(),
      jerseyNote: (json['jersey_note']?.toString().trim().isNotEmpty ?? false)
          ? json['jersey_note'].toString()
          : null,
    );
  }
}
