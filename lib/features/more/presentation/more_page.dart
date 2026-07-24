import 'package:as_grinta/core/config/app_config.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider).profile;
    final isRealAdmin = ref.watch(isRealAdminProvider);
    final viewingAsUser = ref.watch(viewAsUserProvider);

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Paramètres')),
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
          if (isRealAdmin && !viewingAsUser)
            Card(
              child: ListTile(
                leading: const Text('👑', style: TextStyle(fontSize: 22)),
                title: const Text(
                  'Admin',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/admin'),
              ),
            ),
          if (!isRealAdmin)
            Card(
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text(
                  'Admin',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/admin-access'),
              ),
            ),
          if (isRealAdmin) ...[
            const SizedBox(height: 10),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.visibility_outlined),
                title: const Text(
                  'Aperçu utilisateur',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Vois l’app comme un joueur : tous les contrôles admin '
                  'sont masqués. Tes droits ne changent pas.',
                ),
                value: viewingAsUser,
                onChanged: (value) =>
                    ref.read(viewAsUserProvider.notifier).state = value,
              ),
            ),
          ],
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
