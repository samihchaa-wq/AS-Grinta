import 'package:flutter/material.dart';

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  static const _entries = <({String question, String answer})>[
    (
      question: 'Comment je me connecte ?',
      answer:
          'Avec ton identifiant (prénom + première lettre de ton nom, '
          'ex. samihc) et ton mot de passe. Pas besoin d’email. '
          'À ta toute première connexion, appuie sur « Première connexion ? » '
          'et choisis ton mot de passe.',
    ),
    (
      question: 'J’ai oublié mon mot de passe',
      answer:
          'Demande à Samih de le réinitialiser. Tu pourras ensuite refaire '
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
          '• Score exact : cote × 20\n'
          '• Bon vainqueur + bon écart de buts : cote × 15\n'
          '• Bon vainqueur + score exact d’une équipe : cote × 15\n'
          '• Bon vainqueur seulement : cote × 10\n'
          '• Mauvais vainqueur ou pronostic non rempli : 0\n'
          'Plus l’issue était improbable (cote élevée), plus elle rapporte.',
    ),
    (
      question: 'D’où viennent les cotes ?',
      answer:
          'Elles reflètent la forme du moment de l’équipe : les buts marqués '
          'et encaissés sur les 4 derniers matchs, le plus récent pesant le '
          'plus lourd (40 %, puis 30, 20 et 10 %).',
    ),
    (
      question: 'C’est quoi les pronostics de saison ?',
      answer:
          'En début de saison, tu prédis pour chaque joueur ses totaux sur '
          '30 matchs : buts, passes décisives, hommes du match, penalties '
          'provoqués (et clean sheets pour le gardien). Chaque pronostic '
          'rapporte jusqu’à 20 points selon ta précision, réévalués après '
          'chaque match.',
    ),
    (
      question: 'Comment fonctionne le classement général ?',
      answer:
          'Classement = somme de tes points de matchs + tes points de '
          'saison. Tout est recalculé automatiquement à chaque résultat '
          'validé.',
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
      answer: 'Vois ça directement avec Samih. 😄',
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
