import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/calendar_card_palette.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_secondary_tabs.dart';
import 'package:as_grinta/core/widgets/match_contribution_icons.dart';
import 'package:as_grinta/core/widgets/grinta_skeleton.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/data/statistics_badge_emblems_provider.dart';
import 'package:as_grinta/features/badges/presentation/badge_detail_sheet.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem_body.dart';
import 'package:as_grinta/features/players/data/player_card_repository.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:as_grinta/features/statistics/presentation/stats_hub_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    ref.invalidate(playerCardBadgesProvider);
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
    // Sert au seuil de classement de la saison en cours : il ne s'applique
    // qu'une fois passés les premiers matchs de l'équipe.
    final teamMatches = _period == StatisticsPeriod.current
        ? ref
            .watch(teamStatisticsPeriodProvider(StatisticsPeriod.current))
            .asData
            ?.value
            .matchesPlayed
        : null;

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
    if (info.firstName == null && careerRow == null && allTime.hasValue) {
      return const _Message(
        title: 'Pas de fiche joueur',
        message: 'Ce membre n’a encore joué aucun match avec l’équipe.',
      );
    }

    final name = info.firstName ??
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
            nickname: info.nickname,
            photoUrl: info.photoUrl,
            profileId: info.profileId,
            isGoalkeeper: isGoalkeeper,
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
                  _StatGrid(
                    player: row,
                    data: data,
                    teamMatches: teamMatches,
                  ),
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
          // Un joueur d'effectif sans compte ne peut pas gagner de badge.
          if (info.profileId != null) ...[
            const SizedBox(height: 20),
            const _SectionTitle('Badges'),
            const SizedBox(height: 10),
            _BadgeSection(profileId: info.profileId!),
          ],
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

String _ordinal(int rank) => rank == 1 ? '1er' : '${rank}e';

String _decimal(double value) => value.toStringAsFixed(2).replaceAll('.', ',');

final _nameWordStart = RegExp(r"(^|[ '’-])(\p{L})", unicode: true);

/// « FRANÇOIS » ou « françois » deviennent « François » ; « jean-pierre »,
/// « Jean-Pierre ».
String _properCaseName(String value) =>
    value.trim().toLowerCase().replaceAllMapped(
          _nameWordStart,
          (match) => '${match[1]}${match[2]!.toUpperCase()}',
        );

class _Hero extends ConsumerWidget {
  const _Hero({
    required this.name,
    required this.nickname,
    required this.photoUrl,
    required this.profileId,
    required this.isGoalkeeper,
  });

