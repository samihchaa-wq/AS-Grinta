import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/privacy/data/personal_data_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PrivacyPage extends ConsumerStatefulWidget {
  const PrivacyPage({super.key});

  @override
  ConsumerState<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends ConsumerState<PrivacyPage> {
  bool _exporting = false;

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
                'administrateurs dans l’application. Ton export personnel peut '
                'cependant contenir tes propres bulletins, et seulement les tiens.',
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Exporter mes données',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'L’export contient uniquement les données rattachées à ton '
                    'profil. Les clés techniques des notifications et les données '
                    'des autres membres sont exclues.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _exporting ? null : _export,
                    icon: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    label: const Text('Préparer mon export'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Pour demander la suppression ou la correction d’une donnée que tu '
            'ne peux pas modifier depuis ton profil, contacte un administrateur '
            'du club.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final data =
          await ref.read(personalDataRepositoryProvider).exportMyData();
      final json = PersonalDataRepository.prettyJson(data);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mon export personnel'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: SelectableText(
                json,
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: json));
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Export copié.')),
                );
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copier'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeError(error))),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
