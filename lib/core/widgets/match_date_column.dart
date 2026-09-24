import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:flutter/material.dart';

/// Colonne date/heure historique, conservée pour les écrans qui en auraient
/// encore besoin directement :
///
/// ```
/// Lun
/// 07
/// Sept
/// 20:45
/// ```
class MatchDateColumn extends StatelessWidget {
  const MatchDateColumn({
    super.key,
    required this.kickoffAt,
    this.foreground,
    this.secondary,
  });

  final DateTime kickoffAt;
  final Color? foreground;
  final Color? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final main = foreground ?? theme.textTheme.bodyMedium?.color;
    final soft = secondary ?? theme.hintColor;

    Widget line(String text, {bool bold = false, Color? color}) => Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color ?? (bold ? main : soft),
            fontWeight: bold ? FontWeight.w400 : FontWeight.w400,
            fontSize: 14,
            height: 1.15,
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        line(AppFormats.weekdayShort(kickoffAt)),
        line(AppFormats.dayNumber(kickoffAt), bold: true),
        line(AppFormats.monthShort(kickoffAt)),
        line(AppFormats.hourMinute(kickoffAt)),
      ],
    );
  }
}

/// En-tête compact d'une fiche calendrier.
///
/// La date n'est plus comprimée dans une colonne à gauche : elle est affichée
/// en toutes lettres sur une ligne, juste au-dessus de l'affiche. Cela libère
/// toute la largeur pour les noms d'équipes et les scores, en « Défilé » comme
/// en « Par mois ».
class MatchDateHeader extends StatelessWidget {
  const MatchDateHeader({
    super.key,
    required this.kickoffAt,
    required this.child,
    this.foreground,
    this.secondary,
    this.dividerColor,
    this.showTime = true,
    this.dateEndInset = 0,
    this.gap = 7,
    this.label,
  });

  final DateTime kickoffAt;
  final Widget child;
  final Color? foreground;

  /// Conservé pour compatibilité avec les appels existants. La date longue
  /// utilise volontairement la couleur principale afin de rester blanche sur
  /// les cartes du calendrier.
  final Color? secondary;

  /// Conservé pour compatibilité : le filet vertical a été supprimé avec la
  /// nouvelle disposition.
  final Color? dividerColor;

  /// Les archives importées n'ont historiquement qu'une date sans heure.
  final bool showTime;

  /// Marge à droite de la date, pour laisser la place à un bouton posé dans
  /// le coin de la carte.
  final double dateEndInset;

  /// Espace entre la date et le contenu de la carte.
  final double gap;

  /// Complément affiché après l'heure, séparé par un point (ex. le type de
  /// match : « Championnat · J20 »).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateColor = foreground ?? theme.textTheme.bodyMedium?.color;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(end: dateEndInset),
          child: Text(
            [
              AppFormats.calendarDateTimeLong(kickoffAt, includeTime: showTime),
              if (label case final extra? when extra.trim().isNotEmpty) extra,
            ].join(' • '),
            maxLines: label == null ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: dateColor,
              fontSize: 12,
              height: 1.15,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        SizedBox(height: gap),
        SizedBox(width: double.infinity, child: child),
      ],
    );
  }
}
