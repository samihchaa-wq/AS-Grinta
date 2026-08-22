import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_ink_pitch.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_motion.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_theme.dart';
import 'package:flutter/material.dart';

/// Les écrans du bilan, dans l'ordre de lecture.
///
/// L'ordre n'est pas neutre : on ouvre sur la saison, on avance du chiffre le
/// plus modeste au plus flatteur, et on referme sur le récapitulatif, prêt à
/// partager.
List<Widget> buildWrappedSlides({
  required SeasonWrapped wrapped,
  required String? playerName,
  required VoidCallback onShare,
  required VoidCallback onShareByTheme,
}) {
  final skins = WrappedSkin.sequence;

  return [
    _OpeningSlide(skin: skins[0], wrapped: wrapped, playerName: playerName),
    _FigureSlide(
      skin: skins[1],
      label: 'Matchs joués',
      value: wrapped.matchesPlayed,
      rank: wrapped.matchesPlayedRank,
      caption: wrapped.matchesPlayed <= 1
          ? 'Une feuille de match à ton nom.'
          : 'Autant de fois où tu as répondu présent.',
    ),
    _ResponsivenessSlide(skin: skins[2], wrapped: wrapped),
    _PositionSlide(skin: skins[3], wrapped: wrapped),
    _ContributionSlide(skin: skins[4], wrapped: wrapped),
    _ResultsSlide(skin: skins[5], wrapped: wrapped),
    _ClosingSlide(
      skin: skins[6],
      wrapped: wrapped,
      playerName: playerName,
      onShare: onShare,
      onShareByTheme: onShareByTheme,
    ),
  ];
}

/// Ossature commune : le contenu occupe toute la hauteur, du haut au bas.
class _SlideFrame extends StatelessWidget {
  const _SlideFrame({
    required this.skin,
    required this.top,
    required this.middle,
    this.bottom,
  });

  final WrappedSkin skin;
  final Widget top;
  final Widget middle;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return WrappedBackdrop(
      skin: skin,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 74, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              top,
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [middle],
                    ),
                  ),
                ),
              ),
              if (bottom != null) bottom!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Intitulé de rubrique : capitales espacées, barre de couleur en dessous.
class _SlideLabel extends StatelessWidget {
  const _SlideLabel({required this.text, required this.skin});

  final String text;
  final WrappedSkin skin;

  @override
  Widget build(BuildContext context) {
    return WrappedReveal(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 5, width: 62, color: skin.figure),
          const SizedBox(height: 14),
          Text(
            text.toUpperCase(),
            maxLines: 2,
            style: WrappedType.heading(skin.text),
          ),
        ],
      ),
    );
  }
}

/// Le chiffre, aussi grand que la largeur le permet.
class _GiantFigure extends StatelessWidget {
  const _GiantFigure({
    required this.value,
    required this.skin,
    this.suffix = '',
    this.decimals = 0,
  });

  final num value;
  final WrappedSkin skin;
  final String suffix;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: WrappedCountUp(
        value: value,
        suffix: suffix,
        decimals: decimals,
        style: WrappedType.figure(skin.figure),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({
    required this.text,
    required this.skin,
    required this.rank,
    this.delay = const Duration(milliseconds: 1400),
  });

  final String text;
  final WrappedSkin skin;
  final int? rank;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return WrappedReveal(
      delay: delay,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              text,
              style: WrappedType.body(skin.text, size: 16).copyWith(
                height: 1.3,
              ),
            ),
          ),
          if (rank != null) ...[
            const SizedBox(width: 14),
            WrappedRankBadge(rank: rank!, skin: skin),
          ],
        ],
      ),
    );
  }
}

class _OpeningSlide extends StatelessWidget {
  const _OpeningSlide({
    required this.skin,
    required this.wrapped,
    required this.playerName,
  });

  final WrappedSkin skin;
  final SeasonWrapped wrapped;
  final String? playerName;

