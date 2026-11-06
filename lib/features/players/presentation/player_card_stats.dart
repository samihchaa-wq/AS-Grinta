part of 'player_card_page.dart';

class _StatGrid extends StatelessWidget {
  const _StatGrid({
    required this.playerKey,
    required this.player,
    required this.data,
    required this.teamMatches,
  });

  final PlayerCardKey playerKey;
  final PlayerStatistics player;
  final StatisticsPeriodData data;
  final int? teamMatches;

  @override
  Widget build(BuildContext context) {
    final players = data.players;
    final tracksAssists = statisticsShowsAssistsColumn(data);

    final minMatches = averageRankingMinMatches(
      data.period,
      teamMatches: teamMatches,
      players: players,
    );
    bool eligible(PlayerStatistics p) => (p.matchesPlayed ?? 0) >= minMatches;

    // Une valeur nulle ne classe personne : sans cela, une saison où personne
    // n'a encore fait de passe décisive sacrerait tout l'effectif « 1er ».
    int? rankOf(
      PlayerStat stat, {
      bool Function(PlayerStatistics)? among,
    }) {
      final mine = stat.valueOf(player);
      if (mine <= 0) return null;
      return 1 +
          players
              .where(
                (p) => (among == null || among(p)) && stat.valueOf(p) > mine,
              )
              .length;
    }

    // Toucher une case ouvre le classement complet de la statistique.
    VoidCallback openRanking(PlayerStat stat) => () => context.push(
          playerStatRankingLocation(
            key: playerKey,
            stat: stat,
            period: data.period,
          ),
        );

    _StatTile tile(PlayerStat stat) => _StatTile(
          value: stat.display(player),
          label: stat.label,
          rank: rankOf(stat),
          onTap: openRanking(stat),
        );

    // Moyennes : seuls les joueurs assez présents sont classés, entre eux.
    _StatTile averageTile(PlayerStat stat) => _StatTile(
          value: stat.display(player),
          label: stat.label,
          rank: eligible(player) ? rankOf(stat, among: eligible) : null,
          rankNote: eligible(player) ? null : 'N/A',
          onTap: openRanking(stat),
        );

    final tiles = <_StatTile>[
      tile(PlayerStat.matches),
      averageTile(PlayerStat.winRate),
      tile(PlayerStat.goals),
      // Les passes ne sont suivies que depuis leur mise en service : sur une
      // période antérieure, un zéro ferait croire à un manque de saisie, et
      // il n'y a pas de classement à ouvrir.
      if (tracksAssists)
        tile(PlayerStat.assists)
      else
        _StatTile(value: '–', label: PlayerStat.assists.label, rank: null),
      tile(PlayerStat.manOfTheMatch),
      averageTile(PlayerStat.goalsPerMatch),
    ];

    const gap = 8.0;
    Widget row(List<_StatTile> items) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Expanded(child: items[i]),
              ],
            ],
          ),
        );

    return Column(
      children: [
        row(tiles.sublist(0, 3)),
        const SizedBox(height: gap),
        row(tiles.sublist(3)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.rank,
    this.rankNote,
    this.onTap,
  });

  final String value;
  final String label;

  /// Ouvre le classement complet ; `null` quand il n'y en a pas.
  final VoidCallback? onTap;

  /// Remplace la ligne de rang quand le joueur n'est pas classé (« N/A » :
  /// pas assez de matchs joués).
  final String? rankNote;

  /// Rang au club sur cette statistique ; `null` quand il n'a pas de sens
  /// (valeur nulle, statistique non suivie sur la période).
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final rank = this.rank;
    final column = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontFamily: _display,
              fontSize: 28,
              height: 1.1,
              color: _medalColor(rank),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: .5,
            color: AppTheme.textFaint,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          rankNote ?? (rank == null ? '–' : '${_ordinal(rank)} du club'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: rank != null && rank <= 3
                ? _medalColor(rank)
                : AppTheme.primaryBright,
          ),
        ),
      ],
    );
    Widget box({Decoration? decoration}) => Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          decoration: decoration,
          child: column,
        );

    final onTap = this.onTap;
    if (onTap == null) return box(decoration: _cardDecoration);
    // Le fond de la case est porté par le Material : l'effet du toucher se
    // dessine dessus, au lieu de disparaître sous un fond opaque.
    return Semantics(
      button: true,
      hint: 'Voir le classement',
      child: Material(
        color: _cardDecoration.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          side: _cardDecoration.border!.top,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: box()),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.player, required this.recent});

  final PlayerStatistics player;
  final List<PlayerMatchLine> recent;

  @override
  Widget build(BuildContext context) {
    final wins = player.wins ?? 0;
    final draws = player.draws ?? 0;
    final losses = player.losses ?? 0;
    // La forme se lit de gauche à droite, le match le plus récent au bout.
    final form = recent.take(5).toList().reversed.toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: _SectionTitle('Bilan')),
              for (final match in form) ...[
                const SizedBox(width: 6),
                _ResultSquare(result: match.result),
              ],
            ],
          ),
          if (wins + draws + losses > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 8,
                // Sans enfant, une ColoredBox prend la hauteur minimale
                // permise : il faut l'étirer pour que la barre se voie.
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wins > 0)
                      Expanded(
                        flex: wins,
                        child: const ColoredBox(color: AppTheme.success),
                      ),
                    if (wins > 0 && draws + losses > 0)
                      const SizedBox(width: 2),
                    if (draws > 0)
                      Expanded(
                        flex: draws,
                        child: const ColoredBox(color: AppTheme.textFaint),
                      ),
                    if (draws > 0 && losses > 0) const SizedBox(width: 2),
                    if (losses > 0)
                      Expanded(
                        flex: losses,
                        child: const ColoredBox(color: AppTheme.error),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Legend(value: wins, label: 'Victoires', color: AppTheme.success),
              _Legend(value: draws, label: 'Nuls'),
              _Legend(value: losses, label: 'Défaites', color: AppTheme.error),
            ],
          ),
        ],
      ),
    );
  }
}

