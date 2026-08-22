import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:flutter/material.dart';

/// Taille logique de l'image partagée. Capturée à trois fois cette taille,
/// elle sort en 1080 × 1350, le format portrait des messageries.
const double kSeasonWrappedShareWidth = 360;
const double kSeasonWrappedShareHeight = 450;
const double kSeasonWrappedSharePixelRatio = 3;

/// Une feuille du bilan, telle qu'elle part en photo.
///
/// Elle est dessinée hors écran puis capturée : elle ne dépend donc d'aucune
/// contrainte de l'écran qui l'affiche, et rend le même visuel sur tous les
/// téléphones.
class SeasonWrappedShareSheet extends StatelessWidget {
  const SeasonWrappedShareSheet({
    super.key,
    required this.sheet,
    required this.seasonName,
    required this.playerName,
  });

  final SeasonWrappedSheet sheet;
  final String seasonName;
  final String? playerName;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kSeasonWrappedShareWidth,
      height: kSeasonWrappedShareHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.surfaceHero, AppTheme.background],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AS GRINTA',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Saison $seasonName',
                style: const TextStyle(
                  color: AppTheme.textFaint,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                sheet.title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              // Les critères occupent toute la hauteur restante, qu'ils
              // soient deux ou quatre : la feuille garde la même allure.
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final stat in sheet.stats) _ShareStatLine(stat: stat),
                  ],
                ),
              ),
              if (playerName != null && playerName!.isNotEmpty)
                Text(
                  playerName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareStatLine extends StatelessWidget {
  const _ShareStatLine({required this.stat});

  final SeasonWrappedStat stat;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stat.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textFaint,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  stat.value,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (stat.isRanked) ...[
          const SizedBox(width: 10),
          SeasonWrappedRankChip(rank: stat.rank!, compact: true),
        ],
      ],
    );
  }
}

/// Le rang dans l'équipe, seul : « 1er », « 3e ».
class SeasonWrappedRankChip extends StatelessWidget {
  const SeasonWrappedRankChip({
    super.key,
    required this.rank,
    this.compact = false,
  });

  final int rank;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isPodium = rank <= 3;
    final color = isPodium ? AppTheme.reward : AppTheme.primaryBright;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .5)),
      ),
      child: Text(
        seasonWrappedOrdinal(rank),
        style: TextStyle(
          color: color,
          fontSize: compact ? 13 : 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// « 1er », puis « 2e », « 3e »…
String seasonWrappedOrdinal(int rank) => rank == 1 ? '1er' : '${rank}e';
