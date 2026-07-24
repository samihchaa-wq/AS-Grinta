import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_motm_vote_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/sport_motm_vote_page.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MatchDetailsPage extends ConsumerWidget {
  const MatchDetailsPage({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(matchDetailsProvider(matchId));
    final isAdmin =
        ref.watch(authControllerProvider).profile?.role == AuthRole.admin;
    final sportsEnabled = ref.watch(sportsManagementEnabledProvider);

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Match')),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(featureFlagsControllerProvider.notifier).refresh();
          ref
            ..invalidate(matchDetailsProvider(matchId))
            ..invalidate(sportMotmVoteProvider(matchId));
          await ref.read(matchDetailsProvider(matchId).future);
        },
        child: detailsAsync.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: 220),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(humanizeError(error)),
                ),
              ),
            ],
          ),
          data: (details) {
            if (!details.isValidated) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _UpcomingHeader(details: details),
                  const SizedBox(height: 16),
                  if (sportsEnabled)
                    _UpcomingModules(matchId: matchId, isAdmin: isAdmin)
                  else
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('Gestion sportive indisponible.'),
                      ),
                    ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _MatchHeader(details: details),
                if (sportsEnabled) ...[
                  const SizedBox(height: 16),
                  MatchMotmVoteCard(matchId: matchId),
                ],
                const SizedBox(height: 16),
                _CompletedCompositionCard(details: details, matchId: matchId),
                if (details.predictions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _PredictionsTable(
                    predictions: details.predictions,
                    actualGrinta: details.scoreGrinta ?? 0,
                    actualOpponent: details.scoreOpponent ?? 0,
                    isHome: details.location == 'domicile',
                  ),
                ],
                if (isAdmin) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.push('/matches/$matchId/finalize'),
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text('Modifier les statistiques'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _UpcomingHeader extends StatelessWidget {
  const _UpcomingHeader({required this.details});

  final MatchDetailsData details;

  @override
  Widget build(BuildContext context) {
    final home = details.location == 'domicile';
    final homeName = home ? 'AS Grinta' : details.opponentName;
    final awayName = home ? details.opponentName : 'AS Grinta';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Text(
              '$homeName vs $awayName',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(AppFormats.dateTime(details.kickoffAt)),
          ],
        ),
      ),
    );
  }
}

class _UpcomingModules extends StatelessWidget {
  const _UpcomingModules({required this.matchId, required this.isAdmin});

  final String matchId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final effectif = _MatchModule(
          icon: Icons.groups_2_outlined,
          title: 'Effectif',
          subtitle: isAdmin
              ? 'Sélectionner puis enregistrer l’effectif.'
              : 'Consulter les joueurs convoqués.',
          onTap: () => context.push(
            isAdmin
                ? '/matches/$matchId/composition?step=effectif'
                : '/matches/$matchId/lineup?section=effectif',
          ),
        );
        final composition = _MatchModule(
          icon: Icons.dashboard_customize_outlined,
          title: 'Composition',
          subtitle: isAdmin
              ? 'Créer, enregistrer et publier la composition.'
              : 'Consulter la composition publiée.',
          onTap: () => context.push(
            isAdmin
                ? '/matches/$matchId/composition?step=composition'
                : '/matches/$matchId/lineup?section=composition',
          ),
        );
        if (compact) {
          return Column(
            children: [effectif, const SizedBox(height: 12), composition],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: effectif),
            const SizedBox(width: 12),
            Expanded(child: composition),
          ],
        );
      },
    );
  }
}

class _MatchModule extends StatelessWidget {
  const _MatchModule({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 24, child: Icon(icon)),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerRight,
                child: Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchHeader extends StatelessWidget {
  const _MatchHeader({required this.details});

  final MatchDetailsData details;

  @override
  Widget build(BuildContext context) {
    final home = details.location == 'domicile';
    final grinta = details.scoreGrinta ?? 0;
    final opponent = details.scoreOpponent ?? 0;
    final title = home
        ? 'AS Grinta $grinta – $opponent ${details.opponentName}'
        : '${details.opponentName} $opponent – $grinta AS Grinta';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(AppFormats.dateTime(details.kickoffAt)),
          ],
        ),
      ),
    );
  }
}