/// Les statistiques suivies saison par saison. Les passes décisives n'en
/// font pas partie : elles ne sont comptées que depuis la saison 2026-2027.
const _evolutionStats = [
  (stat: PlayerStat.matches, label: 'Matchs'),
  (stat: PlayerStat.winRate, label: '% Victoires'),
  (stat: PlayerStat.goals, label: 'Buts'),
  (stat: PlayerStat.manOfTheMatch, label: 'HDM'),
  (stat: PlayerStat.goalsPerMatch, label: 'Buts / match'),
];

/// Valeur d'une saison ; une moyenne sans match joué n'en a pas.
num? _seasonValue(PlayerStat stat, PlayerSeasonStats season) {
  final played = season.matchesPlayed;
  return switch (stat) {
    PlayerStat.matches => played,
    PlayerStat.winRate => played == 0 ? null : season.wins * 100 / played,
    PlayerStat.goals => season.goals,
    PlayerStat.manOfTheMatch => season.hdm,
    PlayerStat.goalsPerMatch => played == 0 ? null : season.goals / played,
    PlayerStat.assists => null,
  };
}

/// Évolution des statistiques de carrière, une barre par saison.
///
/// N'apparaît qu'à partir de deux saisons ; reste absente si le détail par
/// saison ne peut pas être lu, plutôt que d'afficher une erreur sous des
/// chiffres justes.
class _EvolutionCard extends StatelessWidget {
  const _EvolutionCard({
    required this.seasons,
    required this.stat,
    required this.onStatChanged,
  });

  final AsyncValue<List<PlayerSeasonStats>> seasons;
  final PlayerStat stat;
  final ValueChanged<PlayerStat> onStatChanged;

