part of 'player_card_page.dart';

Color _resultColor(String result) => switch (result) {
      'V' => AppTheme.success,
      'D' => AppTheme.error,
      _ => AppTheme.textFaint,
    };

/// Couleur du score dans la liste des derniers matchs : orange pour un nul,
/// comme une victoire en vert et une défaite en rouge.
Color _scoreColor(String result) =>
    result == 'N' ? AppTheme.warning : _resultColor(result);

class _ResultSquare extends StatelessWidget {
  const _ResultSquare({required this.result});

  final String result;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _resultColor(result),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        result,
        style: const TextStyle(
          fontFamily: _display,
          fontSize: 13,
          color: AppTheme.background,
        ),
      ),
    );
  }
}

const _months = [
  'JAN', 'FÉV', 'MAR', 'AVR', 'MAI', 'JUIN', //
  'JUIL', 'AOÛT', 'SEP', 'OCT', 'NOV', 'DÉC',
];

class _MatchList extends StatelessWidget {
  const _MatchList({required this.matches});

  final List<PlayerMatchLine> matches;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardDecoration,
      child: Column(
        children: [
          for (var i = 0; i < matches.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: AppTheme.outline.withValues(alpha: .35),
              ),
            _MatchRow(match: matches[i]),
          ],
        ],
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match});

  final PlayerMatchLine match;

  ({String label, Color color})? get _type => switch (match.matchType) {
        'championnat' => (
            label: 'CHAMP.',
            color: CalendarCardPalette.championshipBorder,
          ),
        'amical' => (
            label: 'AMICAL',
            color: CalendarCardPalette.friendlyBorder,
          ),
        'entre_nous' => (
            label: 'ENTRE NOUS',
            color: CalendarCardPalette.internalBorder,
          ),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final type = _type;
    final resultColor = _scoreColor(match.result);
    // Ouvre le récapitulatif du match, comme une carte du calendrier ; la
    // flèche retour ramène ici.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => context.push('/matches/${match.matchId}'),
        child: _content(type, resultColor),
      ),
    );
  }

  Widget _content(({String label, Color color})? type, Color resultColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Text(
                  match.date.day.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    fontFamily: _display,
                    fontSize: 16,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  _months[match.date.month - 1],
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textFaint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.opponentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (type != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: type.color.withValues(alpha: .2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          type.label,
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: .4,
                            color: Color.lerp(type.color, Colors.white, .35),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      match.isHome ? 'Domicile' : 'Extérieur',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textFaint,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Mêmes icônes que la composition d'un match terminé.
          if (match.goals > 0)
            _Contribution(icon: const GoalIcon(size: 13), count: match.goals),
          if (match.assists > 0)
            _Contribution(
              icon: const AssistBootIcon(size: 13),
              count: match.assists,
            ),
          if (match.isManOfTheMatch)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Tooltip(
                message: 'Homme du match',
                child: ManOfTheMatchIcon(size: 15),
              ),
            ),
          const SizedBox(width: 8),
          Container(
            constraints: const BoxConstraints(minWidth: 50),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: resultColor.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              match.scoreLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _display,
                fontSize: 16,
                color: resultColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Contribution extends StatelessWidget {
  const _Contribution({required this.icon, required this.count});

  final Widget icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 2),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
