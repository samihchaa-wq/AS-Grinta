import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:flutter/material.dart';

/// Colonne date/heure d'une rencontre, façon calendrier :
///
/// ```
/// Lun
/// 07
/// Sept
/// 20:45
/// ```
///
/// Pensée pour être posée à gauche d'un [MatchFixture], séparée par un filet
/// vertical.
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
            fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
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

/// Combine [MatchDateColumn] + un filet vertical + un contenu (typiquement un
/// [MatchFixture]).
class MatchDateHeader extends StatelessWidget {
  const MatchDateHeader({
    super.key,
    required this.kickoffAt,
    required this.child,
    this.foreground,
    this.secondary,
    this.dividerColor,
  });

  final DateTime kickoffAt;
  final Widget child;
  final Color? foreground;
  final Color? secondary;
  final Color? dividerColor;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 52,
            child: MatchDateColumn(
              kickoffAt: kickoffAt,
              foreground: foreground,
              secondary: secondary,
            ),
          ),
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: dividerColor ??
                (foreground ?? Theme.of(context).dividerColor).withValues(
                  alpha: .25,
                ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: SizedBox(width: double.infinity, child: child),
            ),
          ),
        ],
      ),
    );
  }
}
