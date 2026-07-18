import 'package:flutter/material.dart';

/// Cartouche de tableau dont la ligne d'en-tête reste fixe en haut pendant que
/// les lignes défilent en dessous. Occupe toute la hauteur disponible : à
/// placer dans un parent à hauteur bornée (Expanded, SizedBox…).
///
/// L'en-tête et les lignes partagent la même largeur de colonnes (mêmes
/// `flex`), donc l'alignement est conservé au défilement.
class StickyHeaderTableCard extends StatelessWidget {
  const StickyHeaderTableCard({
    required this.header,
    required this.rows,
    this.onRefresh,
    super.key,
  });

  /// Ligne d'en-tête, épinglée en haut.
  final Widget header;

  /// Lignes de données, séparées automatiquement par un filet.
  final List<Widget> rows;

  /// Rafraîchissement par tirer-lâcher (optionnel).
  final Future<void> Function()? onRefresh;

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
      child: Column(
        children: [
          header,
          const Divider(height: 1),
          Expanded(child: list),
        ],
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