class _CompletedCompositionCard extends ConsumerWidget {
  const _CompletedCompositionCard({
    required this.details,
    required this.matchId,
  });

  final MatchDetailsData details;
  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Priorité au rendu MPG (photos, couronne 👑, ballons ⚽) dès qu'une
    // composition publiée existe : même visuel avant et après le match.
    final composition =
        ref.watch(publishedMatchCompositionProvider(matchId)).valueOrNull;
    final fieldEntries =
        composition?.entriesFor(MatchCompositionZone.field) ?? const [];
    if (fieldEntries.isNotEmpty) {
      return _MpgCompletedCard(composition: composition!);
    }

    final starters = details.startingLineup
        .where((player) => player.isStarter)
        .toList(growable: false);
    final substitutes = details.startingLineup
        .where((player) => !player.isStarter)
        .toList(growable: false);
    final fallbackPlayers = details.playerStats;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Composition et résumé',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Les buts et le statut HDM sont affichés directement sur les joueurs.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            if (starters.isNotEmpty)
              Center(child: _CompletedPitch(players: starters))
            else if (fallbackPlayers.isEmpty)
              const Text('Composition non renseignée.')
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final player in fallbackPlayers)
                    _PlayerSummaryTile(
                      name: player.name,
                      goals: player.goals,
                      isHdm: false,
                    ),
                ],
              ),
            if (substitutes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Remplaçants',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final player in substitutes)
                    _PlayerSummaryTile(
                      name: player.name,
                      goals: player.goals,
                      isHdm: player.isManOfTheMatch,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rendu MPG d'une composition publiée (photos, couronne, ballons) pour un
/// match terminé — identique à l'affichage d'avant-match.
class _MpgCompletedCard extends StatelessWidget {
  const _MpgCompletedCard({required this.composition});

  final MatchComposition composition;

  @override
  Widget build(BuildContext context) {
    final bench = composition.entriesFor(MatchCompositionZone.bench);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Composition et résumé',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Les buts ⚽ et l’homme du match 👑 sont affichés directement '
              'sur les joueurs.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: CompositionPitch(
                  entries: composition.entriesFor(MatchCompositionZone.field),
                ),
              ),
            ),
            if (bench.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Remplaçants (${bench.length})',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final entry in bench) CompositionPlayerTile(entry: entry),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompletedPitch extends StatelessWidget {
  const _CompletedPitch({required this.players});

  final List<MatchStartingPlayer> players;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: AspectRatio(
        aspectRatio: .68,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF174936),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFF6DAD8B), width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: CustomPaint(painter: _CompletedPitchPainter()),
                    ),
                    for (var index = 0; index < players.length; index += 1)
                      _positionedPlayer(
                        players[index],
                        constraints.biggest,
                        index,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _positionedPlayer(
    MatchStartingPlayer player,
    Size size,
    int index,
  ) {
    const width = 86.0;
    const height = 74.0;
    final fallbackColumn = index % 4;
    final fallbackRow = index ~/ 4;
    final x = (player.x ?? (.17 + fallbackColumn * .22)).clamp(.1, .9);
    final y = (player.y ?? (.18 + fallbackRow * .25)).clamp(.08, .92);
    final left =
        (x * size.width - width / 2).clamp(0.0, size.width - width).toDouble();
    final top = (y * size.height - height / 2)
        .clamp(0.0, size.height - height)
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: _PlayerSummaryTile(
        name: player.name,
        goals: player.goals,
        isHdm: player.isManOfTheMatch,
        compact: true,
      ),
    );
  }
}

class _PlayerSummaryTile extends StatelessWidget {
  const _PlayerSummaryTile({
    required this.name,
    required this.goals,
    required this.isHdm,
    this.compact = false,
  });

