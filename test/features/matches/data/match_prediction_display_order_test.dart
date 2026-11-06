import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/presentation/match_details_page.dart';
import 'package:flutter_test/flutter_test.dart';

MatchPredictionResult _prediction({
  required String profileId,
  required String name,
  required double points,
}) {
  return MatchPredictionResult(
    profileId: profileId,
    name: name,
    scoreGrinta: 1,
    scoreOpponent: 0,
    points: points,
    usedX2: false,
  );
}

void main() {
  test('equal points put the viewer first then sort names alphabetically', () {
    final predictions = [
      _prediction(profileId: 'roman', name: 'Roman', points: 128),
      _prediction(profileId: 'allan', name: 'Allan', points: 128),
      _prediction(profileId: 'samih', name: 'Samih', points: 128),
      _prediction(profileId: 'alban', name: 'Alban', points: 128),
    ]..sort(
        (a, b) => compareMatchPredictionResultsForDisplay(
          a,
          b,
          currentProfileId: 'samih',
        ),
      );

    expect(
      predictions.map((prediction) => prediction.name).toList(),
      ['Samih', 'Alban', 'Allan', 'Roman'],
    );
  });

  test('viewer priority only applies inside an equal-points group', () {
    final predictions = [
      _prediction(profileId: 'samih', name: 'Samih', points: 128),
      _prediction(profileId: 'alyoun', name: 'Alyoun', points: 256),
      _prediction(profileId: 'allan', name: 'Allan', points: 128),
    ]..sort(
        (a, b) => compareMatchPredictionResultsForDisplay(
          a,
          b,
          currentProfileId: 'samih',
        ),
      );

    expect(
      predictions.map((prediction) => prediction.name).toList(),
      ['Alyoun', 'Samih', 'Allan'],
    );
  });

  test('without a viewer equal points are alphabetical', () {
    final predictions = [
      _prediction(profileId: 'simon', name: 'Simon', points: 128),
      _prediction(profileId: 'amine', name: 'Amine', points: 128),
      _prediction(profileId: 'lulu', name: 'Lulu', points: 128),
    ]..sort(
        (a, b) => compareMatchPredictionResultsForDisplay(
          a,
          b,
          currentProfileId: null,
        ),
      );

    expect(
      predictions.map((prediction) => prediction.name).toList(),
      ['Amine', 'Lulu', 'Simon'],
    );
  });
}
