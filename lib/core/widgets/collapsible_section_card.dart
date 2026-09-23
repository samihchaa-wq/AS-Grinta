import 'package:flutter/material.dart';

/// Carte rétractable partagée par les sections de la fiche d'un match
/// (« Faits du match », « Votes HDM », « Prono »). Fermée à l'ouverture de
/// la page ; son état ouvert/fermé est mémorisé par [storageKey] pour ne pas
/// se refermer quand la carte sort de l'écran puis y revient.
class CollapsibleSectionCard extends StatelessWidget {
  const CollapsibleSectionCard({
    super.key,
    required this.storageKey,
    required this.icon,
    required this.title,
    required this.children,
    this.childrenPadding = EdgeInsets.zero,
  });

  final String storageKey;
  final IconData icon;
  final String title;
  final List<Widget> children;
  final EdgeInsetsGeometry childrenPadding;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey<String>(storageKey),
        leading: Icon(icon),
        title: Text(title),
        // Pas de filet au-dessus et au-dessous quand la carte est ouverte.
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: childrenPadding,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
