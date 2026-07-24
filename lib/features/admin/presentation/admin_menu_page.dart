import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AdminMenuPage extends ConsumerWidget {
  const AdminMenuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sportsEnabled = ref.watch(sportsManagementEnabledProvider);

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Admin'), admin: true),
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
          if (sportsEnabled) ...[
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.format_list_numbered),
                title: const Text(
                  'Liste d’attente',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Modifier l’ordre permanent utilisé pour les propositions.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/admin/waitlist'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
