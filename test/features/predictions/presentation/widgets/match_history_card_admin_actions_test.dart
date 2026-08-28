import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/match_history_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('un match terminé conserve les actions admin', (tester) async {
    final match = MatchModel(
      id: 'match-id',
      seasonId: 'season-id',
      opponentId: 'opponent-id',
      kickoffAt: DateTime.now().subtract(const Duration(hours: 1)),
      isHome: true,
      plannedDurationMinutes: 90,
      status: 'termine',
      grintaScore: 5,
      opponentScore: 0,
      opponentName: 'FC Booster',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MatchHistoryCard(
              match: match,
              adminActions: const Icon(Icons.edit_outlined, key: Key('admin-actions')),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('admin-actions')), findsOneWidget);
  });
}
