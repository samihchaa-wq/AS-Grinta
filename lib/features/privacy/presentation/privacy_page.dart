import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:flutter/material.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Données personnelles')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _PrivacySection(
            icon: Icons.inventory_2_outlined,
            title: 'Données enregistrées',
            body: 'L’application conserve ton profil, ta photo éventuelle, tes '
                'pronostics, tes préférences de notification, tes badges et les '
                'liens avec les matchs auxquels tu participes.',
          ),
          const _PrivacySection(
            icon: Icons.how_to_vote_outlined,
            title: 'Votes Homme du match',
            body:
                'Les bulletins ne sont pas lisibles par les joueurs ni par les '
                'administrateurs dans l’application.',
          ),
          const _PrivacySection(
            icon: Icons.delete_outline,
            title: 'Suppression du compte',
            body:
                'Un administrateur peut supprimer ton compte de connexion, tes '
                'pronostics, tes abonnements aux notifications et tes données '
                'directement liées au compte. Les feuilles de match et statistiques '
                'sportives déjà validées peuvent rester dans l’historique du club, '
                'sans lien vers un compte de connexion.',
          ),
          const _PrivacySection(
            icon: Icons.photo_outlined,
            title: 'Photos',
            body: 'Les photos sont facultatives. Une nouvelle photo remplace '
                'l’ancienne, qui est supprimée du stockage. Une suppression de '
                'compte ou de joueur doit également nettoyer les fichiers associés.',
          ),
          const SizedBox(height: 8),
          Text(
            'Pour consulter, corriger ou demander la suppression d’une donnée '
            'te concernant, contacte un administrateur du club.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
