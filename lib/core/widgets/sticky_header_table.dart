import 'dart:math' as math;

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

const grintaTableMinWidth = 620.0;
const grintaTableHeaderFontSize = 11.5;
const grintaTableCellFontSize = 13.0;
const grintaTableRankFontSize = 12.0;
const grintaTableHeaderPadding = EdgeInsets.fromLTRB(14, 13, 14, 13);
const grintaTableRowPadding = EdgeInsets.fromLTRB(14, 15, 14, 15);

TextStyle grintaTableHeaderTextStyle(
  BuildContext context, {
  Color? color,
}) {
  return TextStyle(
    color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    fontSize: grintaTableHeaderFontSize,
    fontWeight: FontWeight.w800,
    letterSpacing: .35,
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
  );
}

TextStyle grintaTableRankTextStyle(
  BuildContext context, {
  Color? color,
}) {
  return TextStyle(
    color: color ?? AppTheme.primaryBright,
    fontSize: grintaTableRankFontSize,
    fontWeight: FontWeight.w900,
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

  /// Ligne d'en-tête, épinglée en haut.
  final Widget header;

  /// Lignes de données, séparées automatiquement par un filet.
  final List<Widget> rows;

  /// Rafraîchissement par tirer-lâcher (optionnel).
  final Future<void> Function()? onRefresh;

  /// Largeur minimale commune avant activation du défilement horizontal.
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    Widget list = ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 4),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return DecoratedBox(
          decoration: BoxDecoration(
            color: index.isEven
                ? Colors.transparent
                : AppTheme.surfaceHigh.withValues(alpha: .16),
            border: Border(
              bottom: BorderSide(
                color: AppTheme.outline.withValues(alpha: .28),
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
      color: AppTheme.surface.withValues(alpha: .86),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        side: BorderSide(
          color: AppTheme.outline.withValues(alpha: .52),
        ),
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
                    color: AppTheme.surfaceHigh.withValues(alpha: .88),
                    child: header,
                  ),
                  Divider(
                    height: 1,
                    color: AppTheme.primaryBright.withValues(alpha: .30),
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
          const SizedBox(width: 2),
          Icon(
            descending ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
            size: 16,
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
