import 'package:as_grinta/features/sports_management/data/match_kit_photo_overrides.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter_test/flutter_test.dart';

MatchCompositionEntry entry({
  String seasonPlayerId = 'player-1',
  bool isGuest = false,
  String? photoUrl = 'france.png',
}) =>
    MatchCompositionEntry(
      participantId: 'participant-1',
      seasonPlayerId: seasonPlayerId,
      displayName: 'Alex',
      isGuest: isGuest,
      isGoalkeeper: false,
      zone: MatchCompositionZone.field,
      sortOrder: 0,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'starter',
      photoUrl: photoUrl,
    );

void main() {
  test('the three match jersey IDs map to the correct photo slots', () {
    expect(kitPhotoColumn('france'), isNull);
    expect(kitPhotoColumn('blue'), 'brazil_url');
    expect(kitPhotoColumn('orange'), 'netherlands_url');
    expect(kitPhotoColumn(null), isNull);
    expect(kitPhotoColumn('unknown'), isNull);
  });

  test('the selected shirt replaces only the displayed player photo', () {
    final original = entry();
    final result = withMatchKitPhotos(
      [original],
      {'player-1': 'kits/player-1/brazil.png'},
    );
    expect(result.single.photoUrl, 'kits/player-1/brazil.png');
    expect(original.photoUrl, 'france.png');
    expect(result.single.seasonPlayerId, original.seasonPlayerId);
    expect(result.single.zone, MatchCompositionZone.field);
  });

  test('a missing alternate shirt falls back to the existing France photo', () {
    final original = entry();
    final result = withMatchKitPhotos([original], const {});
    expect(result.single.photoUrl, 'france.png');
  });

  test('coach France keeps the existing photo when no variant is selected', () {
    expect(
      coachPhotoForMatchKit(
        seasonPlayerId: 'coach-1',
        francePhotoUrl: 'coach-france.png',
        photoOverrides: const {},
      ),
      'coach-france.png',
    );
  });

  test('coach follows the Brazil and Netherlands variants by season player ID',
      () {
    const variants = {
      'coach-1': 'kits/coach-1/brazil.png',
      'coach-2': 'kits/coach-2/netherlands.png',
    };
    expect(
      coachPhotoForMatchKit(
        seasonPlayerId: 'coach-1',
        francePhotoUrl: 'coach-france.png',
        photoOverrides: variants,
      ),
      'kits/coach-1/brazil.png',
    );
    expect(
      coachPhotoForMatchKit(
        seasonPlayerId: 'coach-2',
        francePhotoUrl: 'coach-france-2.png',
        photoOverrides: variants,
      ),
      'kits/coach-2/netherlands.png',
    );
  });

  test('missing coach variant and absent season ID fall back to France', () {
    expect(
      coachPhotoForMatchKit(
        seasonPlayerId: 'coach-1',
        francePhotoUrl: 'coach-france.png',
        photoOverrides: const {'another-coach': 'other.png'},
      ),
      'coach-france.png',
    );
    expect(
      coachPhotoForMatchKit(
        seasonPlayerId: null,
        francePhotoUrl: 'coach-france.png',
        photoOverrides: const {'': 'wrong.png'},
      ),
      'coach-france.png',
    );
    expect(
      coachPhotoForMatchKit(
        seasonPlayerId: 'coach-1',
        francePhotoUrl: null,
        photoOverrides: const {'coach-1': '  '},
      ),
      isNull,
    );
  });

  test('a guest is not overridden by a season player photo', () {
    final original = entry(isGuest: true);
    final result = withMatchKitPhotos(
      [original],
      {'player-1': 'kits/player-1/netherlands.png'},
    );
    expect(result.single.photoUrl, 'france.png');
  });
}
