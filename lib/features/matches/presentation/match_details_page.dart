import 'package:as_grinta/core/design_system/components/grinta_button.dart';
import 'package:as_grinta/core/design_system/components/grinta_card.dart';
import 'package:as_grinta/core/design_system/components/grinta_loading.dart';
import 'package:as_grinta/core/design_system/components/grinta_status_message.dart';
import 'package:as_grinta/core/design_system/components/grinta_surface.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_colors.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_iconography.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_radii.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_spacing.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_typography.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Détails du match')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(matchDetailsProvider(matchId));
          await ref.read(matchDetailsProvider(matchId).future);
        },
        child: detailsAsync.when(
          loading: () => const _ScrollableState(
            child: GrintaLoadingIndicator(label: 'Chargement du match'),
          ),
          error: (error, _) => _ScrollableState(
            child: GrintaStatusMessage(
              title: 'Impossible de charger le match',
              message: humanizeError(error),
              tone: GrintaStatusTone.danger,
            ),
          ),
          data: (details) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: GrintaSpacing.contentMaxWidth,
              ),
              child: ListView(
                padding: GrintaSpacing.screenInsets,
                children: [
                  _MatchHero(details: details),
                  if (!details.isValidated) ...[
                    const SizedBox(height: GrintaSpacing.sectionGap),
                    _UpcomingInformation(details: details),
                  ] else ...[
                    if (details.playerStats.isNotEmpty) ...[
                      const SizedBox(height: GrintaSpacing.sectionGap),
                      _MatchSummary(details: details),
                    ],
                    if (details.predictions.isNotEmpty) ...[
                      const SizedBox(height: GrintaSpacing.sectionGap),
                      _PredictionsTable(
                        predictions: details.predictions,
                        actualGrinta: details.scoreGrinta ?? 0,
                        actualOpponent: details.scoreOpponent ?? 0,
                        isHome: details.location == 'domicile',
                      ),
                    ],
                  ],
                  if (isAdmin) ...[
                    const SizedBox(height: GrintaSpacing.sectionGap),
                    _AdminActions(
                      details: details,
                      onFinalize: () =>
                          context.push('/matches/$matchId/finalize'),
                      onReport: () => _report(context, ref, details),
                    ),
                  ],
                  if (!details.isValidated) ...[
                    const SizedBox(height: GrintaSpacing.majorSectionGap),
                    _HeadToHead(details: details),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _report(
    BuildContext context,
    WidgetRef ref,
    MatchDetailsData details,
  ) async {
    final date = await showDatePicker(
      context: context,
      initialDate: details.kickoffAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(details.kickoffAt),
    );
    if (time == null || !context.mounted) return;

    await ref.read(matchDetailsRepositoryProvider).reportMatch(
          matchId: details.matchId,
          kickoffAt: DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          ),
        );
    ref.invalidate(matchDetailsProvider(matchId));
  }
}

class _ScrollableState extends StatelessWidget {
  const _ScrollableState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: GrintaSpacing.screenInsets,
      children: [
        const SizedBox(height: GrintaSpacing.space20),
        child,
      ],
    );
  }
}

class _MatchHero extends StatelessWidget {
  const _MatchHero({required this.details});

  final MatchDetailsData details;

  @override
  Widget build(BuildContext context) {
    final isHome = details.location == 'domicile';
    final grintaScore = details.scoreGrinta;
    final opponentScore = details.scoreOpponent;
    final homeName = isHome ? 'AS Grinta' : details.opponentName;
    final awayName = isHome ? details.opponentName : 'AS Grinta';
    final homeScore = isHome ? grintaScore : opponentScore;
    final awayScore = isHome ? opponentScore : grintaScore;

    return GrintaSurface(
      level: GrintaSurfaceLevel.emphasis,
      padding: const EdgeInsets.all(GrintaSpacing.space6),
      borderRadius: GrintaRadii.prominentCardRadius,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatusBadge(isValidated: details.isValidated),
              Text(
                isHome ? 'DOMICILE' : 'EXTÉRIEUR',
                style: GrintaTypography.eyebrow,
              ),
            ],
          ),
          const SizedBox(height: GrintaSpacing.space8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _TeamIdentity(
                  name: homeName,
                  isGrinta: homeName == 'AS Grinta',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: GrintaSpacing.space3,
                ),
                child: details.isValidated
                    ? _Score(
                        home: homeScore ?? 0,
                        away: awayScore ?? 0,
                      )
                    : Text(
                        'VS',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: GrintaColors.contentTertiary,
                                ),
                      ),
              ),
              Expanded(
                child: _TeamIdentity(
                  name: awayName,
                  isGrinta: awayName == 'AS Grinta',
                ),
              ),
            ],
          ),
          const SizedBox(height: GrintaSpacing.space8),
          const Divider(),
          const SizedBox(height: GrintaSpacing.space4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.schedule_outlined,
                size: GrintaIconography.inline,
                color: GrintaColors.contentTertiary,
              ),
              const SizedBox(width: GrintaSpacing.iconGap),
              Text(
                AppFormats.dateTime(details.kickoffAt),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isValidated});

  final bool isValidated;

  @override
  Widget build(BuildContext context) {
    final color =
        isValidated ? GrintaColors.statusSuccess : GrintaColors.statusWarning;
    final background = isValidated
        ? GrintaColors.statusSuccessSoft
        : GrintaColors.statusWarningSoft;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GrintaSpacing.space3,
        vertical: GrintaSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: GrintaRadii.badgeRadius,
      ),
      child: Text(
        isValidated ? 'TERMINÉ' : 'À VENIR',
        style: GrintaTypography.eyebrow.copyWith(color: color),
      ),
    );
  }
}

