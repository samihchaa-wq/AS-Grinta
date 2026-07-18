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
