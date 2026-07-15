import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminMenuPage extends StatelessWidget {
  const AdminMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Admin')),
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
        ],
      ),
    );
  }
}
