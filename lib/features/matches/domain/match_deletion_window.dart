import 'package:as_grinta/features/matches/domain/match_model.dart';

const matchDeletionWindow = Duration(hours: 24);

DateTime? matchDeletionDeadline(MatchModel match) {
  final createdAt = match.createdAt;
  if (createdAt == null) return null;
  return createdAt.add(matchDeletionWindow);
}

bool canDeleteMatch(MatchModel match, {DateTime? now}) {
  final deadline = matchDeletionDeadline(match);
  if (deadline == null) return false;
  return (now ?? DateTime.now()).toUtc().isBefore(deadline.toUtc());
}