  final String name;
  final int goals;
  final bool isHdm;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final goalLabel = goals == 0
        ? null
        : goals == 1
            ? '1 but'
            : '$goals buts';
    return Container(
      constraints: compact ? null : const BoxConstraints(minWidth: 120),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 10,
        vertical: compact ? 5 : 8,
      ),
      decoration: BoxDecoration(
        color: compact ? const Color(0xE625164F) : AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHdm ? const Color(0xFFFFC857) : Colors.white38,
          width: isHdm ? 1.8 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: compact ? 15 : 19,
                backgroundColor: const Color(0xFFD9DCE3),
                child: Icon(
                  Icons.person,
                  size: compact ? 20 : 25,
                  color: const Color(0xFF596170),
                ),
              ),
              if (isHdm)
                const Positioned(
                  right: -7,
                  top: -7,
                  child: Icon(
                    Icons.emoji_events,
                    size: 17,
                    color: Color(0xFFFFC857),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: compact ? Colors.white : null,
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (goalLabel != null)
            Text(
              goalLabel,
              style: TextStyle(
                color:
                    compact ? const Color(0xFFFFE082) : AppTheme.textSecondary,
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _CompletedPitchPainter extends CustomPainter {
  const _CompletedPitchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xAAFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final inset = size.shortestSide * .045;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    canvas
      ..drawRect(rect, paint)
      ..drawLine(
        Offset(rect.left, rect.center.dy),
        Offset(rect.right, rect.center.dy),
        paint,
      )
      ..drawCircle(rect.center, size.width * .13, paint)
      ..drawRect(
        Rect.fromCenter(
          center: Offset(rect.center.dx, rect.top + rect.height * .08),
          width: rect.width * .58,
          height: rect.height * .16,
        ),
        paint,
      )
      ..drawRect(
        Rect.fromCenter(
          center: Offset(rect.center.dx, rect.bottom - rect.height * .08),
          width: rect.width * .58,
          height: rect.height * .16,
        ),
        paint,
      );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PredictionsTable extends StatelessWidget {
  const _PredictionsTable({
    required this.predictions,
    required this.actualGrinta,
    required this.actualOpponent,
    required this.isHome,
  });

  final List<MatchPredictionResult> predictions;
  final int actualGrinta;
  final int actualOpponent;
  final bool isHome;

  int _result(int home, int away) => home == away ? 0 : (home > away ? 1 : -1);

  Color? _colorFor(MatchPredictionResult prediction) {
    if (prediction.points <= 0) return null;
    final exact = prediction.scoreGrinta == actualGrinta &&
        prediction.scoreOpponent == actualOpponent;
    if (exact) return const Color(0xFF9B6CFF);
    final correctWinner =
        _result(prediction.scoreGrinta, prediction.scoreOpponent) ==
            _result(actualGrinta, actualOpponent);
    if (!correctWinner) return null;
    return const Color(0xFF39E784);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pronostics', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final prediction in predictions)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: _colorFor(prediction) == null
                      ? null
                      : Border.all(color: _colorFor(prediction)!, width: 1.7),
                  color: _colorFor(prediction)?.withValues(alpha: .08),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: NameWithBadges(
                        profileId: prediction.profileId,
                        name: prediction.name,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        isHome
                            ? '${prediction.scoreGrinta}–${prediction.scoreOpponent}'
                            : '${prediction.scoreOpponent}–${prediction.scoreGrinta}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(
                      width: 30,
                      child: prediction.usedX2
                          ? const Align(
                              alignment: Alignment.centerRight,
                              child: _X2Badge(),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        prediction.points.round().toString(),
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pastille « ×2 » indiquant qu'un joueur a utilisé son bonus double sur ce
/// pronostic (ses points sont doublés).
class _X2Badge extends StatelessWidget {
  const _X2Badge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accent.withValues(alpha: .55)),
      ),
      child: const Text(
        '×2',
        style: TextStyle(
          color: AppTheme.accent,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}