  @override
  Widget build(BuildContext context) {
    return _SlideFrame(
      skin: skin,
      top: _SlideLabel(text: 'Ta saison', skin: skin),
      middle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          WrappedReveal(
            delay: const Duration(milliseconds: 120),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                wrapped.seasonName.replaceAll('-', '\n'),
                // Sur deux lignes, les chiffres ont besoin de respirer :
                // l'interligne serré des écrans à un seul nombre les
                // ferait se chevaucher.
                style: WrappedType.figure(skin.figure, size: 128)
                    .copyWith(height: .95),
              ),
            ),
          ),
          const SizedBox(height: 26),
          if (playerName != null && playerName!.isNotEmpty)
            WrappedReveal(
              delay: const Duration(milliseconds: 700),
              child: Text(
                playerName!.toUpperCase(),
                style: WrappedType.title(skin.text, size: 34),
              ),
            ),
        ],
      ),
      bottom: WrappedReveal(
        delay: const Duration(milliseconds: 1100),
        child: Text(
          'L’année est finie. Voici ton résumé…',
          style: WrappedType.title(skin.text, size: 22),
        ),
      ),
    );
  }
}

/// Écran d'un seul chiffre : le format le plus efficace du bilan.
class _FigureSlide extends StatelessWidget {
  const _FigureSlide({
    required this.skin,
    required this.label,
    required this.value,
    required this.rank,
    required this.caption,
    this.suffix = '',
    this.decimals = 0,
  });

  final WrappedSkin skin;
  final String label;
  final num value;
  final int? rank;
  final String caption;
  final String suffix;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    return _SlideFrame(
      skin: skin,
      top: _SlideLabel(text: label, skin: skin),
      middle: _GiantFigure(
        value: value,
        skin: skin,
        suffix: suffix,
        decimals: decimals,
      ),
      bottom: _Caption(text: caption, skin: skin, rank: rank),
    );
  }
}

class _ResponsivenessSlide extends StatelessWidget {
  const _ResponsivenessSlide({required this.skin, required this.wrapped});

  final WrappedSkin skin;
  final SeasonWrapped wrapped;

  @override
  Widget build(BuildContext context) {
    final hours = wrapped.avgResponseHours;

    if (hours == null) {
      return _SlideFrame(
        skin: skin,
        top: _SlideLabel(text: 'Réactivité', skin: skin),
        middle: WrappedReveal(
          delay: const Duration(milliseconds: 200),
          child: Text(
            'Aucune réponse enregistrée',
            style: WrappedType.title(skin.figure, size: 52),
          ),
        ),
        bottom: _Caption(
          text: 'Les disponibilités ouvrent six jours avant chaque match. '
              'La saison prochaine, tu y es.',
          skin: skin,
          rank: null,
          delay: const Duration(milliseconds: 700),
        ),
      );
    }

    // Au-delà de deux jours, la journée parle mieux que l'heure.
    final showDays = hours >= 48;
    final value = showDays ? hours / 24 : hours;

    return _FigureSlide(
      skin: skin,
      label: 'Délai moyen de réponse',
      value: value,
      decimals: value >= 10 ? 0 : 1,
      suffix: showDays ? ' j' : ' h',
      rank: wrapped.avgResponseRank,
      caption: 'En moyenne, entre l’ouverture des disponibilités '
          'et ta réponse.',
    );
  }
}

class _PositionSlide extends StatelessWidget {
  const _PositionSlide({required this.skin, required this.wrapped});

  final WrappedSkin skin;
  final SeasonWrapped wrapped;

