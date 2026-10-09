import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
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
/// soit la longueur des noms. Chaque nom est centré dans sa moitié ; un nom
/// trop long passe à la ligne en lignes équilibrées, sans changer de taille.
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
    this.nameSize = CalendarTeamName.regularSize,
    this.crestSize = regularCrestSize,
    this.limitNameLines = true,
  });

  final String homeName;
  final String awayName;
  final bool grintaIsHome;
  final int? homeScore;
  final int? awayScore;
  final bool finished;
  final Color? foreground;

  /// Taille des noms d'équipes et du score.
  final double nameSize;

  /// Taille de l'écusson AS Grinta.
  final double crestSize;

  /// Sans limite, un nom très long passe sur autant de lignes que nécessaire
  /// et n'est jamais coupé par « … ».
  final bool limitNameLines;

  static const String crestAsset = 'assets/images/as_grinta_logo.webp';

  /// Taille habituelle de l'écusson, celle des cartes du calendrier.
  static const double regularCrestSize = 32;

  /// Écart identique entre chaque équipe et le score.
  static const double scoreGap = 12;

  bool get _hasScores => finished && homeScore != null && awayScore != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameColor = foreground ?? AppTheme.textPrimary;
    final Widget center;
    if (_hasScores) {
      final grinta = grintaIsHome ? homeScore! : awayScore!;
      final opponent = grintaIsHome ? awayScore! : homeScore!;
      final scoreColor = MatchFixture.resultColor(grinta, opponent);
      center = Semantics(
        label: '$homeName $homeScore, $awayName $awayScore',
        excludeSemantics: true,
        child: Text(
          '$homeScore – $awayScore',
          maxLines: 1,
          softWrap: false,
          // Même taille que les noms d'équipes, sur la même ligne.
          style: theme.textTheme.titleMedium?.copyWith(
            color: scoreColor,
            fontSize: nameSize,
            height: 1.15,
            fontWeight: FontWeight.w400,
            // Des chiffres colorés sur fond sombre paraissent plus fins que
            // les noms en blanc : un léger contour de la même couleur leur
            // redonne la même épaisseur visuelle, sans passer en gras.
            shadows: [
              for (final offset in const [
                Offset(.35, 0),
                Offset(-.35, 0),
                Offset(0, .35),
                Offset(0, -.35),
              ])
                Shadow(color: scoreColor, offset: offset),
            ],
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
            isHome: true,
            color: nameColor,
            nameSize: nameSize,
            crestSize: crestSize,
            limitLines: limitNameLines,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: scoreGap),
          child: center,
        ),
        Expanded(
          child: _ScorelineTeam(
            name: awayName,
            isGrinta: !grintaIsHome,
            isHome: false,
            color: nameColor,
            nameSize: nameSize,
            crestSize: crestSize,
            limitLines: limitNameLines,
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
    required this.isHome,
    required this.color,
    required this.nameSize,
    required this.crestSize,
    required this.limitLines,
  });

  final String name;
  final bool isGrinta;

  /// Le nom est centré dans sa moitié de carte (comme les boutons
  /// « Présent » / « Absent »). L'écusson se place côté extérieur ; un espace
  /// de même largeur est réservé de l'autre côté pour que le nom, lui, reste
  /// pile au centre de sa moitié.
  final bool isHome;
  final Color color;
  final double nameSize;
  final double crestSize;
  final bool limitLines;

  static const double _crestGap = 6;

  @override
  Widget build(BuildContext context) {
    final crest = ExcludeSemantics(
      child: Image(
        image: const AssetImage(CalendarScoreline.crestAsset),
        width: crestSize,
        height: crestSize,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
    final label = CalendarTeamName(
      name: name,
      color: color,
      fontSize: nameSize,
      limitLines: limitLines,
    );

    if (!isGrinta) return Center(child: label);

    final reserved = SizedBox(width: crestSize + _crestGap);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Le nom est centré dans sa moitié, avec en miroir de l'écusson un
        // espace de même largeur. Si cette réserve ferait passer le nom sur
        // deux lignes, on centre plutôt le bloc écusson + nom : le nom reste
        // sur une ligne, légèrement décalé.
        final nameWidth = CalendarTeamName.singleLineWidth(
          context,
          name,
          color,
          fontSize: nameSize,
        );
        final symmetric =
            nameWidth + 2 * (crestSize + _crestGap) <= constraints.maxWidth;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isHome) ...[
              crest,
              const SizedBox(width: _crestGap),
            ] else if (symmetric)
              reserved,
            Flexible(child: label),
            if (!isHome) ...[
              const SizedBox(width: _crestGap),
              crest,
            ] else if (symmetric)
              reserved,
          ],
        );
      },
    );
  }
}

