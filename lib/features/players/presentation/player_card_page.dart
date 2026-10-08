import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/calendar_card_palette.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_secondary_tabs.dart';
import 'package:as_grinta/core/widgets/grinta_skeleton.dart';
import 'package:as_grinta/features/badges/data/statistics_badge_emblems_provider.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem_body.dart';
import 'package:as_grinta/features/players/data/player_card_repository.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:as_grinta/features/statistics/presentation/stats_hub_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _display = 'Oswald';

/// Fiche joueur, ouverte en touchant un nom dans le module Statistiques.
///
/// Les chiffres par période viennent des mêmes classements que l'onglet
/// Joueurs (déjà en cache) ; seuls l'identité et les derniers matchs sont
/// chargés en plus.
class PlayerCardPage extends ConsumerStatefulWidget {
  const PlayerCardPage({super.key, required this.playerKey});

  final PlayerCardKey? playerKey;

  @override
  ConsumerState<PlayerCardPage> createState() => _PlayerCardPageState();
}

class _PlayerCardPageState extends ConsumerState<PlayerCardPage> {
  StatisticsPeriod _period = StatisticsPeriod.current;

  Future<void> _refresh(PlayerCardKey key) async {
    for (final period in StatisticsPeriod.values) {
      ref.invalidate(statisticsPeriodProvider(period));
    }
    ref.invalidate(playerCardDetailsProvider(key));
    await ref.read(playerCardDetailsProvider(key).future);
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.playerKey;
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Fiche joueur')),
      body: key == null
          ? const _Message(
              title: 'Joueur introuvable',
              message: 'Ce lien ne désigne aucun joueur.',
            )
          : _body(context, key),
    );
  }

  Widget _body(BuildContext context, PlayerCardKey key) {
    final details = ref.watch(playerCardDetailsProvider(key));
    final periodData = ref.watch(statisticsPeriodProvider(_period));
    final allTime =
        ref.watch(statisticsPeriodProvider(StatisticsPeriod.allTime));

    if (details.isLoading && !details.hasValue) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: GrintaSkeleton.rows(itemCount: 6),
      );
    }
    if (details.hasError && !details.hasValue) {
      return _Message(
        title: 'Fiche indisponible',
        message: humanizeError(details.error!),
      );
    }

    final info = details.requireValue;
    final careerRow = allTime.asData?.value.players
        .where((p) => _isSamePlayer(p, key))
        .firstOrNull;
    if (info.displayName == null && careerRow == null && allTime.hasValue) {
      return const _Message(
        title: 'Pas de fiche joueur',
        message: 'Ce membre n’a encore joué aucun match avec l’équipe.',
      );
    }

    final name = info.displayName ??
        careerRow?.playerName ??
        capitalizePersonName(key.fullName);
    final isGoalkeeper = careerRow?.isGoalkeeper ?? key.isGoalkeeper;

    return RefreshIndicator(
      onRefresh: () => _refresh(key),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter + 4,
          12,
          AppSpacing.screenGutter + 4,
          32,
        ),
        children: [
          _Hero(
            name: name,
            photoUrl: info.photoUrl,
            profileId: info.profileId,
            isGoalkeeper: isGoalkeeper,
            careerMatches: careerRow?.matchesPlayed,
          ),
          const SizedBox(height: 16),
          GrintaSecondaryTabs<StatisticsPeriod>(
            segments: const [
              ButtonSegment(
                value: StatisticsPeriod.current,
                label: Text('Saison'),
              ),
              ButtonSegment(
                value: StatisticsPeriod.previous,
                label: Text('Précédente'),
              ),
              ButtonSegment(
                value: StatisticsPeriod.allTime,
                label: Text('Carrière'),
              ),
            ],
            selected: {_period},
            onSelectionChanged: (value) =>
                setState(() => _period = value.first),
          ),
          const SizedBox(height: 12),
          periodData.when(
            loading: () => GrintaSkeleton.rows(itemCount: 2),
            error: (error, _) => _InlineNote(humanizeError(error)),
            data: (data) {
              final row =
                  data.players.where((p) => _isSamePlayer(p, key)).firstOrNull;
              if (row == null) {
                return const _InlineNote('Aucun match sur cette période.');
              }
              return Column(
                children: [
                  _StatGrid(player: row, data: data),
                  const SizedBox(height: 8),
                  _RecordCard(player: row, recent: info.recentMatches),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Derniers matchs'),
          const SizedBox(height: 10),
          if (info.recentMatches.isEmpty)
            const _InlineNote(
              'Aucun match suivi dans l’application pour l’instant.',
            )
          else
            _MatchList(matches: info.recentMatches),
        ],
      ),
    );
  }
}

