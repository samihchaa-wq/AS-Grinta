import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_ink_pitch.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_motion.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_paper.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_share_sheet.dart';
import 'package:flutter/material.dart';

/// Les écrans du bilan, dans l'ordre de lecture.
///
/// L'ordre n'est pas neutre : on ouvre sur la feuille vierge, on avance du
/// chiffre le plus modeste au plus flatteur, et on referme sur la feuille
/// complète, prête à partager.
List<Widget> buildWrappedSlides({
  required SeasonWrapped wrapped,
  required String? playerName,
  required VoidCallback onShare,
  required VoidCallback onShareByTheme,
}) {
  return [
    _OpeningSlide(wrapped: wrapped, playerName: playerName),
    _FigureSlide(
      seed: 1,
      label: 'Matchs joués',
      value: wrapped.matchesPlayed,
      rank: wrapped.matchesPlayedRank,
      caption: wrapped.matchesPlayed <= 1
          ? 'Une feuille de match à ton nom.'
          : 'Autant de fois où tu as répondu présent.',
    ),
    _ResponsivenessSlide(wrapped: wrapped),
    _PositionSlide(wrapped: wrapped),
    _VersatilitySlide(wrapped: wrapped),
    _ContributionSlide(wrapped: wrapped),
    _ResultsSlide(wrapped: wrapped),
    _ClosingSlide(
      wrapped: wrapped,
      playerName: playerName,
      onShare: onShare,
      onShareByTheme: onShareByTheme,
    ),
  ];
}

/// Ossature commune : l'en-tête de la feuille, puis le contenu centré.
class _SlideFrame extends StatelessWidget {
  const _SlideFrame({required this.seed, required this.child});