/// Nom d'équipe, toujours en taille normale : s'il ne tient pas sur une
/// ligne, il est réparti sur des lignes de longueur équilibrée.
class CalendarTeamName extends StatelessWidget {
  const CalendarTeamName({
    super.key,
    required this.name,
    required this.color,
    this.textAlign = TextAlign.center,
    this.fontSize = regularSize,
    this.limitLines = true,
  });

  final String name;
  final Color color;
  final TextAlign textAlign;
  final double fontSize;

  /// Sans limite, le nom n'est jamais coupé par « … ».
  final bool limitLines;

  static const double regularSize = 17;

  static const int maxLines = 4;

  /// Découpe [name] en lignes de longueur la plus égale possible.
  ///
  /// Si le nom tient sur une ligne, il reste entier. Sinon on cherche le plus
  /// petit nombre de lignes qui tiennent dans [maxWidth], puis, parmi toutes
  /// les coupures entre les mots, celle dont la ligne la plus longue est la
  /// plus courte. On évite ainsi un « 2 » ou un « FC » seul en dessous :
  /// « TOAC Foot / Loisir 2 » plutôt que « TOAC Foot Loisir / 2 ».
  static List<String> balancedLines(
    String name,
    double Function(String line) widthOf,
    double maxWidth, {
    int lineLimit = maxLines,
  }) {
    final trimmed = name.trim();
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length < 2 || widthOf(trimmed) <= maxWidth) return [trimmed];

    List<String>? fallback;
    var fallbackWidth = double.infinity;
    for (var count = 2; count <= lineLimit && count <= words.length; count++) {
      List<String>? best;
      var bestWidth = double.infinity;

      void search(int start, List<String> lines) {
        final remaining = count - lines.length;
        if (remaining == 1) {
          final candidate = [...lines, words.sublist(start).join(' ')];
          final widest = candidate.map(widthOf).reduce((a, b) => a > b ? a : b);
          if (widest < bestWidth) {
            bestWidth = widest;
            best = candidate;
          }
          return;
        }
        // Laisse au moins un mot pour chacune des lignes restantes.
        for (var end = start + 1;
            end <= words.length - (remaining - 1);
            end++) {
          search(end, [...lines, words.sublist(start, end).join(' ')]);
        }
      }

      search(0, const []);
      if (best != null && bestWidth <= maxWidth) return best!;
      if (best != null && bestWidth < fallbackWidth) {
        fallbackWidth = bestWidth;
        fallback = best;
      }
    }
    // Un mot à lui seul plus large que la place : on garde la coupure la plus
    // équilibrée, et le retour à la ligne automatique termine le travail.
    return fallback ?? [trimmed];
  }

  static TextStyle _style(
    BuildContext context,
    Color color, {
    double fontSize = regularSize,
  }) =>
      (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).copyWith(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        height: 1.15,
      );

  /// Largeur d'une ligne de texte, mesurée exactement comme le widget Text
  /// l'affichera (même fusion de style, même agrandissement du texte).
  static double _lineWidth(BuildContext context, String line, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: line,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// Largeur du nom s'il était affiché sur une seule ligne.
  static double singleLineWidth(
    BuildContext context,
    String name,
    Color color, {
    double fontSize = regularSize,
  }) =>
      _lineWidth(
        context,
        name.trim(),
        _style(context, color, fontSize: fontSize),
      );

  @override
  Widget build(BuildContext context) {
    final style = _style(context, color, fontSize: fontSize);

    return LayoutBuilder(
      builder: (context, constraints) {
        double widthOf(String line) => _lineWidth(context, line, style);

        final lines = balancedLines(
          name,
          widthOf,
          constraints.maxWidth,
          // Au-delà de 6 lignes, la recherche de coupures équilibrées
          // devient coûteuse ; le retour à la ligne automatique prend le
          // relais sans jamais tronquer.
          lineLimit: limitLines ? maxLines : 6,
        );
        return Text(
          lines.join('\n'),
          semanticsLabel: name,
          textAlign: textAlign,
          maxLines: limitLines ? maxLines : null,
          overflow: limitLines ? TextOverflow.ellipsis : null,
          // La largeur du texte épouse sa ligne la plus longue : le nom reste
          // collé au score même quand il passe sur plusieurs lignes.
          textWidthBasis: TextWidthBasis.longestLine,
          style: style,
        );
      },
    );
  }
}

/// Titre centré d'une carte sans affiche (« Match entre nous », événement).
class CalendarCenteredTitle extends StatelessWidget {
  const CalendarCenteredTitle(
    this.text, {
    super.key,
    this.color,
    this.fontSize = CalendarTeamName.regularSize,
  });

