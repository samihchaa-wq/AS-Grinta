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
    this.opponentName,
    this.seasonName,
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
  final String? opponentName;
  final String? seasonName;

  String get locationLabel => isHome ? 'Domicile' : 'Extérieur';

  String get statusLabel {
    switch (status) {
      case 'en_cours':
        return 'En cours';
      case 'termine':
        return 'Terminé';
      case 'archive':
        return 'Archivé';
      default:
        return 'À venir';
    }
  }

  factory MatchModel.fromJson(Map<String, dynamic> json) {
    final date = (json['match_date'] ?? '').toString();
    final time = (json['match_time'] ?? '00:00:00').toString();
    final kickoffAt = DateTime.tryParse('${date}T$time') ?? DateTime(1970);

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
      opponentName: json['opponents'] is Map
          ? json['opponents']['name']?.toString()
          : null,
      seasonName:
          json['seasons'] is Map ? json['seasons']['name']?.toString() : null,
    );
  }
}
