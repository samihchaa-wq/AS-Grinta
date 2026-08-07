import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/matches/data/calendar_history_repository.dart';
import 'package:as_grinta/features/matches/data/historical_match_detail_repository.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fiche en lecture seule d'un match de l'historique importé : composition
/// (quand elle est connue), buteurs et HDM. Contrairement à [MatchDetailsPage],
/// il n'y a ici ni pronostics, ni vote, ni action d'administration : tout est
/// figé, importé depuis les archives du club.
///
/// [initialMatch] évite un aller-retour réseau quand on arrive depuis une
/// carte du calendrier qui l'a déjà chargé ; sans lui (arrivée directe sur
/// l'URL, ex. rechargement de page), l'en-tête est retrouvé via [matchId]
/// dans la liste complète de l'historique.
class HistoricalMatchDetailPage extends ConsumerWidget {
  const HistoricalMatchDetailPage({
    required this.matchId,
    this.initialMatch,
    super.key,
  });

  final String matchId;
  final HistoricalMatchResult? initialMatch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(historicalMatchDetailProvider(matchId));

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Match archivé')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(historicalMatchDetailProvider(matchId));
          await ref.read(historicalMatchDetailProvider(matchId).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _HistoricalMatchHeaderSection(
              matchId: matchId,
              initialMatch: initialMatch,
            ),
            const SizedBox(height: 16),
            detailAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: GrintaProgressIndicator()),
              ),
              error: (error, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(humanizeError(error)),
                ),
              ),
              data: (detail) {
                if (detail == null || detail.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        "Aucun détail n'a été retrouvé pour ce match dans "
                        'les archives du club.',
                      ),
                    ),
                  );
                }
                return _HistoricalMatchDetailBody(detail: detail);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoricalMatchHeaderSection extends ConsumerWidget {
  const _HistoricalMatchHeaderSection({
    required this.matchId,
    required this.initialMatch,
  });

  final String matchId;
  final HistoricalMatchResult? initialMatch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = initialMatch;
    if (match != null) return _HistoricalMatchHeader(match: match);

    final allAsync = ref.watch(allHistoricalMatchesProvider);
    return allAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: GrintaProgressIndicator()),
      ),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(humanizeError(error)),
        ),
      ),
      data: (all) {
        final found = all.where((m) => m.id == matchId).firstOrNull;
        if (found == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Match introuvable dans les archives.'),
            ),
          );
        }
        return _HistoricalMatchHeader(match: found);
      },
    );
  }
}

class _HistoricalMatchHeader extends StatelessWidget {
  const _HistoricalMatchHeader({required this.match});

  final HistoricalMatchResult match;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppFormats.date(match.date),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary.withValues(alpha: .7),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            MatchFixture(
              homeName: match.isHome ? 'AS Grinta' : match.opponentName,
              awayName: match.isHome ? match.opponentName : 'AS Grinta',
              grintaIsHome: match.isHome,
              homeScore: match.isHome ? match.grintaScore : match.opponentScore,
              awayScore: match.isHome ? match.opponentScore : match.grintaScore,
              finished: true,
              nameStyle: Theme.of(context).textTheme.titleLarge,
              scoreFontSize: 26,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoricalMatchDetailBody extends StatelessWidget {
  const _HistoricalMatchDetailBody({required this.detail});

  final HistoricalMatchDetail detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (detail.hasComposition) ...[
          _SectionCard(
            title: 'Composition',
            subtitle: detail.formation,
            child: _HistoricalPitch(
              players: detail.fieldPlayers,
              scorers: detail.scorers,
              motmNames: detail.motmNames,
            ),
          ),
          if (detail.benchPlayers.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Banc',
              child: _NameChips(names: detail.benchPlayers),
            ),
          ],
        ] else if (detail.presentNames.isNotEmpty) ...[
          _SectionCard(
            title: 'Présents',
            child: _NameChips(names: detail.presentNames),
          ),
        ],
        if (detail.scorers.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Buteurs',
            child: _ScorersList(scorers: detail.scorers),
          ),
        ],
        if (detail.motmNames.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Homme du match',
            child: _NameChips(names: detail.motmNames, highlighted: true),
          ),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary.withValues(alpha: .7),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _NameChips extends StatelessWidget {
  const _NameChips({required this.names, this.highlighted = false});

  final List<String> names;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final name in names)
          Chip(
            label: Text(name),
            avatar: highlighted
                ? const Text('👑', style: TextStyle(fontSize: 14))
                : null,
            backgroundColor: highlighted
                ? AppTheme.reward.withValues(alpha: .18)
                : AppTheme.surfaceHigh,
            side: BorderSide(
              color: highlighted
                  ? AppTheme.reward.withValues(alpha: .5)
                  : AppTheme.outline,
            ),
          ),
      ],
    );
  }
}

class _ScorersList extends StatelessWidget {
  const _ScorersList({required this.scorers});

  final List<HistoricalScorer> scorers;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final scorer in scorers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    scorer.name,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Text(
                  '⚽' * scorer.goals.clamp(1, 6) +
                      (scorer.goals > 6 ? ' +${scorer.goals - 6}' : ''),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Terrain de la fiche archivée, redessiné avec les mêmes briques que la
/// composition Live ([PitchPainter], [PlayerAvatar], `GoalBallsRow`) pour
/// qu'une fiche de match archivé et une fiche de match courant se
/// ressemblent trait pour trait.
class _HistoricalPitch extends StatelessWidget {
  const _HistoricalPitch({
    required this.players,
    required this.scorers,
    required this.motmNames,
  });

  final List<HistoricalFieldPlayer> players;
  final List<HistoricalScorer> scorers;
  final List<String> motmNames;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: AspectRatio(
        aspectRatio: 0.68,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF174936),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFF6DAD8B), width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    const Positioned.fill(
                      child: CustomPaint(painter: PitchPainter()),
                    ),
                    for (final player in players)
                      _positionedPlayer(player, constraints.biggest),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _positionedPlayer(HistoricalFieldPlayer player, Size size) {
    const markerWidth = 64.0;
    const markerHeight = 84.0;
    final x = (player.xPct / 100).clamp(0.08, 0.92).toDouble();
    final y = (player.yPct / 100).clamp(0.06, 0.94).toDouble();
    final left = (x * size.width - markerWidth / 2)
        .clamp(0.0, size.width - markerWidth)
        .toDouble();
    final top = (y * size.height - markerHeight / 2)
        .clamp(0.0, size.height - markerHeight)
        .toDouble();

    final goals = scorers
        .where((scorer) => scorer.name == player.name)
        .fold<int>(0, (total, scorer) => total + scorer.goals);

    return Positioned(
      left: left,
      top: top,
      width: markerWidth,
      height: markerHeight,
      child: _PlayerMarker(
        player: player,
        goals: goals,
        isMotm: motmNames.contains(player.name),
      ),
    );
  }
}

class _PlayerMarker extends StatelessWidget {
  const _PlayerMarker({
    required this.player,
    required this.goals,
    required this.isMotm,
  });

  final HistoricalFieldPlayer player;
  final int goals;
  final bool isMotm;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 60,
          height: 64,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: PlayerAvatar(
                  photoUrl: null,
                  name: player.name,
                  isGoalkeeper: player.isGoalkeeper,
                  size: 52,
                ),
              ),
              if (isMotm)
                const Positioned(
                  top: 6,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text('👑', style: TextStyle(fontSize: 18)),
                  ),
                ),
              if (goals > 0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Center(child: GoalBallsRow(goals: goals)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          player.name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1.1,
            shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
          ),
        ),
      ],
    );
  }
}
