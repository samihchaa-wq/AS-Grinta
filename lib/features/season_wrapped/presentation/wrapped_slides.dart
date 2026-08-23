import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem_body.dart';
import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_ink_pitch.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_motion.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Les écrans du bilan, dans l'ordre de lecture.
///
/// Une statistique par écran : les regrouper à deux ou trois obligeait à les
/// écrire plus petit, et la moins bien placée passait pour une note de bas de
/// page. L'ordre suit le fil d'un match — la présence, le résultat, ce qu'on y
/// a apporté, où on a joué — et referme sur le récapitulatif, prêt à partager.
List<Widget> buildWrappedSlides({
  required SeasonWrapped wrapped,
  required String? playerName,
  required VoidCallback onShare,
  required VoidCallback onShareByTheme,
  bool preview = false,
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
    _ResultsSlide(skin: skins[2], wrapped: wrapped),
    _WinRateSlide(skin: skins[3], wrapped: wrapped),
    _FigureSlide(
      skin: skins[4],
      label: 'Buts',
      value: wrapped.goals,
      rank: wrapped.goalsRank,
      caption: switch (wrapped.goals) {
        0 => 'Aucun cette saison. Le premier est pour la prochaine.',
        1 => 'Un but, et il compte autant que les autres.',
        _ => 'Inscrits cette saison, toutes compétitions confondues.',
      },
    ),
    _FigureSlide(
      skin: skins[5],
      label: 'Homme du match',
      value: wrapped.motm,
      rank: wrapped.motmRank,
      caption: wrapped.motm == 0
          ? 'Le vote reste anonyme, comme toujours.'
          : 'Élu par tes coéquipiers. Les bulletins restent secrets.',
    ),
    _FigureSlide(
      skin: skins[6],
      label: 'Matchs sans encaisser',
      value: wrapped.cleanMatches,
      rank: wrapped.cleanMatchesRank,
      caption: wrapped.cleanMatches == 0
          ? 'L’équipe a encaissé à chacune de tes sorties.'
          : 'Autant de matchs où la cage est restée inviolée, toi sur le '
              'terrain.',
    ),
    _PositionSlide(skin: skins[7], wrapped: wrapped),
    _ResponsivenessSlide(skin: skins[8], wrapped: wrapped),
    _BadgesSlide(skin: skins[9], wrapped: wrapped, preview: preview),
    _ClosingSlide(
      skin: skins[10],
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
    this.size = 180,
  });

  final num value;
  final WrappedSkin skin;
  final String suffix;

  /// Un écran qui porte autre chose que ce chiffre lui laisse moins de place.
  final double size;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: WrappedCountUp(
        value: value,
        suffix: suffix,
        style: WrappedType.figure(skin.figure, size: size),
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
              // La phrase du bas explique le chiffre : elle doit se lire
              // d'un coup d'œil, pas à la loupe.
              text,
              style: WrappedType.body(skin.text, size: 22).copyWith(
                height: 1.25,
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
  });

  final WrappedSkin skin;
  final String label;
  final num value;
  final int? rank;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return _SlideFrame(
      skin: skin,
      top: _SlideLabel(text: label, skin: skin),
      middle: _GiantFigure(value: value, skin: skin),
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

    final delay = WrappedDelay.fromHours(hours);
    final minutes = delay.minutes;

    return _SlideFrame(
      skin: skin,
      top: _SlideLabel(text: 'Délai moyen de réponse', skin: skin),
      middle: minutes == null
          ? _GiantFigure(
              value: delay.figure,
              skin: skin,
              suffix: delay.suffix,
            )
          // Un délai en deux nombres se lit en deux temps.
          : FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: WrappedDelayCountUp(
                hours: delay.figure,
                minutes: minutes,
                style: WrappedType.figure(skin.figure),
              ),
            ),
      bottom: _Caption(
        text: 'En moyenne, entre l’ouverture des disponibilités '
            'et ta réponse.',
        skin: skin,
        rank: wrapped.avgResponseRank,
      ),
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
        text: switch (wrapped.versatility) {
          0 || 1 => 'Un seul poste. Le coach sait où te trouver.',
          2 => 'Deux postes différents cette saison.',
          _ => '${wrapped.versatility} postes différents. Couteau suisse.',
        },
        skin: skin,
        rank: wrapped.versatilityRank,
        delay: const Duration(milliseconds: 1700),
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
    return _SlideFrame(
      skin: skin,
      top: _SlideLabel(text: 'L’équipe quand tu étais là', skin: skin),
      middle: WrappedReveal(
        delay: const Duration(milliseconds: 200),
        child: Row(
          children: [
            _ResultBlock(skin: skin, letter: 'V', value: wrapped.wins),
            const SizedBox(width: 18),
            _ResultBlock(skin: skin, letter: 'N', value: wrapped.draws),
            const SizedBox(width: 18),
            _ResultBlock(skin: skin, letter: 'D', value: wrapped.losses),
          ],
        ),
      ),
      bottom: _Caption(
        text: 'Victoires, nuls et défaites, uniquement sur les matchs où tu '
            'étais présent.',
        skin: skin,
        rank: null,
        delay: const Duration(milliseconds: 900),
      ),
    );
  }
}

