import 'package:as_grinta/features/coach/data/coach_live_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final coachMatchStatusProvider =
    StreamProvider.autoDispose.family<String, String>((ref, matchId) {
  return ref.watch(coachLiveRepositoryProvider).watchMatchStatus(matchId);
});
