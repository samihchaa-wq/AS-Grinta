import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:flutter/material.dart';

/// Affiche d'une rencontre sur une seule ligne, pour les cartes du calendrier :
///
/// ```
/// [écusson] AS Grinta    3 – 4    AS Clinique Pasteur
/// ```
///
/// Les deux équipes occupent chacune la même largeur : le score (ou « VS »
/// avant le coup d'envoi) tombe donc pile au milieu de la carte, quelle que
/// soit la longueur des noms. Un nom trop long passe sur plusieurs lignes, en
/// police légèrement plus petite, au lieu d'être coupé.
class CalendarScoreline extends StatelessWidget {
  const CalendarScoreline({
    super.key,
    required this.homeName,
    required this.awayName,
    required this.grintaIsHome,
    this.homeScore,
    this.awayScore,
    this.finished = false,
    this.foreground,
  });

  final String homeName;
  final String awayName;
  final bool grintaIsHome;
  final int? homeScore;
  final int? awayScore;
  final bool finished;
  final Color? foreground;

  static const String crestAsset = 'assets/images/as_grinta_logo.webp';

  bool get _hasScores => finished && homeScore != null && awayScore != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameColor = foreground ?? AppTheme.textPrimary;
    final Widget center;
    if (_hasScores) {
      final grinta = grintaIsHome ? homeScore! : awayScore!;
      final opponent = grintaIsHome ? awayScore! : homeScore!;
      center = Semantics(
        label: '$homeName $homeScore, $awayName $awayScore',
        excludeSemantics: true,
        child: Text(
          '$homeScore – $awayScore',
          maxLines: 1,
          softWrap: false,
          // Même taille que les noms d'équipes, sur la même ligne.
          style: theme.textTheme.titleMedium?.copyWith(
            color: MatchFixture.resultColor(grinta, opponent),
            fontSize: CalendarTeamName.regularSize,
            height: 1.15,
            fontWeight: FontWeight.w400,
          ),
        ),
      );
    } else {
      center = Text(
        'VS',
        style: theme.textTheme.labelLarge?.copyWith(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w400,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _ScorelineTeam(
            name: homeName,
            isGrinta: grintaIsHome,
            crestBeforeName: true,
            color: nameColor,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: center,
        ),
        Expanded(
          child: _ScorelineTeam(
            name: awayName,
            isGrinta: !grintaIsHome,
            crestBeforeName: false,
            color: nameColor,
          ),
        ),
      ],
    );
  }
}

class _ScorelineTeam extends StatelessWidget {
  const _ScorelineTeam({
    required this.name,
    required this.isGrinta,
    required this.crestBeforeName,
    required this.color,
  });

  final String name;
  final bool isGrinta;

  /// Écusson à gauche du nom pour l'équipe à domicile, à droite pour
  /// l'équipe à l'extérieur : la ligne reste symétrique autour du score.
  final bool crestBeforeName;
  final Color color;

  static const double _crestSize = 32;
  static const double _crestGap = 6;

  @override
  Widget build(BuildContext context) {
    const crest = ExcludeSemantics(
      child: Image(
        image: AssetImage(CalendarScoreline.crestAsset),
        width: _crestSize,
        height: _crestSize,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
    final label = Flexible(
      child: CalendarTeamName(name: name, color: color),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isGrinta && crestBeforeName) ...[
          crest,
          const SizedBox(width: _crestGap),
        ],
        label,
        if (isGrinta && !crestBeforeName) ...[
          const SizedBox(width: _crestGap),
          crest,
        ],
      ],
    );
  }
}

/// Nom d'équipe centré : sur une ligne à taille normale s'il tient, sinon
/// réparti sur plusieurs lignes dans une police un peu plus petite.
class CalendarTeamName extends StatelessWidget {
  const CalendarTeamName({super.key, required this.name, required this.color});

  final String name;
  final Color color;

  static const double regularSize = 17;
  static const double compactSize = 14.5;

  @override
  Widget build(BuildContext context) {
    // Même fusion que celle faite par le widget Text : la mesure ci-dessous
    // doit correspondre exactement au rendu, sinon un nom « limite » serait
    // tronqué au lieu de passer à la ligne.
    final base = DefaultTextStyle.of(context).style.merge(
          (Theme.of(context).textTheme.titleMedium ?? const TextStyle())
              .copyWith(
            color: color,
            fontWeight: FontWeight.w400,
            height: 1.15,
          ),
        );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final regular = base.copyWith(fontSize: regularSize);
        final painter = TextPainter(
          text: TextSpan(text: name, style: regular),
          maxLines: 1,
          textDirection: direction,
          textScaler: scaler,
        )..layout(maxWidth: constraints.maxWidth);
        final fits = !painter.didExceedMaxLines;
        painter.dispose();

        return Text(
          name,
          textAlign: TextAlign.center,
          maxLines: fits ? 1 : 4,
          overflow: TextOverflow.ellipsis,
          style: fits ? regular : base.copyWith(fontSize: compactSize),
        );
      },
    );
  }
}

/// Titre centré d'une carte sans affiche (« Match entre nous », événement).
class CalendarCenteredTitle extends StatelessWidget {
  const CalendarCenteredTitle(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 17,
              height: 1.15,
              fontWeight: FontWeight.w400,
              color: color ?? AppTheme.textPrimary,
            ),
      ),
    );
  }
}

/// Place le bouton d'administration (crayon) dans le coin haut droit d'une
/// carte, à hauteur de la date, sans empiéter sur la largeur de l'affiche :
/// le score reste ainsi centré même quand le bouton est présent.
class CalendarCardActionsOverlay extends StatelessWidget {
  const CalendarCardActionsOverlay({
    super.key,
    required this.child,
    this.actions,
  });

  final Widget child;
  final Widget? actions;

  /// Espace à laisser libre à droite de la date quand un bouton est affiché.
  static const double dateInset = 34;

  @override
  Widget build(BuildContext context) {
    final actions = this.actions;
    if (actions == null) return child;
    return Stack(
      children: [
        child,
        Positioned(
          top: 2,
          right: 2,
          child: SizedBox.square(dimension: 40, child: actions),
        ),
      ],
    );
  }
}

/// Espacements communs des cartes du calendrier (« Défilé » et « Par mois »).
abstract final class CalendarCardSpacing {
  /// Marge intérieure en haut et en bas de chaque carte.
  static const double vertical = 20;

  /// Espace entre deux lignes d'une même carte (date, affiche, type, lieu).
  static const double line = 14;

  /// Espace entre deux cartes.
  static const double betweenCards = 18;
}
