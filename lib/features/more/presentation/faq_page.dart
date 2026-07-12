import 'package:flutter/material.dart';

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  static const _entries = <({String question, String answer})>[
    (
      question: 'Comment je crÃ©e mon compte ?',
      answer:
          'Avec le lien dâinscription partagÃ© dans la conversation du club : '
          'tu renseignes ton prÃ©nom, ton nom et ton mot de passe. Ton identifiant est gÃ©nÃ©rÃ© '
          'automatiquement (prÃ©nom + premiÃ¨re lettre du nom, ex. samihc) â '
          'retiens-le bien ! l’admin valide ensuite ton compte et tu peux te '
          'connecter.',
    ),
    (
      question: 'Comment je me connecte ?',
      answer:
          'Avec ton identifiant (prÃ©nom + premiÃ¨re lettre de ton nom, '
          'ex. samihc) et ton mot de passe. Pas besoin dâemail.',
    ),
    (
      question: 'Jâai oubliÃ© mon mot de passe',
      answer:
          'Demande Ã  l’admin de le rÃ©initialiser. Tu pourras ensuite refaire '
          'une Â« premiÃ¨re connexion Â» et choisir un nouveau mot de passe.',
    ),
    (
      question: 'Comment je pronostique ?',
      answer:
          'Va dans lâonglet Pronos dÃ¨s quâun match est annoncÃ© et saisis le '
          'score exact que tu prÃ©dis. Tu peux modifier ton pronostic autant '
          'de fois que tu veux jusquâÃ  5 minutes avant le coup dâenvoi. '
          'Ensuite, câest verrouillÃ©.',
    ),
    (
      question: 'Qui voit mon pronostic ?',
      answer:
          'Personne avant la fin du match â seul le nombre de participants '
          'est visible. Une fois le rÃ©sultat validÃ©, tous les pronostics '
          'deviennent visibles, avec les points gagnÃ©s par chacun.',
    ),
    (
      question: 'Comment sont calculÃ©s les points dâun match ?',
      answer:
          'Chaque issue (victoire, nul, dÃ©faite) a une cote. Tes points '
          'dÃ©pendent de ta prÃ©cision :\n'
          'â¢ Score exact : cote Ã 20\n'
          'â¢ Bon vainqueur + bon Ã©cart de buts : cote Ã 15\n'
          'â¢ Bon vainqueur + score exact dâune Ã©quipe : cote Ã 15\n'
          'â¢ Bon vainqueur seulement : cote Ã 10\n'
          'â¢ Mauvais vainqueur ou pronostic non rempli : 0\n'
          'Plus lâissue Ã©tait improbable (cote Ã©levÃ©e), plus elle rapporte.',
    ),
    (
      question: 'DâoÃ¹ viennent les cotes ?',
      answer:
          'Elles reflÃ¨tent la forme du moment de lâÃ©quipe : les buts marquÃ©s '
          'et encaissÃ©s sur les 4 derniers matchs, le plus rÃ©cent pesant le '
          'plus lourd (40 %, puis 30, 20 et 10 %).',
    ),
    (
      question: 'Câest quoi les pronostics de saison ?',
      answer:
          'En dÃ©but de saison, tu prÃ©dis le nombre de buts de chaque joueur '
          'sur une saison complÃ¨te de 30 matchs (et les clean sheets du '
          'gardien). Pour chaque joueur, tous les participants sont classÃ©s '
          'du pronostic le plus proche au plus Ã©loignÃ© : le plus proche '
          'remporte le plus de points. Un petit bonus rÃ©compense le bon '
          'classement prÃ©visionnel des buteurs.',
    ),
    (
      question: 'Pourquoi Â« classement provisoire Â» ?',
      answer:
          'Les pronostics portent sur 30 matchs. Tant que la saison nâest '
          'pas finie, les points sont calculÃ©s sur une projection : par '
          'exemple 10 buts en 15 matchs jouÃ©s donne une projection de 20 '
          'buts sur 30. Le classement Ã©volue donc Ã  chaque match, puis '
          'devient dÃ©finitif en fin de saison.',
    ),
    (
      question: 'Comment fonctionne le classement gÃ©nÃ©ral ?',
      answer:
          'Il combine tes points de pronostics de matchs (70 %) et de '
          'pronostics de saison (30 %). Tout est recalculÃ© automatiquement '
          'Ã  chaque rÃ©sultat validÃ©.',
    ),
    (
      question: 'Comment activer les notifications ?',
      answer:
          'Va dans â¦ Plus â Notifications et active lâinterrupteur. Tu peux '
          'choisir dâÃªtre prÃ©venu Ã  lâouverture dâun pronostic, 2 h avant le '
          'match si tu nâas pas encore pronostiquÃ©, et Ã  la validation du '
          'rÃ©sultat. Sur iPhone : installe dâabord lâapp sur lâÃ©cran '
          'dâaccueil (Safari â Partager â Â« Sur lâÃ©cran dâaccueil Â»), puis '
          'active les notifications.',
    ),
    (
      question: 'Une question, un problÃ¨me ?',
      answer: 'Vois Ã§a directement avec l’admin. ð',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FAQ')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return Card(
            child: ExpansionTile(
              title: Text(entry.question),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(entry.answer),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