  final String text;
  final Color? color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: fontSize,
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
    this.actionsWidth = actionExtent,
  });

  final Widget child;
  final Widget? actions;
  final double actionsWidth;

  /// Largeur réservée à une action (cloche, crayon…).
  static const double actionExtent = 40;

  /// Espace à laisser libre à droite de la date pour une action.
  static const double dateInset = 34;

  static double dateInsetFor(int actionCount) {
    if (actionCount <= 0) return 0;
    return dateInset + (actionCount - 1) * actionExtent;
  }

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
          child: SizedBox(
            width: actionsWidth,
            height: actionExtent,
            child: actions,
          ),
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
  static const double betweenCards = 28;

  /// Marge haute et basse des bandeaux foncés (date, adresse).
  static const double band = 12;
}

/// Découpe d'une carte du calendrier en trois zones :
///
/// - en haut, un bandeau plus foncé avec la date, l'heure et le type ;
/// - au milieu, sur la couleur de la carte, l'affiche (équipes et score) ;
/// - en bas, un second bandeau plus foncé avec l'adresse, s'il y en a une.
class CalendarCardSections extends StatelessWidget {
  const CalendarCardSections({
    super.key,
    required this.header,
    required this.body,
    this.footer,
    this.bandVerticalPadding = CalendarCardSpacing.band,
    this.bodyVerticalPadding = CalendarCardSpacing.vertical,
    this.bandHorizontalPadding = 14,
    this.bodyHorizontalPadding = 12,
  });

  final Widget header;
  final Widget body;
  final Widget? footer;
  final double bandVerticalPadding;
  final double bodyVerticalPadding;
  final double bandHorizontalPadding;
  final double bodyHorizontalPadding;

  /// Voile posé sur la couleur de la carte pour foncer les bandeaux.
  static const Color bandShade = Color(0x47000000);

  @override
  Widget build(BuildContext context) {
    Widget band(Widget child) => ColoredBox(
          color: bandShade,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: bandHorizontalPadding,
              vertical: bandVerticalPadding,
            ),
            child: child,
          ),
        );

    final footer = this.footer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        band(header),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: bodyHorizontalPadding,
            vertical: bodyVerticalPadding,
          ),
          child: body,
        ),
        if (footer != null) band(footer),
      ],
    );
  }
}

/// Ligne « date • heure • type » du bandeau du haut.
class CalendarDateLine extends StatelessWidget {
  const CalendarDateLine({
    super.key,
    required this.kickoffAt,
    this.showTime = true,
    this.label,
    this.endInset = 0,
    this.limitLines = true,
  });

  final DateTime kickoffAt;
  final bool showTime;
  final String? label;

  /// Sans limite, la ligne passe à la ligne autant que nécessaire et n'est
  /// jamais coupée par « … ».
  final bool limitLines;

  /// Place laissée à droite pour le bouton d'administration.
  final double endInset;

  String _compose() {
    final parts = [
      AppFormats.calendarDateTimeLong(kickoffAt, includeTime: showTime),
      if (label case final extra? when extra.trim().isNotEmpty) extra,
    ];
    if (limitLines) return parts.join(' • ');
    // Sans limite de lignes, la ligne ne se coupe qu'entre deux éléments :
    // jamais « J2 » ou « 2026 » seul en dessous.
    return parts
        .map((part) => part.trim().replaceAll(' ', '\u00A0'))
        .join('\u00A0• ');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(end: endInset),
      child: Text(
        _compose(),
        maxLines: limitLines ? 2 : null,
        overflow: limitLines ? TextOverflow.ellipsis : null,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppTheme.textPrimary,
              fontSize: 12,
              height: 1.15,
              fontWeight: FontWeight.w400,
            ),
      ),
    );
  }
}

/// Adresse du bandeau du bas, cliquable pour ouvrir le choix du GPS.
class CalendarAddressLine extends StatelessWidget {
  const CalendarAddressLine(
    this.address, {
    super.key,
    this.onTap,
    this.limitLines = true,
  });

  final String address;
  final VoidCallback? onTap;

  /// Sans limite, l'adresse n'est jamais coupée par « … ».
  final bool limitLines;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      address,
      maxLines: limitLines ? 2 : null,
      overflow: limitLines ? TextOverflow.ellipsis : null,
      // Même hauteur de ligne que la date du bandeau du haut : l'espace entre
      // le bord de la carte et le texte est ainsi identique en haut et en bas.
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppTheme.textSecondary,
            fontSize: 12,
            height: 1.15,
            fontWeight: FontWeight.w400,
          ),
    );
    final onTap = this.onTap;
    if (onTap == null) return text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: text,
    );
  }
}
