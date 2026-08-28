import 'package:as_grinta/features/matches/domain/match_model.dart';

const matchDeletionWindow = Duration(hours: 24);

DateTime matchDeletionDeadline(MatchModel match) {
  return match.kickoffAt.add(matchDeletionWindow);
}

bool canDeleteMatch(MatchModel match, {DateTime? now}) {
  final deadline = matchDeletionDeadline(match);
  return (now ?? DateTime.now()).toUtc().isBefore(deadline.toUtc());
}
