import 'package:as_grinta/features/matches/data/calendar_history_repository.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/widgets/admin_match_options_button.dart';
import 'package:as_grinta/features/matches/presentation/widgets/historical_match_card.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/match_history_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

MatchModel _finished({required DateTime kickoffAt}) => MatchModel(
      id: 'match-id',
      seasonId: 'season-id',
      opponentId: 'opponent-id',
      kickoffAt: kickoffAt,
      isHome: true,
      plannedDurationMinutes: 90,
      status: 'termine',
      grintaScore: 6,
      opponentScore: 0,
      opponentName: 'FC Booster',
      matchType: 'amical',
    );

void main() {
  testWidgets(
      'le score d’un match de la saison est au même endroit que celui d’un '
      'match de l’historique', (tester) async {
    final validatedLongAgo = _finished(
      kickoffAt: DateTime.now().subtract(const Duration(days: 2)),
    );
    // Côté admin, le calendrier ne réserve la place du crayon que s'il reste
    // une action possible. Deux jours après le match, il n'en reste aucune.
    expect(AdminMatchOptionsButton.hasOptions(validatedLongAgo), isFalse);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: Column(
                children: [
                  MatchHistoryCard(match: validatedLongAgo),
                  HistoricalMatchCard(
                    match: HistoricalMatchResult(
                      id: 'history-1',
                      date: DateTime(2026, 6, 15, 20, 45),
                      hasTime: true,
                      opponentName: 'AS Clinique Pasteur',
                      grintaScore: 3,
                      opponentScore: 4,
                      isHome: true,
                      matchType: 'championnat',
                      championshipRound: 26,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final seasonScore = tester.getRect(find.text('6'));
    final historyScore = tester.getRect(find.text('3'));
    expect(seasonScore.right, closeTo(historyScore.right, 0.5));
    expect(seasonScore.height, closeTo(historyScore.height, 0.5));
  });

  test('un match à venir ou tout juste joué garde ses options admin', () {
    expect(
      AdminMatchOptionsButton.hasOptions(
        _finished(kickoffAt: DateTime.now().add(const Duration(days: 5))),
      ),
      isTrue,
    );
    expect(
      AdminMatchOptionsButton.hasOptions(
        _finished(
          kickoffAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ),
      isTrue,
    );
  });
}
