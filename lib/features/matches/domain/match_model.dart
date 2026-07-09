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
    return MatchModel(
      id: json['id']?.toString() ?? '',
      seasonId: json['season_id']?.toString() ?? '',
      opponentId: json['opponent_id']?.toString() ?? '',
      kickoffAt: DateTime.parse(json['kickoff_at'] as String),
      isHome: json['is_home'] == true,
      plannedDurationMinutes: int.tryParse('${json['planned_duration_minutes']}') ?? 90,
      status: (json['status'] ?? 'a_venir').toString(),
      grintaScore: json['grinta_score'] == null ? null : int.tryParse('${json['grinta_score']}'),
      opponentScore: json['opponent_score'] == null ? null : int.tryParse('${json['opponent_score']}'),
      opponentName: json['opponents'] is Map ? json['opponents']['name']?.toString() : null,
      seasonName: json['seasons'] is Map ? json['seasons']['name']?.toString() : null,
    );
  }
}
