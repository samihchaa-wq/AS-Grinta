import 'package:flutter/material.dart';

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  static const _entries = <({String question, String answer})>[
    (
      question: 'Comment je crée mon compte ?',
      answer:
          'Avec le lien d’inscription partagé dans la conversation du club : '
          'tu renseignes ton prénom, ton nom et ton mot de passe. Ton identifiant est généré '
          'automatiquement (prénom + première lettre du nom, ex. samihc) — '
          'retiens-le bien ! l’admin valide ensuite ton compte et tu peux te '
          'connecter.',
    ),
    (
      question: 'Comment je me connecte ?',
      answer:
          'Avec ton identifiant (prénom + première lettre de ton nom, '
          'ex. samihc) et ton mot de passe. Pas besoin d’email.',
    ),
    (
      question: 'J’ai oublié mon mot de passe',
      answer:
          'Demande à l’admin de le réinitialiser. Tu pourras ensuite refaire '
          'une « première connexion » et choisir un nouveau mot de passe.',
    ),
    (
      question: 'Comment je pronostique ?',
      answer:
          'Va dans l’onglet Pronos dès qu’un match est annoncé et saisis le '
          'score exact que tu prédis. Tu peux modifier ton pronostic autant '
          'de fois que tu veux jusqu’à 5 minutes avant le coup d’envoi. '
          'Ensuite, c’est verrouillé.',
    ),
    (
      question: 'Qui voit mon pronostic ?',
      answer:
          'Personne avant la fin du match — seul le nombre de participants '
          'est visible. Une fois le résultat validé, tous les pronostics '
          'deviennent visibles, avec les points gagnés par chacun.',
    ),
    (
      question: 'Comment sont calculés les points d’un match ?',
      answer:
          'Chaque issue (victoire, nul, défaite) a une cote. Tes points '
          'dépendent de ta précision :\n'
          '• Score exact : cote × 2\n'
          '• Bon vainqueur + bon écart de buts : cote × 1,5\n'
          '• Bon vainqueur + score exact d’une équipe : cote × 1,5\n'
          '• Bon vainqueur seulement : cote × 1\n'
          '• Mauvais vainqueur ou pronostic non rempli : 0\n'
          'Plus l’issue était improbable (cote élevée), plus elle rapporte. '
          '(Les cotes sont affichées ×100 : « 210 » = 2,10.)',
    ),
    (
      question: 'D’où viennent les cotes ?',
      answer:
          'Elles se basent sur les précédentes rencontres face à cet '
          'adversaire : les buts marqués et encaissés lors des derniers '
          'face-à-face, la confrontation la plus récente pesant le plus '
          'lourd, avec un ajustement domicile / extérieur. Sans historique '
          'connu, on repart de la forme récente de l’équipe.',
    ),
    (
      question: 'C’est quoi les pronostics de saison ?',
      answer:
          'En début de saison, tu prédis le nombre de buts de chaque joueur '
          'sur une saison complète de 30 matchs (et les clean sheets du '
          'gardien). Pour chaque joueur, tous les participants sont classés '
          'du pronostic le plus proche au plus éloigné : le plus proche '
          'remporte le plus de points. Et si tu trouves le nombre exact, '
          'tes points sur ce joueur sont doublés (x2). Un petit bonus '
          'récompense aussi le bon classement prévisionnel des buteurs.',
    ),
    (
      question: 'Pourquoi « classement provisoire » ?',
      answer:
          'Les pronostics portent sur 30 matchs. Tant que la saison n’est '
          'pas finie, les points sont calculés sur une projection : par '
          'exemple 10 buts en 15 matchs joués donne une projection de 20 '
          'buts sur 30. Le classement évolue donc à chaque match, puis '
          'devient définitif en fin de saison.',
    ),
    (
      question: 'Comment fonctionne le classement général ?',
      answer:
          'Il combine tes points de pronostics de matchs (70 %) et de '
          'pronostics de saison (30 %). Tout est recalculé automatiquement '
          'à chaque résultat validé.',
    ),
    (
      question: 'Comment activer les notifications ?',
      answer:
          'Va dans … Plus → Notifications et active l’interrupteur. Tu peux '
          'choisir d’être prévenu à l’ouverture d’un pronostic, 2 h avant le '
          'match si tu n’as pas encore pronostiqué, et à la validation du '
          'résultat. Sur iPhone : installe d’abord l’app sur l’écran '
          'd’accueil (Safari → Partager → « Sur l’écran d’accueil »), puis '
          'active les notifications.',
    ),
    (
      question: 'Une question, un problème ?',
      answer: 'Vois ça directement avec l’admin. 😄',
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
