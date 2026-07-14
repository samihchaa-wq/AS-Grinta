import 'package:as_grinta/core/config/app_config.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider).profile;
    final isStaff = profile?.role.isStaff == true;

    return Scaffold(
      appBar: GrintaAppBar(title: const SizedBox.shrink()),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profil'),
              subtitle: Text(
                profile?.displayName.isNotEmpty == true
                    ? profile!.displayName
                    : 'Ton prénom, ton nom et ton mot de passe',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile'),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_none_outlined),
              title: const Text('Notifications'),
              subtitle: const Text('Choisis quand tu veux être prévenu'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/notifications'),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: isStaff
                ? ExpansionTile(
                    leading: const Text('👑', style: TextStyle(fontSize: 22)),
                    title: const Text(
                      'Admin',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    children: [
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.shield_outlined),
                        title: const Text('Administration'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/admin'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.groups_outlined),
                        title: const Text('Effectif'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/players'),
                      ),
                    ],
                  )
                : ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text(
                      'Admin',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/admin-access'),
                  ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('FAQ'),
              subtitle: const Text('Les réponses aux questions fréquentes'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/faq'),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Ma Petite Grinta • version ${AppConfig.version}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