/// La part de victoires. Elle n'existe pas sans match joué : dans ce cas on
/// le dit, plutôt que d'écrire un zéro qui ferait croire à un mauvais bilan.
class _WinRateSlide extends StatelessWidget {
  const _WinRateSlide({required this.skin, required this.wrapped});

  final WrappedSkin skin;
  final SeasonWrapped wrapped;

  @override
  Widget build(BuildContext context) {
    final winPct = wrapped.winPct;

    if (winPct == null) {
      return _SlideFrame(
        skin: skin,
        top: _SlideLabel(text: 'Pourcentage de victoires', skin: skin),
        middle: WrappedReveal(
          delay: const Duration(milliseconds: 200),
          child: Text(
            'Aucun match joué',
            style: WrappedType.title(skin.figure, size: 52),
          ),
        ),
        bottom: _Caption(
          text: 'Il faut au moins une feuille de match pour en calculer un.',
          skin: skin,
          rank: null,
          delay: const Duration(milliseconds: 700),
        ),
      );
    }

    return _SlideFrame(
      skin: skin,
      top: _SlideLabel(text: 'Pourcentage de victoires', skin: skin),
      middle: _GiantFigure(
        value: winPct.round(),
        skin: skin,
        suffix: ' %',
      ),
      bottom: _Caption(
        text: 'La part des matchs gagnés quand tu étais sur la feuille.',
        skin: skin,
        rank: wrapped.winPctRank,
      ),
    );
  }
}

class _BadgesSlide extends ConsumerWidget {
  const _BadgesSlide({
    required this.skin,
    required this.wrapped,
    required this.preview,
  });

  final WrappedSkin skin;
  final SeasonWrapped wrapped;
  final bool preview;

  /// Au-delà, la grille déborde de l'écran.
  static const int _maxVignettes = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etatArmoire = ref.watch(myArmoireProvider);
    final armoire = etatArmoire.valueOrNull;
    final validees = armoire?.validated ?? const <ArmoireBadge>[];
    final parCode = {for (final badge in validees) badge.def.code: badge};

    // En aperçu, les chiffres sont fictifs : on montre les vraies vignettes de
    // la personne qui regarde, faute de quoi l'écran ne montrerait rien.
    final vignettes = preview
        ? (armoire?.recent ?? const <ArmoireBadge>[])
        : [
            for (final badge in wrapped.badges)
              if (parCode[badge.code] != null) parCode[badge.code]!,
          ];

    // Un badge que l'armoire ne connaît pas garde son nom seul. Tant que
    // l'armoire charge, on n'affiche rien plutôt qu'une liste de noms qui
    // serait remplacée par les vignettes une seconde plus tard.
    final sansVignette = preview || etatArmoire.isLoading
        ? const <SeasonWrappedBadge>[]
        : [
            for (final badge in wrapped.badges)
              if (parCode[badge.code] == null) badge,
          ];

    final total = preview ? vignettes.length : wrapped.badges.length;

    if (total == 0) {
      return _SlideFrame(
        skin: skin,
        top: _SlideLabel(text: 'Tes badges', skin: skin),
        middle: WrappedReveal(
          delay: const Duration(milliseconds: 200),
          child: Text(
            'Aucun badge cette saison',
            style: WrappedType.title(skin.figure, size: 46),
          ),
        ),
        bottom: _Caption(
          text: 'Ils se décrochent en jouant, en marquant, en gardant ta cage '
              'inviolée. La saison prochaine, tu y es.',
          skin: skin,
          rank: null,
          delay: const Duration(milliseconds: 700),
        ),
      );
    }

    final montrees = vignettes.take(_maxVignettes).toList();
    final restants = total - montrees.length - sansVignette.length;

