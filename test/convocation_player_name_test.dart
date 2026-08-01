import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:flutter_test/flutter_test.dart';

ConvocationPlayer _player({
  String firstName = 'Stéphane',
  String? serverName,
  bool isGuest = false,
}) {
  return ConvocationPlayer(
    participantId: 'p1',
    seasonPlayerId: 's1',
    firstName: firstName,
    lastName: 'Fernandez',
    availabilityStatus: 'available',
    convocationStatus: ConvocationStatus.convoked,
    publishedConvocationStatus: ConvocationStatus.convoked,
    manualOverride: false,
    waitlistPosition: null,
    recommendedNotConvoked: false,
    turnShouldConsume: false,
    turnState: WaitlistTurnState.notApplicable,
    promotedAfterWithdrawalAt: null,
    isGuest: isGuest,
    serverName: serverName,
  );
}

void main() {
  group('Nom d’un joueur sur une puce d’effectif', () {
    test('le nom résolu par le serveur passe devant celui de la fiche', () {
      // Le cas réel : la fiche dit « Stéphane », son compte dit « Steph ».
      final player = _player(serverName: 'Steph');
      expect(player.shortName, 'Steph');
    });

    test('sans nom du serveur, on garde le prénom de la fiche', () {
      expect(_player().shortName, 'Stéphane');
    });

    test('le suffixe « (Invité) » est retiré de la puce', () {
      // La puce a une icône d'invité et la grille est trop étroite pour le
      // suffixe ; il reste présent sur displayName, utilisé ailleurs.
      final guest = _player(serverName: 'Kevin (Invité)', isGuest: true);
      expect(guest.shortName, 'Kevin');
      expect(guest.displayName, 'Kevin (Invité)');
    });
  });
}
