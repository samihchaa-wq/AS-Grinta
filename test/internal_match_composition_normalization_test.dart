import 'package:as_grinta/features/sports_management/domain/internal_match_composition.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fieldEntry(
  String id,
  String slot,
  double x,
  double y,
) =>
    {
      'participant_id': id,
      'display_name': id,
      'is_guest': false,
      'is_goalkeeper': slot == 'GB',
      'team_no': 1,
      'zone': 'field',
      'x': x,
      'y': y,
      'slot_label': slot,
      'sort_order': 0,
    };

void main() {
  test('recalage du 3-3-2 historique sur les deux BU courants', () {
    final composition = InternalMatchComposition.tryFromRpc({
      'match_id': 'm',
      'team1_name': 'Équipe 1',
      'team2_name': 'Équipe 2',
      'team1_formation': '3-3-2',
      'team2_formation': null,
      'entries': [
        _fieldEntry('gb', 'GB', .5, .86),
        _fieldEntry('dcg', 'DCG', .14, .68),
        _fieldEntry('dc', 'DC', .5, .68),
        _fieldEntry('dcd', 'DCD', .86, .68),
        _fieldEntry('mcg', 'MCG', .14, .41),
        _fieldEntry('mc', 'MC', .5, .41),
        _fieldEntry('mcd', 'MCD', .86, .41),
        _fieldEntry('simon', 'BUG', .14, .14),
        _fieldEntry('allan', 'BUD', .86, .14),
      ],
    });

    expect(composition, isNotNull);
    final bySlot = {
      for (final entry in composition!.team1) entry.slotLabel: entry,
    };

    expect(bySlot['BUG']!.x, closeTo(.38, .001));
    expect(bySlot['BUG']!.y, closeTo(.20, .001));
    expect(bySlot['BUD']!.x, closeTo(.62, .001));
    expect(bySlot['BUD']!.y, closeTo(.20, .001));
    expect(bySlot['DCG']!.x, closeTo(.24, .001));
    expect(bySlot['DCD']!.x, closeTo(.76, .001));
  });

  test('un poste inconnu reste visible en revenant à placer', () {
    final entries = <InternalCompositionEntry>[
      for (var i = 0; i < 8; i += 1)
        InternalCompositionEntry(
          participantId: 'p$i',
          displayName: 'P$i',
          isGuest: false,
          isGoalkeeper: i == 0,
          teamNo: 1,
          zone: 'field',
          x: .5,
          y: .5,
          slotLabel: i == 7 ? 'ANCIEN_POSTE' : const [
            'GB',
            'DCG',
            'DC',
            'DCD',
            'MCG',
            'MC',
            'MCD',
          ][i],
        ),
    ];

    final normalized = normalizeInternalVisualEntries(
      entries: entries,
      team1FormationCode: '3-3-1',
      team2FormationCode: null,
    );
    final invalid = normalized.singleWhere(
      (entry) => entry.participantId == 'p7',
    );

    expect(invalid.zone, 'available');
    expect(invalid.slotLabel, isNull);
    expect(invalid.x, isNull);
    expect(invalid.y, isNull);
  });
}
