class ClubEvent {
  const ClubEvent({
    required this.id,
    required this.seasonId,
    required this.title,
    required this.startsAt,
    required this.location,
    required this.createdBy,
  });

  final String id;
  final String seasonId;
  final String title;
  final DateTime startsAt;
  final String location;
  final String createdBy;

  factory ClubEvent.fromJson(Map<String, dynamic> json) {
    return ClubEvent(
      id: json['id'].toString(),
      seasonId: json['season_id'].toString(),
      title: json['title']?.toString().trim() ?? '',
      startsAt: DateTime.parse(json['starts_at'].toString()).toLocal(),
      location: json['location']?.toString().trim() ?? '',
      createdBy: json['created_by']?.toString() ?? '',
    );
  }
}