  final int seed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return WrappedPaperBackground(
      seed: seed,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 64, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AS GRINTA · FEUILLE DE SAISON',
                style: WrappedPaper.label(size: 10),
              ),
              const SizedBox(height: 6),
              Container(
                  height: 1.4, color: WrappedPaper.ink.withValues(alpha: .25)),
              Expanded(
                child: Align(
                  // Un peu au-dessus du centre optique : une feuille se lit
                  // du haut, pas du milieu.
                  alignment: const Alignment(0, -.2),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [child],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Intitulé de rubrique, souligné comme une case de formulaire.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return WrappedReveal(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text.toUpperCase(), style: WrappedPaper.label()),
          const SizedBox(height: 4),
          SizedBox(
            width: 54,
            child: Container(
              height: 2,
              color: WrappedPaper.stamp.withValues(alpha: .55),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpeningSlide extends StatelessWidget {
  const _OpeningSlide({required this.wrapped, required this.playerName});

  final SeasonWrapped wrapped;
  final String? playerName;

  @override
  Widget build(BuildContext context) {
    return _SlideFrame(
      seed: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          WrappedReveal(
            child: Text('Saison', style: WrappedPaper.label(size: 13)),
          ),
          const SizedBox(height: 6),
          WrappedReveal(
            delay: const Duration(milliseconds: 120),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                wrapped.seasonName,
                style: WrappedPaper.figure(size: 76),
              ),
            ),
          ),
          const SizedBox(height: 22),
          WrappedTypewriter(
            delay: const Duration(milliseconds: 620),
            text: playerName == null || playerName!.isEmpty
                ? 'Ta saison, en huit cases.'
                : '$playerName — ta saison, en huit cases.',
            style: WrappedPaper.body(size: 15),
          ),
          const SizedBox(height: 26),
          WrappedReveal(
            delay: const Duration(milliseconds: 1500),
            child: WrappedStamp(text: 'Saison close', angle: -.06),
          ),
          const SizedBox(height: 26),
          WrappedReveal(
            delay: const Duration(milliseconds: 1800),
            child: Text(
              'Les rangs te situent parmi les ${wrapped.rosterSize} joueurs '
              'ayant disputé au moins un match.',
              style: WrappedPaper.body(size: 12, color: WrappedPaper.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

/// Écran d'un seul chiffre : le format le plus efficace du bilan.
class _FigureSlide extends StatelessWidget {
  const _FigureSlide({
    required this.seed,
    required this.label,
    required this.value,
    required this.rank,
    required this.caption,
    this.suffix = '',
    this.decimals = 0,
  });

  final int seed;
  final String label;
  final num value;
  final int? rank;
  final String caption;
  final String suffix;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    return _SlideFrame(
      seed: seed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _FieldLabel(label),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: WrappedCountUp(
              value: value,
              suffix: suffix,
              decimals: decimals,
              style: WrappedPaper.figure(size: 150),
            ),
          ),
          const SizedBox(height: 18),
          WrappedReveal(
            delay: const Duration(milliseconds: 1500),
            child: Text(caption, style: WrappedPaper.body(size: 14)),
          ),
          if (rank != null) ...[
            const SizedBox(height: 26),
            WrappedReveal(
              delay: const Duration(milliseconds: 1850),
              child:
                  WrappedStamp(text: '${seasonWrappedOrdinal(rank!)} du club'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResponsivenessSlide extends StatelessWidget {
  const _ResponsivenessSlide({required this.wrapped});

  final SeasonWrapped wrapped;

  @override
  Widget build(BuildContext context) {
    final hours = wrapped.avgResponseHours;

    if (hours == null) {
      return _SlideFrame(
        seed: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _FieldLabel('Réactivité'),
            const SizedBox(height: 14),
            WrappedReveal(
              delay: const Duration(milliseconds: 200),
              child: Text(
                'Aucune réponse\nenregistrée',
                style: WrappedPaper.title(size: 34),
              ),
            ),
            const SizedBox(height: 18),
            WrappedReveal(
              delay: const Duration(milliseconds: 700),
              child: Text(
                'Les disponibilités ouvrent six jours avant chaque match. '
                'La saison prochaine, tu y es.',
                style: WrappedPaper.body(size: 14),
              ),
            ),
          ],
        ),
      );
    }

    // Sous deux jours, l'heure parle mieux que la fraction de journée.
    final showDays = hours >= 48;
    final value = showDays ? hours / 24 : hours;

    return _FigureSlide(
      seed: 2,
      label: 'Tu réponds présent en',
      value: value,
      decimals: value >= 10 ? 0 : 1,
      suffix: showDays ? ' jours' : ' h',
      rank: wrapped.avgResponseRank,
      caption: wrapped.avgResponseRank == null
          ? 'Délai moyen entre l’ouverture des disponibilités et ta réponse.'
          : 'En moyenne, après l’ouverture des disponibilités.',
    );
  }
}

class _PositionSlide extends StatelessWidget {
  const _PositionSlide({required this.wrapped});

  final SeasonWrapped wrapped;

  @override
  Widget build(BuildContext context) {
    final spots = wrappedPositionSpots(wrapped.topPosition);
    final reduced = wrappedReducedMotion(context);

    return _SlideFrame(
      seed: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _FieldLabel('Ton poste'),
          const SizedBox(height: 14),
          WrappedReveal(
            delay: const Duration(milliseconds: 160),
            child: Text(
              wrapped.topPosition ?? 'Jamais aligné au coup d’envoi',
              style: WrappedPaper.title(size: 36),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: SizedBox(
              width: 216,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: reduced ? 1 : 0, end: 1),
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 1500),
                curve: Curves.easeOutCubic,
                builder: (context, progress, _) =>
                    WrappedInkPitch(spots: spots, progress: progress),
              ),
            ),
          ),
          const SizedBox(height: 14),
          WrappedReveal(
            delay: const Duration(milliseconds: 1300),
            child: Text(
              spots.isEmpty
                  ? 'Tu n’apparais dans aucune composition de départ.'
                  : 'Le poste où tu as été aligné le plus souvent.',
              style: WrappedPaper.body(size: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersatilitySlide extends StatelessWidget {
  const _VersatilitySlide({required this.wrapped});

  final SeasonWrapped wrapped;

  @override
  Widget build(BuildContext context) {
    return _FigureSlide(
      seed: 4,
      label: 'Polyvalence',
      value: wrapped.versatility,
      suffix: wrapped.versatility <= 1 ? ' poste' : ' postes',
      rank: wrapped.versatilityRank,
      caption: switch (wrapped.versatility) {
        0 => 'Aucune composition de départ cette saison.',
        1 => 'Un poste, toujours le même. Le coach sait où te trouver.',
        2 => 'Deux postes différents occupés cette saison.',
        _ => 'Autant de postes différents occupés. Couteau suisse.',
      },
    );
  }
}

class _ContributionSlide extends StatelessWidget {
  const _ContributionSlide({required this.wrapped});

  final SeasonWrapped wrapped;

  @override
  Widget build(BuildContext context) {
    return _SlideFrame(
      seed: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _FieldLabel('Ton apport'),
          const SizedBox(height: 20),
          _InlineFigure(
            label: 'Buts',
            value: wrapped.goals,
            rank: wrapped.goalsRank,
            delay: const Duration(milliseconds: 200),
          ),
          const SizedBox(height: 26),
          _InlineFigure(
            label: 'Homme du match',
            value: wrapped.motm,
            rank: wrapped.motmRank,
            delay: const Duration(milliseconds: 900),
          ),
          const SizedBox(height: 24),
          WrappedReveal(
            delay: const Duration(milliseconds: 1700),
            child: Text(
              wrapped.motm == 0
                  ? 'Le vote Homme du match reste anonyme, comme toujours.'
                  : 'Élu par tes coéquipiers. Les bulletins, eux, restent secrets.',
              style: WrappedPaper.body(size: 13, color: WrappedPaper.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineFigure extends StatelessWidget {
  const _InlineFigure({
    required this.label,
    required this.value,
    required this.rank,
    required this.delay,
    this.suffix = '',
    this.decimals = 0,
  });

  final String label;
  final num value;
  final int? rank;
  final Duration delay;
  final String suffix;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    return WrappedReveal(
      delay: delay,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: WrappedPaper.label(size: 11)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: WrappedCountUp(
                    value: value,
                    suffix: suffix,
                    decimals: decimals,
                    delay: delay + const Duration(milliseconds: 160),
                    style: WrappedPaper.figure(size: 68),
                  ),
                ),
              ],
            ),
          ),
          if (rank != null)
            WrappedStamp(text: seasonWrappedOrdinal(rank!), size: 13),
        ],
      ),
    );
  }
}

class _ResultsSlide extends StatelessWidget {
  const _ResultsSlide({required this.wrapped});

  final SeasonWrapped wrapped;

  @override
  Widget build(BuildContext context) {
    final winPct = wrapped.winPct;

    return _SlideFrame(
      seed: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _FieldLabel('L’équipe quand tu étais là'),
          const SizedBox(height: 20),
          WrappedReveal(
            delay: const Duration(milliseconds: 200),
            child: Row(
              children: [
                _ResultBlock(letter: 'V', value: wrapped.wins),
                _ResultBlock(letter: 'N', value: wrapped.draws),
                _ResultBlock(letter: 'D', value: wrapped.losses),
              ],
            ),
          ),
          const SizedBox(height: 28),
          if (winPct != null)
            _InlineFigure(
              label: 'Pourcentage de victoire',
              value: winPct,
              suffix: ' %',
              decimals: winPct >= 10 ? 0 : 1,
              rank: wrapped.winPctRank,
              delay: const Duration(milliseconds: 900),
            ),
          const SizedBox(height: 24),
          _InlineFigure(
            label: 'Matchs sans encaisser',
            value: wrapped.cleanMatches,
            rank: wrapped.cleanMatchesRank,
            delay: const Duration(milliseconds: 1500),
          ),
        ],
      ),
    );
  }
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({required this.letter, required this.value});

  final String letter;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(letter, style: WrappedPaper.label(size: 12)),
          const SizedBox(height: 2),
          WrappedCountUp(
            value: value,
            delay: const Duration(milliseconds: 320),
            style: WrappedPaper.figure(size: 56),
          ),
        ],
      ),
    );
  }
}

class _ClosingSlide extends StatelessWidget {
  const _ClosingSlide({
    required this.wrapped,
    required this.playerName,
    required this.onShare,
    required this.onShareByTheme,
  });

  final SeasonWrapped wrapped;
  final String? playerName;
  final VoidCallback onShare;
  final VoidCallback onShareByTheme;

  @override
  Widget build(BuildContext context) {
    return _SlideFrame(
      seed: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _FieldLabel('Ta feuille'),
          const SizedBox(height: 14),
          for (var i = 0; i < wrapped.stats.length; i += 1)
            WrappedReveal(
              delay: Duration(milliseconds: 120 + i * 90),
              child: _RecapLine(stat: wrapped.stats[i]),
            ),
          const SizedBox(height: 18),
          WrappedReveal(
            delay: const Duration(milliseconds: 1100),
            child: Row(
              children: [
                WrappedStamp(text: 'Vu et approuvé', size: 12),
                const Spacer(),
                if (playerName != null && playerName!.isNotEmpty)
                  Text(playerName!, style: WrappedPaper.body(size: 13)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          WrappedReveal(
            delay: const Duration(milliseconds: 1300),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: onShare,
                  style: FilledButton.styleFrom(
                    backgroundColor: WrappedPaper.ink,
                    foregroundColor: WrappedPaper.paper,
                    shape: const RoundedRectangleBorder(),
                  ),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Partager ma feuille'),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: onShareByTheme,
                  style: TextButton.styleFrom(
                    foregroundColor: WrappedPaper.inkSoft,
                  ),
                  child: const Text('Partager par thème'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecapLine extends StatelessWidget {
  const _RecapLine({required this.stat});

  final SeasonWrappedStat stat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            flex: 7,
            child: Text(
              stat.shortLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WrappedPaper.body(size: 11),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: WrappedPaper.ink.withValues(alpha: .22),
                    ),
                  ),
                ),
                child: const SizedBox(height: 10, width: double.infinity),
              ),
            ),
          ),
          Expanded(
            flex: 10,
            child: Text(
              stat.value,
              maxLines: 1,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: WrappedPaper.body(size: 12).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Colonne de rang de largeur fixe : les valeurs restent alignées
          // qu'un critère soit classé ou non.
          SizedBox(
            width: 34,
            child: Text(
              stat.isRanked ? seasonWrappedOrdinal(stat.rank!) : '',
              textAlign: TextAlign.right,
              style: WrappedPaper.label(size: 11, color: WrappedPaper.stamp),
            ),
          ),
        ],
      ),
    );
  }
}
