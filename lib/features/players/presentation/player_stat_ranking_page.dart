import 'dart:math' as math;

import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_secondary_tabs.dart';
import 'package:as_grinta/core/widgets/grinta_skeleton.dart';
import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/badges/presentation/badge_display_scope.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:as_grinta/features/players/data/player_card_repository.dart';
import 'package:as_grinta/features/players/data/player_stat_ranking.dart';
import 'package:as_grinta/features/players/presentation/player_card_link.dart';
import 'package:as_grinta/features/players/presentation/player_card_page.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:as_grinta/features/statistics/presentation/stats_hub_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Même largeur de colonne que le tableau des Statistiques.
const _columnWidth = 64.0;

/// Hauteur approximative d'une ligne, pour amener d'un coup la liste près du
/// joueur mis en évidence avant de le centrer précisément.
const _estimatedRowHeight = 56.0;

/// Classement complet du club sur une statistique de la fiche joueur.
///
/// Reprend le tableau de l'onglet Statistiques › Joueurs : rang, nom (avec
/// son badge), la statistique, puis le nombre de matchs joués. Le joueur dont
/// on vient est mis en évidence.
class PlayerStatRankingPage extends ConsumerStatefulWidget {
  const PlayerStatRankingPage({
    super.key,
    required this.stat,
    required this.initialPeriod,
    this.playerKey,
  });

  final PlayerStat? stat;
  final StatisticsPeriod initialPeriod;
  final PlayerCardKey? playerKey;

  @override
  ConsumerState<PlayerStatRankingPage> createState() =>
      _PlayerStatRankingPageState();
}

class _PlayerStatRankingPageState extends ConsumerState<PlayerStatRankingPage> {
  late StatisticsPeriod _period = widget.initialPeriod;
  final _scroll = ScrollController();
  final _highlightedRow = GlobalKey();