  @override
  Widget build(BuildContext context) {
    final positions = wrapped.positionShares;
    final reduced = wrappedReducedMotion(context);

    if (positions.isEmpty) {
      return _SlideFrame(
        skin: skin,
        top: _SlideLabel(text: 'Ton poste', skin: skin),
        middle: WrappedReveal(
          delay: const Duration(milliseconds: 160),
          child: Text(
            'Jamais aligné au coup d’envoi',
            style: WrappedType.title(skin.figure, size: 40),
          ),
        ),
        bottom: _Caption(
          text: 'Tu n’apparais dans aucune composition de départ.',
          skin: skin,
          rank: null,
          delay: const Duration(milliseconds: 700),
        ),
      );
    }

    return _SlideFrame(
      skin: skin,
      top: _SlideLabel(text: 'Ton poste', skin: skin),
      middle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: SizedBox(
              width: 268,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: reduced ? 1 : 0, end: 1),
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 1600),
                curve: Curves.easeOutCubic,
                builder: (context, progress, _) => WrappedInkPitch(
                  skin: skin,
                  positions: positions,
                  progress: progress,
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          WrappedReveal(
            delay: const Duration(milliseconds: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LE PLUS SOUVENT',
                  style: WrappedType.label(skin.muted, size: 12),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    (wrapped.topPosition ?? '').toUpperCase(),
                    style: WrappedType.title(skin.figure, size: 42),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottom: _Caption(
        text: switch (positions.length) {
          1 => 'Un seul poste. Le coach sait où te trouver.',
          2 => 'Deux postes différents cette saison.',
          _ => '${positions.length} postes différents. Couteau suisse.',
        },
        skin: skin,
        rank: wrapped.versatilityRank,
        delay: const Duration(milliseconds: 1700),
      ),
    );
  }
}

class _ContributionSlide extends StatelessWidget {
  const _ContributionSlide({required this.skin, required this.wrapped});

  final WrappedSkin skin;
  final SeasonWrapped wrapped;

  @override
  Widget build(BuildContext context) {
    return _SlideFrame(
      skin: skin,
      top: _SlideLabel(text: 'Ton apport', skin: skin),
      middle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _StackedFigure(
            skin: skin,
            label: 'Buts',
            value: wrapped.goals,
            rank: wrapped.goalsRank,
            delay: const Duration(milliseconds: 200),
          ),
          const SizedBox(height: 30),
          _StackedFigure(
            skin: skin,
            label: 'Homme du match',
            value: wrapped.motm,
            rank: wrapped.motmRank,
            delay: const Duration(milliseconds: 800),
          ),
        ],
      ),
      bottom: WrappedReveal(
        delay: const Duration(milliseconds: 1500),
        child: Text(
          wrapped.motm == 0
              ? 'Le vote Homme du match reste anonyme, comme toujours.'
              : 'Élu par tes coéquipiers. Les bulletins restent secrets.',
          style: WrappedType.body(skin.muted, size: 14),
        ),
      ),
    );
  }
}

class _StackedFigure extends StatelessWidget {
  const _StackedFigure({
    required this.skin,
    required this.label,
    required this.value,
    required this.rank,
    required this.delay,
    this.suffix = '',
  });

  final WrappedSkin skin;
  final String label;
  final num value;
  final int? rank;
  final Duration delay;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return WrappedReveal(
      delay: delay,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: WrappedType.label(skin.muted, size: 12),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: WrappedCountUp(
                    value: value,
                    suffix: suffix,
                    delay: delay + const Duration(milliseconds: 140),
                    style: WrappedType.figure(skin.figure, size: 92),
                  ),
                ),
              ],
            ),
          ),
          if (rank != null) ...[
            const SizedBox(width: 12),
            WrappedRankBadge(rank: rank!, skin: skin, size: 15),
          ],
        ],
      ),
    );
  }
}

class _ResultsSlide extends StatelessWidget {
  const _ResultsSlide({required this.skin, required this.wrapped});

  final WrappedSkin skin;
  final SeasonWrapped wrapped;

