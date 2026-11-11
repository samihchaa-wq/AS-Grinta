import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:as_grinta/features/admin/presentation/admin_profile_policy.dart';
import 'package:as_grinta/features/admin/presentation/opponent_stadium_library_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/players/data/roster_repository.dart';
import 'package:as_grinta/features/players/presentation/players_registry_page.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';

part 'admin_season_section.dart';
part 'admin_club_defaults_section.dart';
part 'admin_profiles_section_v2.dart';
part 'admin_profile_actions.dart';
part 'admin_profile_dialogs.dart';

/// Lien public d'auto-inscription à partager dans la conversation du club.
const _registerLink =
    'https://samihchaa-wq.github.io/AS-Grinta/#/auth/register';

enum _UsersSection { validated, pending }

/// Effectif du club : les comptes et les fiches joueurs de la saison.
class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  _UsersSection _usersSection = _UsersSection.validated;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Effectif')),
      body: _AdminDashboardBody(
        builder: (dashboard) => _UsersAdminSection(
          dashboard: dashboard,
          selected: _usersSection,
          onSelected: (value) => setState(() => _usersSection = value),
        ),
      ),
    );
  }
}

/// Réglages du club, ouverts depuis les Paramètres : la saison en cours, les
/// valeurs par défaut des matchs, les équipes et les stades.
class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Réglages')),
      body: _AdminDashboardBody(
        builder: (dashboard) => _SeasonSection(dashboard: dashboard),
      ),
    );
  }
}

/// Charge le tableau d'administration, avec attente et nouvel essai.
class _AdminDashboardBody extends ConsumerWidget {
  const _AdminDashboardBody({required this.builder});

  final Widget Function(AdminDashboardData dashboard) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(adminDashboardProvider);
    return dashboardAsync.when(
      loading: () => const Center(child: GrintaProgressIndicator()),
      error: (error, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Impossible de charger l’administration. ${humanizeError(error)}',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => ref.invalidate(adminDashboardProvider),
            child: const Text('Réessayer'),
          ),
        ],
      ),
      data: builder,
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

    // L'effectif de la saison ouverte est croisé avec les comptes : chaque
    // compte affiche sa fiche joueur, et les fiches sans compte restent
    // visibles à la suite.
    final seasonId = ref.watch(openSeasonIdProvider).asData?.value;
    final rosterState =
        seasonId == null ? null : ref.watch(rosterProvider(seasonId));
    final roster = rosterState?.asData?.value;
    final rosterByProfileId = <String, RosterPlayer>{
      for (final player in roster ?? const <RosterPlayer>[])
        if (player.linkedProfileId != null) player.linkedProfileId!: player,
    };
    final effectif = seasonId == null || roster == null
        ? null
        : _EffectifContext(seasonId: seasonId, roster: roster);
    final playersWithoutAccount = selected == _UsersSection.validated
        ? (roster ?? const <RosterPlayer>[])
            .where((player) => player.linkedProfileId == null)
            .toList()
        : const <RosterPlayer>[];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(adminDashboardProvider);
        ref.invalidate(openSeasonIdProvider);
        if (seasonId != null) ref.invalidate(rosterProvider(seasonId));
        await ref.read(adminDashboardProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          SizedBox(
            width: double.infinity,
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
          if (selected == _UsersSection.validated && rosterState != null)
            if (rosterState.hasError)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Effectif indisponible : '
                  '${humanizeError(rosterState.error!)}',
                ),
              ),
          if (profiles.isEmpty && playersWithoutAccount.isEmpty)
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
          else ...[
            ...profiles.map(
              (profile) => _ProfileCard(
                profile: profile,
                effectif: effectif,
                rosterPlayer: rosterByProfileId[profile.id],
              ),
            ),
            if (playersWithoutAccount.isNotEmpty && effectif != null) ...[
              const SizedBox(height: 8),
              Text(
                'Dans l’effectif, sans compte',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ...playersWithoutAccount.map(
                (player) => _RosterOnlyCard(
                  player: player,
                  effectif: effectif,
                ),
              ),
            ],
          ],
          if (selected == _UsersSection.validated && effectif != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showRosterPlayerDialog(
                  context,
                  ref,
                  seasonId: effectif.seasonId,
                ),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Ajouter un joueur sans compte'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Saison ouverte et son effectif, nécessaires aux actions « effectif ».
class _EffectifContext {
  const _EffectifContext({required this.seasonId, required this.roster});

  final String seasonId;
  final List<RosterPlayer> roster;
}

/// Fiche de l'effectif qui n'est reliée à aucun compte.
class _RosterOnlyCard extends StatelessWidget {
  const _RosterOnlyCard({required this.player, required this.effectif});

  final RosterPlayer player;
  final _EffectifContext effectif;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: PlayerAvatar(
          photoUrl: player.photoUrl,
          name: player.displayName,
          lastName: player.lastName,
          isGoalkeeper: player.isGoalkeeper,
          size: 40,
        ),
        title: Text(player.displayName),
        subtitle: Text(
          [
            if (player.isCoach) 'Coach',
            if (player.isGoalkeeper) 'Gardien',
            'Aucun compte lié',
            if (!player.isActive) 'Hors effectif',
          ].join(' · '),
        ),
        trailing: RosterPlayerMenu(
          seasonId: effectif.seasonId,
          player: player,
          roster: effectif.roster,
        ),
      ),
    );
  }
}

class _SeasonSection extends ConsumerWidget {
  const _SeasonSection({required this.dashboard});

  final AdminDashboardData dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(adminDashboardProvider);
        ref.invalidate(adminClubDefaultsProvider);
        await ref.read(adminDashboardProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _SeasonCard(dashboard: dashboard),
          const SizedBox(height: 14),
          const _ClubDefaultsCard(),
          const SizedBox(height: 14),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.stadium_outlined),
              title: const Text('Équipes & stades'),
              subtitle: const Text('Adversaires et adresse de leur terrain.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OpponentStadiumLibraryPage(),
                  ),
                );
                if (!context.mounted) return;
                // Les matchs affichent le nom et le stade des adversaires.
                await ref.read(matchesControllerProvider.notifier).load(
                      allSeasons: true,
                      forceRefresh: true,
                    );
              },
            ),
          ),
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
                              ? FontWeight.w400
                              : FontWeight.w400,
                          color: selected == items[index].$1
                              ? scheme.secondary
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
