import 'dart:math' as math;

import 'package:flutter/material.dart';

const grintaTableMinWidth = 620.0;
const grintaTableHeaderFontSize = 12.0;
const grintaTableCellFontSize = 13.0;
const grintaTableRankFontSize = 12.0;
const grintaTableHeaderPadding = EdgeInsets.fromLTRB(12, 12, 12, 12);
const grintaTableRowPadding = EdgeInsets.fromLTRB(12, 14, 12, 14);

TextStyle grintaTableHeaderTextStyle(
  BuildContext context, {
  Color? color,
}) {
  return TextStyle(
    color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    fontSize: grintaTableHeaderFontSize,
    fontWeight: FontWeight.w800,
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
  );
}

TextStyle grintaTableRankTextStyle(
  BuildContext context, {
  Color? color,
}) {
  return TextStyle(
    color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    fontSize: grintaTableRankFontSize,
    fontWeight: FontWeight.w700,
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
    Widget list = ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => rows[index],
    );
    if (onRefresh != null) {
      list = RefreshIndicator(onRefresh: onRefresh!, child: list);
    }

    return Card(
      clipBehavior: Clip.antiAlias,
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
                  header,
                  const Divider(height: 1),
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
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: onTap,
        child: Row(
          mainAxisAlignment: mainAxis,
          children: [
            Flexible(
              child: Text(
                label,
                style: style,
                overflow: TextOverflow.ellipsis,
                textAlign: align,
              ),
            ),
            if (active)
              Icon(
                descending ? Icons.arrow_drop_down : Icons.arrow_drop_up,
                size: 16,
                color: style?.color,
              ),
          ],
        ),
      ),
    );
  }
}
