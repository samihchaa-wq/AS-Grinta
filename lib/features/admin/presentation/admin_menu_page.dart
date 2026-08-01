import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Module réservé aux modérateurs : la gestion des comptes et des saisons.
/// Un admin garde tous ses autres droits mais n'y a pas accès.
class AdminMenuPage extends ConsumerWidget {
  const AdminMenuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Modérateur'), admin: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text(
                'Administration',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Gérer la saison, les matchs et les comptes.',
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
          // « Notification » vit désormais dans l'écran Notifications, et
          // « Liste d'attente » dans les paramètres : les deux étaient en
          // double ici.
        ],
      ),
    );
  }
}