  /// Le défilement vers le joueur ne se fait qu'une fois par période : on ne
  /// reprend pas la main sur quelqu'un qui fait défiler la liste.
  StatisticsPeriod? _scrolledFor;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(statisticsPeriodProvider(_period));
    await ref.read(statisticsPeriodProvider(_period).future);
  }

  void _scrollToHighlighted(int index) {
    if (_scrolledFor == _period) return;
    _scrolledFor = _period;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      // Les lignes lointaines ne sont pas encore construites : on s'en
      // approche d'abord, puis on centre la ligne une fois qu'elle existe.
      final target = math.max(0.0, (index - 2) * _estimatedRowHeight);
      _scroll.jumpTo(math.min(target, _scroll.position.maxScrollExtent));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final rowContext = _highlightedRow.currentContext;
        if (!mounted || rowContext == null) return;
        Scrollable.ensureVisible(rowContext, alignment: .4);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final stat = widget.stat;
    return Scaffold(
      appBar: GrintaAppBar(title: Text(stat?.label ?? 'Classement')),
      // Comme dans le module Statistiques : badges à côté des noms, et un nom
      // touché ouvre la fiche du joueur.
      body: BadgeDisplayScope(
        showBadges: true,
        child: PlayerCardLinkScope(
          enabled: true,
          child: stat == null
              ? const _Message(
                  title: 'Classement introuvable',
                  message: 'Ce lien ne désigne aucune statistique.',
                )
              : Column(
                  children: [
                    const SizedBox(height: AppSpacing.contentGap),
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
                    Expanded(child: _table(context, stat)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _table(BuildContext context, PlayerStat stat) {
    final async = ref.watch(statisticsPeriodProvider(_period));
    // Seuil des moyennes de la saison en cours : il dépend du nombre de
    // matchs de l'équipe, comme sur la fiche.
    final teamMatches = _period == StatisticsPeriod.current
        ? ref
            .watch(teamStatisticsPeriodProvider(StatisticsPeriod.current))
            .asData
            ?.value
            .matchesPlayed
        : null;

    return async.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: GrintaSkeleton.rows(itemCount: 7),
      ),
      error: (error, _) => _Message(
        title: 'Classement indisponible',
        message: humanizeError(error),
        onRefresh: _refresh,
      ),
      data: (data) {
        if (data.players.isEmpty) {
          return _Message(
            title: 'Pas encore de statistiques',
            message: 'Les stats apparaîtront après le premier match validé.',
            onRefresh: _refresh,
          );
        }
        if (stat == PlayerStat.assists && !statisticsShowsAssistsColumn(data)) {
          return _Message(
            title: 'Pas de passes décisives',
            message: 'Les passes décisives n’étaient pas encore suivies '
                'sur cette période.',
            onRefresh: _refresh,
          );
        }

        final minMatches = averageRankingMinMatches(
          data.period,
          teamMatches: teamMatches,
          players: data.players,
        );
        final entries =
            rankPlayersOnStat(data.players, stat, minMatches: minMatches);
        final key = widget.playerKey;
        final highlighted = key == null
            ? -1
            : entries.indexWhere((e) => isPlayerOfCard(e.player, key));
        if (highlighted >= 0) _scrollToHighlighted(highlighted);

        // Le classement des moyennes s'arrête aux joueurs assez présents ; les
        // autres suivent, sous une ligne qui l'explique.
        final firstUnranked = entries.indexWhere((e) => !e.isRanked);
        final showsMatches = stat != PlayerStat.matches;
        final columns = showsMatches ? 2 : 1;

        final pinnedWidth = grintaTablePinnedWidthForNames(
          context,
          entries.map((e) => capitalizePersonName(e.player.playerName)),
          trailingWidth: statisticsBadgeSize,
          trailingGap: nameWithBadgesGap,
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.contentGap,
            AppSpacing.screenGutter,
            32,
          ),
          child: StickyHeaderTableCard(
            controller: _scroll,
            onRefresh: _refresh,
            pinnedWidth: pinnedWidth,
            minWidth: pinnedWidth + columns * _columnWidth,
            pinnedHeader: const SizedBox.shrink(),
            scrollableHeader: Padding(
              padding: grintaTableScrollableHeaderPadding,
              child: Row(
                children: [
                  _HeaderCell(stat.columnLabel, active: true),
                  if (showsMatches) _HeaderCell(PlayerStat.matches.columnLabel),
                ],
              ),
            ),
            rows: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i == firstUnranked) _unrankedSeparator(context, minMatches),
                _row(
                  context,
                  entry: entries[i],
                  stat: stat,
                  showsMatches: showsMatches,
                  highlightKey: i == highlighted ? _highlightedRow : null,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {this.active = false});

  final String label;

  /// La statistique du classement, en couleur comme une colonne triée dans
  /// le tableau des Statistiques.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final style = grintaTableHeaderTextStyle(
      context,
      color: active ? AppTheme.accent : null,
    );
    return Expanded(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(
          child: Text(label, textAlign: TextAlign.center, style: style),
        ),
      ),
    );
  }
}

StickyTableRow _unrankedSeparator(BuildContext context, int minMatches) {
  return StickyTableRow(
    pinned: Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
      child: Text(
        'Moins de $minMatches matchs',
        style: grintaTableHeaderTextStyle(context, color: AppTheme.textFaint),
      ),
    ),
    scrollable: const SizedBox.shrink(),
  );
}

StickyTableRow _row(
  BuildContext context, {
  required PlayerStatRankingEntry entry,
  required PlayerStat stat,
  required bool showsMatches,
  required GlobalKey? highlightKey,
}) {
  final player = entry.player;
  final valueStyle = grintaTableCellTextStyle(context);

  Widget value(String text) => Expanded(
        child: Text(text, textAlign: TextAlign.center, style: valueStyle),
      );

  Widget pinned = PlayerCardLink(
    playerKey: (
      profileId: player.profileId,
      fullName: player.fullName,
      isGoalkeeper: player.isGoalkeeper,
    ),
    child: Padding(
      padding: grintaTablePinnedRowPadding,
      child: Row(
        children: [
          if (entry.rank case final rank?)
            GrintaTableRankCell(rank: rank)
          else
            const _UnrankedCell(),
          Expanded(
            child: NameWithBadges(
              profileId: player.profileId,
              name: player.playerName,
              badgeSize: statisticsBadgeSize,
              alignBadgesEnd: true,
            ),
          ),
        ],
      ),
    ),
  );

  Widget scrollable = Padding(
    padding: grintaTableScrollableRowPadding,
    child: Row(
      children: [
        value(stat.display(player)),
        if (showsMatches) value(PlayerStat.matches.display(player)),
      ],
    ),
  );

  // Même mise en évidence que la ligne de l'utilisateur dans Statistiques.
  if (highlightKey != null) {
    final accent = Theme.of(context).colorScheme.secondary;
    pinned = DecoratedBox(
      key: highlightKey,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .14),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: pinned,
    );
    scrollable = DecoratedBox(
      decoration: BoxDecoration(color: accent.withValues(alpha: .14)),
      child: scrollable,
    );
  }

  return StickyTableRow(pinned: pinned, scrollable: scrollable);
}

/// Place du rang pour un joueur non classé : un tiret, aligné comme les
/// rangs au-dessus.
class _UnrankedCell extends StatelessWidget {
  const _UnrankedCell();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: grintaTableRankGap),
      child: SizedBox(
        width: grintaTableRankWidth,
        child: Text(
          '–',
          textAlign: TextAlign.end,
          style: grintaTableRankTextStyle(context),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.message,
    this.onRefresh,
  });

  final String title;
  final String message;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sectionGap,
        AppSpacing.screenGutter,
        32,
      ),
      children: [
        Card(
          child: GrintaEmptyState(
            icon: Icons.bar_chart_rounded,
            title: title,
            message: message,
          ),
        ),
      ],
    );
    final onRefresh = this.onRefresh;
    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh, child: list);
  }
}