  @override
  Widget build(BuildContext context) {
    return seasons.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        if (list.length < 2) return const SizedBox.shrink();
        final last = list.last;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: _cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionTitle('Évolution'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final option in _evolutionStats)
                      _StatChoice(
                        label: option.label,
                        selected: option.stat == stat,
                        onTap: () => onStatChanged(option.stat),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _SeasonBars(seasons: list, stat: stat),
                if (last.isCurrent) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Saison ${last.seasonName} en cours.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatChoice extends StatelessWidget {
  const _StatChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(
      side: BorderSide(
        color: selected
            ? AppTheme.accent.withValues(alpha: .55)
            : AppTheme.outline.withValues(alpha: .5),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        // Même bleu que l'onglet de période choisi.
        color: selected ? const Color(0xFF1E3A66) : Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? AppTheme.accent : AppTheme.textFaint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hauteur réservée aux barres et à leur valeur.
const _barAreaHeight = 130.0;

/// Largeur minimale d'une saison : en dessous, le graphique défile, la
/// saison la plus récente d'abord visible.
const _minSeasonSlot = 36.0;

/// Matchs joués pour qu'une moyenne de saison compte comme la meilleure.
const _seasonAverageMinMatches = 5;

class _SeasonBars extends StatelessWidget {
  const _SeasonBars({required this.seasons, required this.stat});

  final List<PlayerSeasonStats> seasons;
  final PlayerStat stat;

  @override
  Widget build(BuildContext context) {
    final values = [for (final s in seasons) _seasonValue(stat, s)];
    var maxValue = 0.0;
    for (final value in values) {
      if (value != null && value > maxValue) maxValue = value.toDouble();
    }
    // La meilleure saison passe en or. Pour une moyenne, il lui faut autant
    // de matchs que pour être classé sur une saison (voir
    // averageRankingMinMatches) : deux matchs gagnés ne font pas une saison
    // à 100 %.
    // Des saisons à égalité, telle que la valeur s'affiche, sont toutes en
    // or.
    bool eligible(int i) {
      final value = values[i];
      if (value == null || value <= 0) return false;
      return !stat.isAverage ||
          seasons[i].matchesPlayed >= _seasonAverageMinMatches;
    }

    num? best;
    for (var i = 0; i < seasons.length; i++) {
      if (eligible(i) && (best == null || values[i]! > best)) best = values[i];
    }
    final bestLabel = best == null ? null : stat.format(best);

    return LayoutBuilder(
      builder: (context, constraints) {
        final fits = seasons.length * _minSeasonSlot <= constraints.maxWidth;
        final slot =
            fits ? constraints.maxWidth / seasons.length : _minSeasonSlot;
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < seasons.length; i++)
              SizedBox(
                width: slot,
                child: _SeasonBar(
                  season: seasons[i],
                  value: values[i],
                  label: values[i] == null ? '–' : stat.format(values[i]!),
                  statLabel: stat.label,
                  share: values[i] == null || maxValue == 0
                      ? 0
                      : values[i]! / maxValue,
                  isBest: eligible(i) && stat.format(values[i]!) == bestLabel,
                ),
              ),
          ],
        );
        if (fits) return row;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: row,
        );
      },
    );
  }
}

class _SeasonBar extends StatelessWidget {
  const _SeasonBar({
    required this.season,
    required this.value,
    required this.label,
    required this.statLabel,
    required this.share,
    required this.isBest,
  });

  final PlayerSeasonStats season;
  final num? value;
  final String label;
  final String statLabel;

  /// Part de la plus haute valeur affichée, entre 0 et 1.
  final double share;
  final bool isBest;

  /// « 2023-2024 » devient « 23-24 ».
  String get _shortSeason {
    final name = season.seasonName;
    return name.length == 9 && name[4] == '-'
        ? '${name.substring(2, 4)}-${name.substring(7)}'
        : name;
  }

  @override
  Widget build(BuildContext context) {
    const valueHeight = 22.0;
    final value = this.value;
    // Une petite valeur garde une barre visible ; zéro n'en a pas.
    final barHeight = value == null || value <= 0
        ? 0.0
        : (share * (_barAreaHeight - valueHeight)).clamp(3.0, double.infinity);
    final color = isBest ? _gold : AppTheme.primaryBright;

    return Semantics(
      label: '${season.seasonName}${season.isCurrent ? ' (en cours)' : ''} : '
          '$label, $statLabel',
      excludeSemantics: true,
      child: Column(
        children: [
          SizedBox(
            height: _barAreaHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: valueHeight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: _display,
                        fontSize: 13,
                        color: isBest ? _gold : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  height: barHeight,
                  width: 18,
                  decoration: BoxDecoration(
                    // La saison en cours, encore incomplète, s'efface un peu.
                    color:
                        season.isCurrent ? color.withValues(alpha: .45) : color,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(5)),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            color: AppTheme.outline.withValues(alpha: .6),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _shortSeason,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10.5,
                color: season.isCurrent
                    ? AppTheme.textSecondary
                    : AppTheme.textFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.value, required this.label, this.color});

  final int value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$value ',
            style: TextStyle(
              fontFamily: _display,
              fontSize: 16,
              color: color ?? AppTheme.textPrimary,
            ),
          ),
          TextSpan(text: label),
        ],
      ),
      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
    );
  }
}