  final String name;
  final String? nickname;
  final String? photoUrl;
  final String? profileId;
  final bool isGoalkeeper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nickname = this.nickname;
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
            child: Row(
              children: [
                // Même avatar que sur les compositions d'équipe.
                PlayerAvatar(
                  photoUrl: photoUrl,
                  name: name,
                  isGoalkeeper: isGoalkeeper,
                  size: _heroPhotoSize,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Une seule ligne, réduite au besoin : un prénom ne se
                      // coupe pas au milieu.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _properCaseName(name),
                          maxLines: 1,
                          style: const TextStyle(
                            fontFamily: _display,
                            fontSize: 30,
                            height: 1.05,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      if (nickname != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '« $nickname »',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 12),
                  // Aussi haut que la photo, pas plus.
                  SizedBox(
                    height: _heroPhotoSize,
                    width: _heroPhotoSize /
                        badgeEmblemHeightRatio(hasStar: badge.hasStar),
                    child: FittedBox(
                      child: BadgeEmblem(
                        emoji: badge.emoji,
                        imageUrl: badge.imageUrl,
                        color: badge.color,
                        baremeLabel: badge.valueLabel,
                        descriptor: badge.descriptor,
                        showStar: badge.hasStar,
                        starCount: badge.stars,
                        size: 192,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Photo du joueur dans l'en-tête ; le badge arboré prend la même hauteur.
const _heroPhotoSize = 96.0;

/// Or, argent et bronze pour les trois premiers du club sur une statistique.
const _gold = Color(0xFFFFD84A);
// Plus sombre que le blanc des autres rangs, pour que les deux ne se
// confondent pas.
const _silver = Color(0xFFAEBACA);
const _bronze = Color(0xFFDB9A5B);

Color _medalColor(int? rank) => switch (rank) {
      1 => _gold,
      2 => _silver,
      3 => _bronze,
      _ => AppTheme.textPrimary,
    };

/// Matchs joués exigés pour figurer au classement des moyennes (% de
/// victoires, buts par match) : sans ce seuil, un joueur venu une seule fois
/// et reparti vainqueur serait « 1er du club ».
///
/// Toutes saisons : 20 matchs. Saison précédente : 5. Saison en cours : aucun
/// tant que l'équipe a joué 5 matchs ou moins, 5 ensuite. [teamMatches] est
/// le nombre de matchs de l'équipe sur la saison en cours, quand on le
/// connaît ; à défaut, le joueur le plus présent en donne un minimum.
int averageRankingMinMatches(
  StatisticsPeriod period, {
  required int? teamMatches,
  required Iterable<PlayerStatistics> players,
}) {
  switch (period) {
    case StatisticsPeriod.allTime:
      return 20;
    case StatisticsPeriod.previous:
      return 5;
    case StatisticsPeriod.current:
      var played = teamMatches ?? 0;
      for (final p in players) {
        final matches = p.matchesPlayed ?? 0;
        if (matches > played) played = matches;
      }
      return played > 5 ? 5 : 0;
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({
    required this.player,
    required this.data,
    required this.teamMatches,
  });

  final PlayerStatistics player;
  final StatisticsPeriodData data;
  final int? teamMatches;

  @override
  Widget build(BuildContext context) {
    final players = data.players;
    final matches = player.matchesPlayed ?? 0;
    final tracksAssists = statisticsShowsAssistsColumn(data);

    double winRate(PlayerStatistics p) {
      final played = p.matchesPlayed ?? 0;
      return played == 0 ? 0 : (p.wins ?? 0) * 100 / played;
    }

    double goalsPerMatch(PlayerStatistics p) {
      final played = p.matchesPlayed ?? 0;
      return played == 0 ? 0 : p.goals / played;
    }

    final minMatches = averageRankingMinMatches(
      data.period,
      teamMatches: teamMatches,
      players: players,
    );
    bool eligible(PlayerStatistics p) => (p.matchesPlayed ?? 0) >= minMatches;

    // Une valeur nulle ne classe personne : sans cela, une saison où personne
    // n'a encore fait de passe décisive sacrerait tout l'effectif « 1er ».
    int? rankOf(
      num Function(PlayerStatistics) of, {
      bool Function(PlayerStatistics)? among,
    }) {
      final mine = of(player);
      if (mine <= 0) return null;
      return 1 +
          players
              .where((p) => (among == null || among(p)) && of(p) > mine)
              .length;
    }

    _StatTile tile(
      String label,
      String value,
      num Function(PlayerStatistics) of, {
      bool ranked = true,
    }) {
      final rank = ranked ? rankOf(of) : null;
      return _StatTile(value: value, label: label, rank: rank);
    }

    // Moyennes : seuls les joueurs assez présents sont classés, entre eux.
    _StatTile averageTile(
      String label,
      String value,
      num Function(PlayerStatistics) of,
    ) {
      if (!eligible(player)) {
        return _StatTile(
          value: value,
          label: label,
          rank: null,
          rankNote: 'N/A',
        );
      }
      return _StatTile(
        value: value,
        label: label,
        rank: rankOf(of, among: eligible),
      );
    }

    final tiles = <_StatTile>[
      tile('Matchs', '$matches', (p) => p.matchesPlayed ?? 0),
      averageTile(
        'Victoires',
        matches == 0 ? '–' : '${winRate(player).round()} %',
        winRate,
      ),
      tile('Buts', '${player.goals}', (p) => p.goals),
      // Les passes ne sont suivies que depuis leur mise en service : sur une
      // période antérieure, un zéro ferait croire à un manque de saisie.
      tile(
        'Passes D.',
        tracksAssists ? '${player.assists}' : '–',
        (p) => p.assists,
        ranked: tracksAssists,
      ),
      tile('Homme du match', '${player.hdm ?? 0}', (p) => p.hdm ?? 0),
      averageTile(
        'Buts / match',
        matches == 0 ? '–' : _decimal(goalsPerMatch(player)),
        goalsPerMatch,
      ),
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
  });

  final String value;
  final String label;

  /// Remplace la ligne de rang quand le joueur n'est pas classé (« N/A » :
  /// pas assez de matchs joués).
  final String? rankNote;

  /// Rang au club sur cette statistique ; `null` quand il n'a pas de sens
  /// (valeur nulle, statistique non suivie sur la période).
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final rank = this.rank;
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

class _BadgeSection extends ConsumerWidget {
  const _BadgeSection({required this.profileId});

  final String profileId;

  static const _columns = 4;
  static const _gap = 10.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(playerCardBadgesProvider(profileId));
    return badges.when(
      loading: () => GrintaSkeleton.rows(itemCount: 2),
      error: (error, _) => _InlineNote(humanizeError(error)),
      data: (list) {
        if (list.isEmpty) {
          return const _InlineNote('Aucun badge gagné pour l’instant.');
        }
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDecoration,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  (constraints.maxWidth - (_columns - 1) * _gap) / _columns;
              return Wrap(
                spacing: _gap,
                runSpacing: 14,
                children: [
                  for (final badge in list)
                    SizedBox(
                      width: width,
                      child: _BadgeTile(badge: badge, size: width),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, required this.size});

  final ArmoireBadge badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final def = badge.def;
    return Semantics(
      button: true,
      label: def.name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showBadgeDetailSheet(context, def,
            showLadder: false, showHolders: true),
        child: Column(
          children: [
            BadgeEmblem(
              emoji: def.emoji,
              imageUrl: def.imageUrl,
              color: def.color,
              baremeLabel: baremeLabelFor(def.metric, badge.displayValue),
              descriptor: badgeDescriptorFor(
                code: def.code,
                metric: def.metric,
                category: def.category,
                name: def.name,
              ),
              showStar: def.hasStar,
              starCount: badge.stars,
              size: size,
            ),
            const SizedBox(height: 6),
            Text(
              def.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                height: 1.15,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
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
