import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:as_grinta/features/admin/presentation/admin_profile_policy.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/players/data/roster_repository.dart';
import 'package:as_grinta/features/players/presentation/players_registry_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';

part 'admin_season_section.dart';
part 'admin_profiles_section_v2.dart';
part 'admin_profile_actions.dart';
part 'admin_profile_dialogs.dart';

/// Lien public d'auto-inscription à partager dans la conversation du club.
const _registerLink = 'https://samihchaa-wq.github.io/AS-Grinta/auth/register';

enum _AdminSection { users, roster, season }

enum _UsersSection { validated, pending }

class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  _AdminSection _section = _AdminSection.users;
  _UsersSection _usersSection = _UsersSection.validated;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Administration'), admin: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: _AdminSegmentedBar(
              selected: _section,
              onSelected: (value) => setState(() => _section = value),
            ),
          ),
          Expanded(child: _buildSelectedSection()),
        ],
      ),
    );
  }

  Widget _buildSelectedSection() {
    if (_section == _AdminSection.roster) {
      return const _EmbeddedPlayersRegistry();
    }

    final dashboardAsync = ref.watch(adminDashboardProvider);
    return dashboardAsync.when(
      loading: () => const Center(child: GrintaProgressIndicator()),
      error: (error, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Impossible de charger l’administration : $error'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => ref.invalidate(adminDashboardProvider),
            child: const Text('Réessayer'),
          ),
        ],
      ),
      data: (dashboard) {
        if (_section == _AdminSection.season) {
          return _SeasonSection(
            dashboard: dashboard,
            onSeasonCreated: () {
              setState(() => _section = _AdminSection.roster);
            },
          );
        }
        return _UsersAdminSection(
          dashboard: dashboard,
          selected: _usersSection,
          onSelected: (value) => setState(() => _usersSection = value),
        );
      },
    );
  }
}

class _AdminSegmentedBar extends StatelessWidget {
  const _AdminSegmentedBar({required this.selected, required this.onSelected});

  final _AdminSection selected;
  final ValueChanged<_AdminSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return _SegmentedBar<_AdminSection>(
      selected: selected,
      onSelected: onSelected,
      items: const [
        (_AdminSection.users, 'Utilisateurs'),
        (_AdminSection.roster, 'Effectif'),
        (_AdminSection.season, 'Saison'),
      ],
    );
  }
}

class _UsersAdminSection extends ConsumerWidget {
  const _UsersAdminSection({
    required this.dashboard,
    required this.selected,
    required this.onSelected,
  });

  final AdminDashboardData dashboard;
  final _UsersSection selected;
  final ValueChanged<_UsersSection> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = groupAdminProfiles(dashboard.profiles);
    final profiles =
        selected == _UsersSection.validated ? groups.validated : groups.pending;
    final emptyMessage = selected == _UsersSection.validated
        ? 'Aucun compte validé.'
        : 'Aucun compte en attente.';

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(adminDashboardProvider);
        await ref.read(adminDashboardProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () async {
                await Clipboard.setData(
                  const ClipboardData(text: _registerLink),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Lien d’inscription copié — partage-le sur WhatsApp.',
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Lien d’inscription'),
            ),
          ),
          const SizedBox(height: 14),
          _SegmentedBar<_UsersSection>(
            selected: selected,
            onSelected: onSelected,
            items: const [
              (_UsersSection.validated, 'Validés'),
              (_UsersSection.pending, 'En attente'),
            ],
          ),
          const SizedBox(height: 14),
          if (profiles.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(emptyMessage)),
                  ],
                ),
              ),
            )
          else
            ...profiles.map((profile) => _ProfileCard(profile: profile)),
        ],
      ),
    );
  }
}

class _SeasonSection extends ConsumerWidget {
  const _SeasonSection({
    required this.dashboard,
    required this.onSeasonCreated,
  });

  final AdminDashboardData dashboard;
  final VoidCallback onSeasonCreated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(adminDashboardProvider);
        await ref.read(adminDashboardProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          _SeasonCard(dashboard: dashboard, onSeasonCreated: onSeasonCreated),
        ],
      ),
    );
  }
}

class _SegmentedBar<T> extends StatelessWidget {
  const _SegmentedBar({
    required this.selected,
    required this.onSelected,
    required this.items,
  });

  final T selected;
  final ValueChanged<T> onSelected;
  final List<(T, String)> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .52),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0)
              Container(width: 1, height: 38, color: scheme.outlineVariant),
            Expanded(
              child: InkWell(
                onTap: () => onSelected(items[index].$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  color: selected == items[index].$1
                      ? scheme.primaryContainer
                      : Colors.transparent,
                  child: Text(
                    items[index].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: selected == items[index].$1
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: selected == items[index].$1
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Réutilise la page Effectif existante sans modifier ses actions ni son rendu.
/// Le scaffold interne est simplement décalé pour masquer son app bar, puisque
/// l'administration possède désormais sa propre barre de modules persistante.
class _EmbeddedPlayersRegistry extends StatelessWidget {
  const _EmbeddedPlayersRegistry();

  static const _innerAppBarHeight = 60.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: constraints.maxHeight + _innerAppBarHeight,
            maxHeight: constraints.maxHeight + _innerAppBarHeight,
            child: Transform.translate(
              offset: const Offset(0, -_innerAppBarHeight),
              child: SizedBox(
                height: constraints.maxHeight + _innerAppBarHeight,
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: const PlayersRegistryPage(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
