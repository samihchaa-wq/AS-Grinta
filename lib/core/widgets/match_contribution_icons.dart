import 'package:flutter/material.dart';

/// Icônes des faits de match d'un joueur, partagées par la composition d'un
/// match terminé et la fiche joueur : ⚽ pour un but, un crampon pour une
/// passe décisive, 👑 pour l'Homme du match.

/// Ballon d'un but.
class GoalIcon extends StatelessWidget {
  const GoalIcon({super.key, this.size = 11});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Text('⚽', style: TextStyle(fontSize: size, height: 1));
  }
}

/// Couronne de l'Homme du match.
class ManOfTheMatchIcon extends StatelessWidget {
  const ManOfTheMatchIcon({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Text('👑', style: TextStyle(fontSize: size, height: 1));
  }
}

/// Crampon d'une passe décisive, dans son cercle, en blanc sur un disque
/// noir : sur fond transparent, le trait blanc se perdait dans les bandes
/// claires du terrain et sur les photos des joueurs.
///
/// [size] est la hauteur, comme la taille de police d'un emoji voisin.
class AssistBootIcon extends StatelessWidget {
  const AssistBootIcon({super.key, this.size = 11});

  final double size;

  @override
  Widget build(BuildContext context) {
    // Le cercle blanc du dessin occupe toute l'image : le disque noir, de la
    // même taille, ne déborde pas autour.
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.black,
        shape: BoxShape.circle,
      ),
      child: Image.asset(
        'assets/images/icons/assist_boot.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