    return _SlideFrame(
      skin: skin,
      top: _SlideLabel(text: 'Tes badges', skin: skin),
      middle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // La grille occupe déjà la moitié de l'écran : le compte se lit
          // plus petit que sur les écrans qui ne portent qu'un chiffre.
          _GiantFigure(value: total, skin: skin, size: 122),
          const SizedBox(height: 28),
          WrappedReveal(
            delay: const Duration(milliseconds: 900),
            child: LayoutBuilder(
              builder: (context, contraintes) {
                // Trois vignettes par ligne, comme dans l'armoire à badges.
                const colonnes = 3;
                const ecart = 12.0;
                final largeur =
                    (contraintes.maxWidth - (colonnes - 1) * ecart) / colonnes;
                final embleme = largeur < 87 ? largeur : 87.0;
                // Tous les emblèmes n'ont pas la même hauteur : un badge de
                // palmarès porte une étoile et n'affiche pas de nombre. On
                // réserve la plus grande hauteur pour tout le monde, et on
                // pose chaque emblème sur ce même socle : sinon les lignes de
                // la grille se décalent les unes par rapport aux autres.
                var hauteur = 0.0;
                for (final badge in montrees) {
                  final h = _hauteurEmbleme(badge) * embleme;
                  if (h > hauteur) hauteur = h;
                }
                return Wrap(
                  spacing: ecart,
                  runSpacing: 16,
                  children: [
                    for (final badge in montrees)
                      _BadgeTile(
                        badge: badge,
                        skin: skin,
                        largeur: largeur,
                        embleme: embleme,
                        hauteurEmbleme: hauteur,
                      ),
                    for (final badge in sansVignette.take(_maxVignettes))
                      _BadgeChip(badge: badge, skin: skin),
                  ],
                );
              },
            ),
          ),
          if (restants > 0) ...[
            const SizedBox(height: 14),
            WrappedReveal(
              delay: const Duration(milliseconds: 1100),
              child: Text(
                restants == 1 ? 'et un autre' : 'et $restants autres',
                style: WrappedType.body(skin.muted, size: 19),
              ),
            ),
          ],
          // La légende du bas ne doit pas coller à la dernière rangée.
          const SizedBox(height: 20),
        ],
      ),
      bottom: _Caption(
        text: total == 1
            ? 'Décroché cette saison.'
            : 'Décrochés cette saison, du premier au dernier.',
        skin: skin,
        rank: null,
        delay: const Duration(milliseconds: 1500),
      ),
    );
  }
}

/// La vignette exacte de l'armoire à badges : illustration, valeur atteinte et
/// critère. Redessiner un badge ici, c'est prendre le risque qu'il diverge.
/// La hauteur d'un emblème rapportée à sa largeur, telle que l'armoire la
/// calcule.
double _hauteurEmbleme(ArmoireBadge badge) {
  final valeur = baremeLabelFor(badge.def.metric, badge.def.threshold);
  final descripteur = badgeDescriptorFor(
    code: badge.def.code,
    metric: badge.def.metric,
    category: badge.def.category,
    name: badge.def.name,
  );
  return badgeEmblemHeightRatio(
    hasValue: valeur != null,
    hasPeriod: descripteur.period != null,
    hasStar: badge.def.hasStar,
  );
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({
    required this.badge,
    required this.skin,
    required this.largeur,
    required this.embleme,
    required this.hauteurEmbleme,
  });

  final ArmoireBadge badge;
  final WrappedSkin skin;
  final double largeur;
  final double embleme;
  final double hauteurEmbleme;

  /// Deux lignes de nom, réservées même quand une seule est écrite : sans
  /// cela, les vignettes n'ont pas la même hauteur et les lignes se décalent.
  static const double _hauteurNom = 32;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: largeur,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: hauteurEmbleme,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: BadgeEmblem(
                emoji: badge.def.emoji,
                imageUrl: badge.def.imageUrl,
                color: badge.def.color,
                // Le palier qu'il a fallu atteindre, pas le total du jour :
                // un « Vétéran » se lit à 100 matchs, même si le compteur
                // affiche 132 depuis.
                baremeLabel: baremeLabelFor(
                  badge.def.metric,
                  badge.def.threshold,
                ),
                descriptor: badgeDescriptorFor(
                  code: badge.def.code,
                  metric: badge.def.metric,
                  category: badge.def.category,
                  name: badge.def.name,
                ),
                showStar: badge.def.hasStar,
                starCount: badge.stars,
                size: embleme,
              ),
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: _hauteurNom,
            child: Text(
              badge.def.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  WrappedType.body(skin.text, size: 13).copyWith(height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.badge, required this.skin});

  final SeasonWrappedBadge badge;
  final WrappedSkin skin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: skin.figure.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge.emoji.isNotEmpty) ...[
            Text(badge.emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 7),
          ],
          Text(badge.name, style: WrappedType.body(skin.text, size: 15)),
        ],
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
    // Chaque nombre est centré dans sa colonne, séparé des deux autres par
    // une règle : côte à côte et alignés à gauche, « 12 4 5 » se lisait comme
    // un seul nombre.
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            letter,
            textAlign: TextAlign.center,
            style: WrappedType.label(skin.muted, size: 15),
          ),
          const SizedBox(height: 8),
          Container(height: 2, color: skin.figure.withValues(alpha: .35)),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: WrappedCountUp(
              value: value,
              delay: const Duration(milliseconds: 320),
              // L'écran ne porte plus que ces trois nombres : ils se lisent
              // aussi gros que le chiffre unique des autres écrans.
              style: WrappedType.figure(skin.figure, size: 112),
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
                style: WrappedType.body(skin.muted, size: 20),
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