  @override
  Widget build(BuildContext context) {
    final winPct = wrapped.winPct;

    return _SlideFrame(
      skin: skin,
      top: _SlideLabel(text: 'L’équipe quand tu étais là', skin: skin),
      middle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          WrappedReveal(
            delay: const Duration(milliseconds: 200),
            child: Row(
              children: [
                _ResultBlock(skin: skin, letter: 'V', value: wrapped.wins),
                _ResultBlock(skin: skin, letter: 'N', value: wrapped.draws),
                _ResultBlock(skin: skin, letter: 'D', value: wrapped.losses),
              ],
            ),
          ),
          const SizedBox(height: 30),
          if (winPct != null)
            _StackedFigure(
              skin: skin,
              label: 'Pourcentage de victoire',
              value: winPct.round(),
              suffix: ' %',
              rank: wrapped.winPctRank,
              delay: const Duration(milliseconds: 800),
            ),
        ],
      ),
      bottom: _Caption(
        text: '${wrapped.cleanMatches} match'
            '${wrapped.cleanMatches > 1 ? 's' : ''} sans encaisser.',
        skin: skin,
        rank: wrapped.cleanMatchesRank,
        delay: const Duration(milliseconds: 1500),
      ),
    );
  }
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({
    required this.skin,
    required this.letter,
    required this.value,
  });

  final WrappedSkin skin;
  final String letter;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(letter, style: WrappedType.label(skin.muted, size: 13)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: WrappedCountUp(
              value: value,
              delay: const Duration(milliseconds: 320),
              style: WrappedType.figure(skin.figure, size: 76),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClosingSlide extends StatelessWidget {
  const _ClosingSlide({
    required this.skin,
    required this.wrapped,
    required this.playerName,
    required this.onShare,
    required this.onShareByTheme,
  });

  final WrappedSkin skin;
  final SeasonWrapped wrapped;
  final String? playerName;
  final VoidCallback onShare;
  final VoidCallback onShareByTheme;

  @override
  Widget build(BuildContext context) {
    return _SlideFrame(
      skin: skin,
      top: _SlideLabel(text: 'Ta saison en entier', skin: skin),
      middle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < wrapped.stats.length; i += 1)
            WrappedReveal(
              delay: Duration(milliseconds: 100 + i * 80),
              child: WrappedRecapLine(stat: wrapped.stats[i], skin: skin),
            ),
        ],
      ),
      bottom: WrappedReveal(
        delay: const Duration(milliseconds: 1000),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (playerName != null && playerName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  playerName!.toUpperCase(),
                  style: WrappedType.title(skin.text, size: 26),
                ),
              ),
            FilledButton.icon(
              onPressed: onShare,
              style: FilledButton.styleFrom(
                backgroundColor: skin.badge,
                foregroundColor: skin.badgeText,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: WrappedType.label(skin.badgeText, size: 14),
              ),
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('PARTAGER MA SAISON'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: onShareByTheme,
              style: TextButton.styleFrom(foregroundColor: skin.muted),
              child: Text(
                'Partager par thème',
                style: WrappedType.body(skin.muted, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une ligne du récapitulatif : intitulé à gauche, valeur à droite, rang au
/// bout. Les colonnes sont fixes pour que rien n'ondule d'une ligne à l'autre.
class WrappedRecapLine extends StatelessWidget {
  const WrappedRecapLine({
    super.key,
    required this.stat,
    required this.skin,
    this.dense = false,
  });

  final SeasonWrappedStat stat;
  final WrappedSkin skin;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final size = dense ? 12.0 : 14.0;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 3 : 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            flex: 7,
            child: Text(
              stat.shortLabel.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WrappedType.label(
                // La graisse fine perd en presence : on la rattrape par
                // le contraste plutot qu'en reepaississant.
                skin.muted.withValues(alpha: .92),
                size: size - 2,
              ).copyWith(letterSpacing: 1.4),
            ),
          ),
          Expanded(
            flex: 10,
            child: Text(
              stat.value,
              maxLines: 1,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: WrappedType.title(skin.figure, size: size + 5)
                  .copyWith(fontWeight: FontWeight.w400),
            ),
          ),
          SizedBox(
            width: dense ? 30 : 36,
            child: Text(
              stat.isRanked ? wrappedOrdinal(stat.rank!) : '',
              textAlign: TextAlign.right,
              style: WrappedType.label(skin.badge, size: size - 3),
            ),
          ),
        ],
      ),
    );
  }
}