class _TeamIdentity extends StatelessWidget {
  const _TeamIdentity({required this.name, required this.isGrinta});

  final String name;
  final bool isGrinta;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isGrinta
                ? GrintaColors.actionPrimary
                : GrintaColors.surfaceElevated,
            shape: BoxShape.circle,
            border: Border.all(color: GrintaColors.borderDefault),
          ),
          child: Icon(
            isGrinta ? Icons.shield_outlined : Icons.sports_soccer_outlined,
            color: isGrinta
                ? GrintaColors.actionPrimaryContent
                : GrintaColors.contentSecondary,
          ),
        ),
        const SizedBox(height: GrintaSpacing.space3),
        Text(
          name,
          style: Theme.of(context).textTheme.titleSmall,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.home, required this.away});

  final int home;
  final int away;

  @override
  Widget build(BuildContext context) {
    return Text('$home–$away', style: GrintaTypography.score);
  }
}

class _UpcomingInformation extends StatelessWidget {
  const _UpcomingInformation({required this.details});

  final MatchDetailsData details;

  @override
  Widget build(BuildContext context) {
    return GrintaCard(
      title: 'Pronostics ouverts',
      subtitle:
          '${details.predictionParticipantCount} participant${details.predictionParticipantCount > 1 ? 's' : ''}',
      leading: const Icon(Icons.bolt_outlined),
      child: Row(
        children: [
          Expanded(
            child: _InfoTile(
              label: 'Victoire',
              value: AppFormats.odds(details.oddsWin),
            ),
          ),
          const SizedBox(width: GrintaSpacing.controlGap),
          Expanded(
            child: _InfoTile(
              label: 'Nul',
              value: AppFormats.odds(details.oddsDraw),
            ),
          ),
          const SizedBox(width: GrintaSpacing.controlGap),
          Expanded(
            child: _InfoTile(
              label: 'Défaite',
              value: AppFormats.odds(details.oddsLoss),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchSummary extends StatelessWidget {
  const _MatchSummary({required this.details});

  final MatchDetailsData details;

  @override
  Widget build(BuildContext context) {
    final scorers =
        details.playerStats.where((line) => line.goals > 0).toList();
    final cleanSheets =
        details.playerStats.where((line) => line.cleanSheet).toList();

    return GrintaCard(
      title: 'Résumé du match',
      subtitle: 'Performances individuelles',
      leading: const Icon(Icons.insights_outlined),
      child: Column(
        children: [
          if (scorers.isNotEmpty)
            _SummarySection(
              icon: Icons.sports_soccer_outlined,
              label: 'Buteurs',
              children: scorers
                  .map(
                    (line) => _SummaryRow(
                      name: line.name,
                      value: '${line.goals} but${line.goals > 1 ? 's' : ''}',
                    ),
                  )
                  .toList(),
            ),
          if (scorers.isNotEmpty && cleanSheets.isNotEmpty)
            const SizedBox(height: GrintaSpacing.sectionGap),
          if (cleanSheets.isNotEmpty)
            _SummarySection(
              icon: Icons.shield_outlined,
              label: 'Clean sheet',
              children: cleanSheets
                  .map(
                    (line) => _SummaryRow(name: line.name, value: '1'),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.icon,
    required this.label,
    required this.children,
  });

  final IconData icon;
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: GrintaIconography.inline),
            const SizedBox(width: GrintaSpacing.iconGap),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: GrintaSpacing.space3),
        ...children,
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.name, required this.value});

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GrintaSpacing.space2),
      child: Row(
        children: [
          Expanded(child: Text(name)),
          Text(value, style: GrintaTypography.statistic),
        ],
      ),
    );
  }
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

  Color? _colorFor(MatchPredictionResult prediction) {
    if (prediction.points <= 0) return null;
    if (prediction.scoreGrinta == actualGrinta &&
        prediction.scoreOpponent == actualOpponent) {
      return GrintaColors.statusSuccess;
    }
    final predictedDifference =
        prediction.scoreGrinta - prediction.scoreOpponent;
    final actualDifference = actualGrinta - actualOpponent;
    if (predictedDifference == actualDifference) {
      return GrintaColors.statusInfo;
    }
    if (prediction.scoreGrinta == actualGrinta ||
        prediction.scoreOpponent == actualOpponent) {
      return GrintaColors.statusWarning;
    }
    return GrintaColors.accentPrimary;
  }

  @override
  Widget build(BuildContext context) {
    return GrintaCard(
      title: 'Pronostics',
      subtitle:
          '${predictions.length} participation${predictions.length > 1 ? 's' : ''}',
      leading: const Icon(Icons.bolt_outlined),
      child: Column(
        children: [
          const _PredictionHeader(),
          const SizedBox(height: GrintaSpacing.space2),
          ...predictions.map((prediction) {
            final color = _colorFor(prediction);
            final displayedScore = isHome
                ? '${prediction.scoreGrinta}–${prediction.scoreOpponent}'
                : '${prediction.scoreOpponent}–${prediction.scoreGrinta}';

            return _PredictionRow(
              name: prediction.name,
              score: displayedScore,
              points: prediction.points.round(),
              color: color,
            );
          }),
        ],
      ),
    );
  }
}

class _PredictionHeader extends StatelessWidget {
  const _PredictionHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GrintaSpacing.space3),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('JOUEUR', style: style)),
          Expanded(
            child: Text('PRONO', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            child: Text('POINTS', style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _PredictionRow extends StatelessWidget {
  const _PredictionRow({
    required this.name,
    required this.score,
    required this.points,
    required this.color,
  });

  final String name;
  final String score;
  final int points;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: GrintaSpacing.space2),
      padding: const EdgeInsets.symmetric(
        horizontal: GrintaSpacing.space3,
        vertical: GrintaSpacing.space3,
      ),
      decoration: BoxDecoration(
        color: color?.withValues(alpha: .08),
        borderRadius: GrintaRadii.controlRadius,
        border: Border.all(
          color: color ?? GrintaColors.borderSubtle,
          width: color == null ? 1 : 1.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: GrintaColors.contentPrimary,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              score,
              textAlign: TextAlign.center,
              style: GrintaTypography.statistic,
            ),
          ),
          Expanded(
            child: Text(
              points.toString(),
              textAlign: TextAlign.end,
              style: GrintaTypography.statistic.copyWith(
                color: color ?? GrintaColors.contentTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminActions extends StatelessWidget {
  const _AdminActions({
    required this.details,
    required this.onFinalize,
    required this.onReport,
  });

  final MatchDetailsData details;
  final VoidCallback onFinalize;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final isUpcoming = details.status == 'a_venir';

    return GrintaCard(
      title: 'Administration',
      subtitle: isUpcoming
          ? 'Gérer la rencontre avant validation'
          : 'Corriger les statistiques enregistrées',
      leading: const Icon(Icons.admin_panel_settings_outlined),
      child: Column(
        children: [
          GrintaButton(
            label: isUpcoming
                ? 'Saisir les statistiques'
                : 'Modifier les statistiques',
            icon: isUpcoming
                ? Icons.fact_check_outlined
                : Icons.history_edu_outlined,
            onPressed: onFinalize,
            expand: true,
          ),
          if (isUpcoming) ...[
            const SizedBox(height: GrintaSpacing.controlGap),
            GrintaButton(
              label: 'Reporter le match',
              icon: Icons.event_repeat_outlined,
              variant: GrintaButtonVariant.secondary,
              onPressed: onReport,
              expand: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _HeadToHead extends StatelessWidget {
  const _HeadToHead({required this.details});

  final MatchDetailsData details;

  @override
  Widget build(BuildContext context) {
    if (details.headToHead.isEmpty) {
      return const GrintaStatusMessage(
        message: 'Aucune confrontation précédente.',
        tone: GrintaStatusTone.info,
      );
    }

    return GrintaCard(
      title: 'Confrontations récentes',
      subtitle: 'Les 5 derniers matchs',
      leading: const Icon(Icons.history_outlined),
      child: Column(
        children: details.headToHead
            .map(
              (match) => Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: GrintaSpacing.space3,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppFormats.date(match.date),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      '${match.scoreGrinta ?? '?'}–${match.scoreOpponent ?? '?'}',
                      style: GrintaTypography.statistic,
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GrintaSurface(
      level: GrintaSurfaceLevel.elevated,
      padding: const EdgeInsets.symmetric(
        horizontal: GrintaSpacing.space3,
        vertical: GrintaSpacing.space4,
      ),
      borderRadius: GrintaRadii.controlRadius,
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: GrintaSpacing.space2),
          Text(
            value,
            style: GrintaTypography.statistic,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
