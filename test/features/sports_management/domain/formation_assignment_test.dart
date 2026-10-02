import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/formation_assignment.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/match_squad_editing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MatchCompositionEntry onSlot(
    FootballFormationSlot slot, {
    String? id,
    bool goalkeeper = false,
    int sortOrder = 0,
  }) {
    return MatchCompositionEntry(
      participantId: id ?? slot.label,
      seasonPlayerId: 'season-${id ?? slot.label}',
      displayName: id ?? slot.label,
      isGoalkeeper: goalkeeper,
      zone: MatchCompositionZone.field,
      x: slot.position.dx,
      y: slot.position.dy,
      sortOrder: sortOrder,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'starter',
    );
  }

  /// Une équipe complète posée sur [code], chaque joueur portant le nom de
  /// son poste. L'ordre de la liste est volontairement inversé : la
  /// répartition ne doit pas en dépendre.
  List<MatchCompositionEntry> teamOn(String code) {
    final slots = formationForCode(code).slots;
    return [
      for (var index = slots.length - 1; index >= 0; index -= 1)
        onSlot(
          slots[index],
          goalkeeper: slots[index].label == 'GB',
          sortOrder: slots.length - index,
        ),
    ];
  }

  Map<String, String> labelsAfter(String from, String to) {
    final assigned = assignFieldPlayersToSlots(
      teamOn(from),
      formationForCode(to).slots,
    );
    return {
      for (final entry in assigned.entries) entry.key: entry.value.label,
    };
  }

  test('un dispositif identique ne bouge personne', () {
    for (final formation in footballFormations) {
      final moved = labelsAfter(formation.code, formation.code);
      for (final entry in moved.entries) {
        expect(entry.value, entry.key, reason: formation.code);
      }
    }
  });

  test('4-4-2 → 4-3-3 : la défense reste, les attaquants restent devant', () {
    final moved = labelsAfter('4-4-2 à plat', '4-3-3 défensif');
    expect(moved['GB'], 'GB');
    for (final defender in ['DG', 'DCG', 'DCD', 'DD']) {
      expect(moved[defender], defender);
    }
    expect(moved['BUG'], isIn(['AG', 'BU', 'AD']));
    expect(moved['BUD'], isIn(['AG', 'BU', 'AD']));
    expect(moved['MCG'], isIn(['MDC', 'MCG', 'MCD']));
    expect(moved['MCD'], isIn(['MDC', 'MCG', 'MCD']));
  });

  test('4-2-3-1 → 3-5-2 : un seul latéral devient piston, pas attaquant', () {
    final moved = labelsAfter('4-2-3-1', '3-5-2');
    expect(moved['GB'], 'GB');
    expect(moved['BU'], isIn(['BUG', 'BUD']));
    for (final label in ['DG', 'DCG', 'DCD', 'DD']) {
      expect(moved[label], isIn(['DCG', 'DC', 'DCD', 'MG', 'MD']));
    }
  });

  test('tous les changements gardent chaque ligne cohérente', () {
    // D'un dispositif à l'autre, personne ne traverse le terrain : aucun
    // défenseur central ne finit attaquant et aucun attaquant ne finit
    // défenseur central. Seuls les couloirs bougent beaucoup : un ailier
    // redescend piston quand on passe à cinq derrière, un piston monte
    // ailier quand on repasse à trois — le choix qu'on ferait au bord du
    // terrain.
    bool isCentralDefender(String label) =>
        label == 'DCG' || label == 'DC' || label == 'DCD';
    bool isForward(String label) =>
        label.startsWith('BU') || label == 'AG' || label == 'AD';
    for (final from in footballFormations) {
      for (final to in footballFormations) {
        final moved = labelsAfter(from.code, to.code);
        expect(moved, hasLength(11), reason: '${from.code} → ${to.code}');
        expect(moved['GB'], 'GB', reason: '${from.code} → ${to.code}');
        for (final entry in moved.entries) {
          final reason = '${from.code} → ${to.code} : ${entry.key}';
          if (isCentralDefender(entry.key)) {
            expect(isForward(entry.value), isFalse, reason: reason);
          }
          if (isForward(entry.key)) {
            expect(isCentralDefender(entry.value), isFalse, reason: reason);
          }
        }
      }
    }
  });

  test('le gardien retourne au but même s’il était placé sur le terrain', () {
    final slots = formationForCode('4-4-2 à plat').slots;
    final keeper = onSlot(slots[5], id: 'gardien', goalkeeper: true);
    final field = onSlot(slots[0], id: 'joueur');
    final assigned = assignFieldPlayersToSlots([field, keeper], slots);
    expect(assigned['gardien']!.label, 'GB');
    expect(assigned['joueur']!.label, isNot('GB'));
  });

  test('sans gardien, personne n’est envoyé au but depuis le terrain', () {
    final slots = formationForCode('4-4-2 à plat').slots;
    final field = [for (final slot in slots.skip(1)) onSlot(slot)];
    final assigned = assignFieldPlayersToSlots(field, slots);
    expect(assigned.values.map((slot) => slot.label), isNot(contains('GB')));
  });

  test('un joueur en trop reste sans poste, jamais le gardien', () {
    final slots = formationForCode('4-4-2 à plat').slots;
    final field = [
      for (final slot in slots) onSlot(slot, goalkeeper: slot.label == 'GB'),
      onSlot(slots[3], id: 'en-trop'),
    ];
    final assigned = assignFieldPlayersToSlots(field, slots);
    expect(assigned, hasLength(11));
    expect(assigned['GB']!.label, 'GB');
    expect(assigned.values.toSet(), hasLength(11));
  });

  test('repositionForFormation applique la même répartition', () {
    final lineup = MatchComposition(
      matchId: 'match-1',
      formationCode: '4-4-2 à plat',
      status: 'draft',
      version: 0,
      hasUnpublishedChanges: true,
      squadSizeExceptionApproved: false,
      entries: teamOn('4-4-2 à plat'),
    );
    final next = repositionForFormation(lineup, '4-2-3-1');
    final slots = {
      for (final slot in formationForCode('4-2-3-1').slots)
        slot.label: slot.position,
    };
    final keeper = next.entries.firstWhere((e) => e.participantId == 'GB');
    expect(keeper.x, slots['GB']!.dx);
    expect(keeper.y, slots['GB']!.dy);
    final leftBack = next.entries.firstWhere((e) => e.participantId == 'DG');
    expect(leftBack.x, slots['DG']!.dx);
    expect(leftBack.y, slots['DG']!.dy);
  });
}
