import 'dart:math' as math;

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

const grintaTableMinWidth = 620.0;
const grintaTableHeaderFontSize = 11.5;
const grintaTableCellFontSize = 13.5;
const grintaTableRankFontSize = 12.5;
const grintaTableHeaderPadding = EdgeInsets.fromLTRB(16, 12, 16, 12);
const grintaTableRowPadding = EdgeInsets.fromLTRB(16, 17, 16, 17);

TextStyle grintaTableHeaderTextStyle(BuildContext context, {Color? color}) {
  return TextStyle(
    color: color ?? AppTheme.textSecondary,
    fontSize: grintaTableHeaderFontSize,
    fontWeight: FontWeight.w800,
    letterSpacing: .55,
    height: 1,
  );
}

TextStyle grintaTableCellTextStyle(
  BuildContext context, {
  Color? color,
  FontWeight fontWeight = FontWeight.w700,
}) {
  return TextStyle(
    color: color ?? Theme.of(context).colorScheme.onSurface,
    fontSize: grintaTableCellFontSize,
    fontWeight: fontWeight,
    height: 1.15,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

TextStyle grintaTableRankTextStyle(BuildContext context, {Color? color}) {
  return TextStyle(
    color: color ?? AppTheme.textFaint,
    fontSize: grintaTableRankFontSize,
    fontWeight: FontWeight.w900,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Cartouche de tableau dont la ligne d'en-tête reste fixe en haut pendant que
/// les lignes défilent en dessous. Occupe toute la hauteur disponible : à
/// placer dans un parent à hauteur bornée (Expanded, SizedBox…).
///
/// L'en-tête et les lignes partagent la même largeur de colonnes (mêmes
/// `flex`), donc l'alignement est conservé au défilement. Le tableau dispose
/// aussi d'une largeur minimale commune et peut être glissé horizontalement
/// pour afficher toutes ses colonnes sur les petits écrans.
class StickyHeaderTableCard extends StatelessWidget {
  const StickyHeaderTableCard({
    required this.header,
    required this.rows,
    this.onRefresh,
    this.minWidth = grintaTableMinWidth,
    super.key,
  });

  final Widget header;
  final List<Widget> rows;
  final Future<void> Function()? onRefresh;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    Widget list = ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 6),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return DecoratedBox(
          decoration: BoxDecoration(
            color: index.isEven
                ? Colors.transparent
                : AppTheme.surfaceHigh.withValues(alpha: .10),
            border: Border(
              bottom: BorderSide(
                color: AppTheme.outline.withValues(alpha: .16),
              ),
            ),
          ),
          child: row,
        );
      },
    );
    if (onRefresh != null) {
      list = RefreshIndicator(onRefresh: onRefresh!, child: list);
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      color: AppTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(color: AppTheme.outline.withValues(alpha: .24)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = math.max(constraints.maxWidth, minWidth);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: SizedBox(
              width: tableWidth,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  ColoredBox(
                    color: AppTheme.surfaceHigh,
                    child: header,
                  ),
                  Divider(
                    height: 1,
                    color: AppTheme.outline.withValues(alpha: .22),
                  ),
                  Expanded(child: list),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Cellule d'en-tête cliquable : un appui trie le tableau selon cette colonne
/// (et inverse le sens si la colonne est déjà active). Une flèche ↑/↓ indique
/// la colonne et le sens de tri courants.
class SortableHeaderCell extends StatelessWidget {
  const SortableHeaderCell({
    required this.label,
    required this.flex,
    required this.active,
    required this.descending,
    required this.onTap,
    this.align = TextAlign.center,
    this.style,
    super.key,
  });

  final String label;
  final int flex;
  final bool active;
  final bool descending;
  final VoidCallback onTap;
  final TextAlign align;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final mainAxis = switch (align) {
      TextAlign.start || TextAlign.left => MainAxisAlignment.start,
      TextAlign.end || TextAlign.right => MainAxisAlignment.end,
      _ => MainAxisAlignment.center,
    };

    final content = Row(
      mainAxisAlignment: mainAxis,
      children: [
        Flexible(
          child: Text(
            label,
            style: style?.copyWith(
              color: active ? AppTheme.primaryBright : style?.color,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: align,
          ),
        ),
        if (active) ...[
          const SizedBox(width: 3),
          Icon(
            descending ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
            size: 15,
            color: AppTheme.primaryBright,
          ),
        ],
      ],
    );

    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: content,
        ),
      ),
    );
  }
}