/// Le compte identifie le joueur quand on le connaît ; sinon, comme la vue
/// des statistiques, le nom complet et le poste.
bool _isSamePlayer(PlayerStatistics player, PlayerCardKey key) {
  if (key.profileId != null && player.profileId == key.profileId) return true;
  if (key.fullName.isEmpty) return false;
  return _normalize(player.fullName) == _normalize(key.fullName) &&
      player.isGoalkeeper == key.isGoalkeeper;
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Rang « compétition » du joueur sur une valeur : 1 + le nombre de joueurs
/// strictement devant lui.
int _clubRank(List<PlayerStatistics> players, int Function(PlayerStatistics) of,
    PlayerStatistics player) {
  final mine = of(player);
  return 1 + players.where((p) => of(p) > mine).length;
}

String _ordinal(int rank) => rank == 1 ? '1er' : '${rank}e';

String _decimal(double value) => value.toStringAsFixed(2).replaceAll('.', ',');

class _Hero extends ConsumerWidget {
  const _Hero({
    required this.name,
    required this.photoUrl,
    required this.profileId,
    required this.isGoalkeeper,
    required this.careerMatches,
  });

  final String name;
  final String? photoUrl;
  final String? profileId;
  final bool isGoalkeeper;
  final int? careerMatches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badge = profileId == null
        ? null
        : ref
            .watch(statisticsBadgeEmblemsProvider)
            .asData
            ?.value[profileId]
            ?.firstOrNull;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border:
            Border.all(color: AppTheme.primaryBright.withValues(alpha: .35)),
        gradient: const RadialGradient(
          center: Alignment.topRight,
          radius: 1.4,
          colors: [Color(0xFF2453B8), AppTheme.surfaceHero, Color(0xFF0D2A52)],
          stops: [0, .4, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -30,
            width: 210,
            height: 230,
            child: Opacity(
              opacity: .09,
              child: Image.asset(
                'assets/images/as_grinta_logo.webp',
                fit: BoxFit.contain,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.accent,
                      ),
                      child: PlayerAvatar(
                        photoUrl: photoUrl,
                        name: name,
                        isGoalkeeper: isGoalkeeper,
                        size: 84,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.toUpperCase(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: _display,
                              fontSize: 30,
                              height: 1.05,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _Chip(
                            label: isGoalkeeper ? 'Gardien' : 'Joueur de champ',
                            highlighted: true,
                          ),
                        ],
                      ),
                    ),
                    if (badge != null)
                      SizedBox(
                        width: 48,
                        height:
                            48 * badgeEmblemHeightRatio(hasStar: badge.hasStar),
                        child: FittedBox(
                          child: BadgeEmblem(
                            emoji: badge.emoji,
                            imageUrl: badge.imageUrl,
                            color: badge.color,
                            baremeLabel: badge.valueLabel,
                            descriptor: badge.descriptor,
                            showStar: badge.hasStar,
                            starCount: badge.stars,
                            size: 96,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: Colors.white.withValues(alpha: .12)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Image.asset(
                      'assets/images/as_grinta_logo.webp',
                      width: 22,
                      height: 22,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: 'AS La Grinta',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            if (careerMatches != null)
                              TextSpan(
                                text: ' · $careerMatches '
                                    '${careerMatches == 1 ? 'match' : 'matchs'}',
                              ),
                          ],
                        ),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.highlighted = false});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: highlighted
            ? AppTheme.accent
            : AppTheme.background.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: highlighted ? AppTheme.background : AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.player, required this.data});

  final PlayerStatistics player;
  final StatisticsPeriodData data;

  @override
  Widget build(BuildContext context) {
    final players = data.players;
    final matches = player.matchesPlayed ?? 0;
    final wins = player.wins ?? 0;

    String? rankOf(int value, int Function(PlayerStatistics) of) {
      if (value <= 0) return null;
      return '${_ordinal(_clubRank(players, of, player))} du club';
    }

    final tiles = <Widget>[
      _StatTile(value: '$matches', label: 'Matchs'),
      _StatTile(
        value: '${player.goals}',
        label: 'Buts',
        color: AppTheme.accent,
        note: rankOf(player.goals, (p) => p.goals),
      ),
      if (statisticsShowsAssistsColumn(data))
        _StatTile(
          value: '${player.assists}',
          label: 'Passes D.',
          note: rankOf(player.assists, (p) => p.assists),
        )
      else
        _StatTile(value: '${player.teamCleanSheets}', label: 'CS équipe'),
      _StatTile(
        value: '${player.hdm ?? 0}',
        label: 'Homme du match',
        color: AppTheme.reward,
        note: rankOf(player.hdm ?? 0, (p) => p.hdm ?? 0),
      ),
      if (player.isGoalkeeper)
        _StatTile(value: '${player.cleanSheets}', label: 'Clean sheets')
      else
        _StatTile(
          value: matches == 0 ? '–' : _decimal(player.goals / matches),
          label: 'Buts / match',
        ),
      _StatTile(
        value: matches == 0 ? '–' : '${(wins * 100 / matches).round()} %',
        label: 'Victoires',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = (constraints.maxWidth - 2 * gap) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    this.color,
    this.note,
  });

  final String value;
  final String label;
  final Color? color;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      decoration: _cardDecoration,
      child: Column(
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
                color: color ?? AppTheme.textPrimary,
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
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(
              note!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.primaryBright,
              ),
            ),
          ],
        ],
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
              const Expanded(child: _SectionTitle('Bilan avec lui')),
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

Color _resultColor(String result) => switch (result) {
      'V' => AppTheme.success,
      'D' => AppTheme.error,
      _ => AppTheme.textFaint,
    };

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
    final resultColor = _resultColor(match.result);
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
          if (match.goals > 0)
            _Contribution(icon: Icons.sports_soccer, count: match.goals),
          if (match.assists > 0)
            _Contribution(
                icon: Icons.assistant_direction, count: match.assists),
          if (match.isManOfTheMatch)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'HDM',
                style: TextStyle(
                  fontSize: 9,
                  color: AppTheme.background,
                ),
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
              '${match.grintaScore}-${match.opponentScore}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _display,
                fontSize: 16,
                color:
                    match.result == 'N' ? AppTheme.textSecondary : resultColor,
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

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
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

final _cardDecoration = BoxDecoration(
  color: AppTheme.surface,
  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
  border: Border.all(color: AppTheme.outline.withValues(alpha: .4)),
);

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontFamily: _display,
        fontSize: 15,
        letterSpacing: 1,
        color: AppTheme.textSecondary,
      ),
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppTheme.textFaint),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter + 4),
      children: [
        Card(
          child: GrintaEmptyState(
            icon: Icons.person_search_rounded,
            title: title,
            message: message,
          ),
        ),
      ],
    );
  }
}
