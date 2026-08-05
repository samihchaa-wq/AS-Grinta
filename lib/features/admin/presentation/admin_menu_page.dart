import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Point d'entrée de l'administration. Tous les comptes `admin` ont accès à
/// l'ensemble des fonctions de gestion ; coach et gardien restent des attributs
/// sportifs sans impact sur les autorisations.
class AdminMenuPage extends ConsumerWidget {
  const AdminMenuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Administration'), admin: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text(
                'Comptes et saison',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Gérer les comptes, la saison et les réglages du club.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/admin/administration'),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text(
                'Effectif',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Gérer les joueurs de l’équipe.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/players'),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text(
                'Calendrier',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Créer et modifier les rencontres.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/admin/matches'),
            ),
          ),
        ],
      ),
    );
  }
}
