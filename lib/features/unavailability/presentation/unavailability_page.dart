import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/core/widgets/grinta_secondary_tabs.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/unavailability/data/player_unavailability_repository.dart';
import 'package:as_grinta/features/unavailability/domain/player_unavailability.dart';
import 'package:as_grinta/features/unavailability/presentation/unavailability_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _UnavailabilitySection { mine, club }

/// Module Indisponibilité.
///
/// Tout le monde y déclare ses propres périodes. Les administrateurs ont en
/// plus, derrière la barre « Moi / Équipe », la lecture de toutes celles du
/// club : qui, quand il l'a saisie, quelle période et pour quelle raison.
class UnavailabilityPage extends ConsumerStatefulWidget {
  const UnavailabilityPage({super.key});

  @override
  ConsumerState<UnavailabilityPage> createState() => _UnavailabilityPageState();
}

class _UnavailabilityPageState extends ConsumerState<UnavailabilityPage> {
  _UnavailabilitySection _section = _UnavailabilitySection.mine;

  @override
  Widget build(BuildContext context) {
    final isAdminView = ref.watch(isAdminViewProvider);
    final section = isAdminView ? _section : _UnavailabilitySection.mine;

    return Scaffold(
      appBar: GrintaAppBar(
        title: const Text('Indisponibilité'),
        admin: isAdminView && section == _UnavailabilitySection.club,
      ),
      body: Column(
        children: [
          if (isAdminView)
            GrintaSecondaryTabs<_UnavailabilitySection>(
              segments: const [
                ButtonSegment(
                  value: _UnavailabilitySection.mine,
                  label: Text('Moi'),
                ),
                ButtonSegment(
                  value: _UnavailabilitySection.club,
                  label: Text('Équipe'),
                ),
              ],
              selected: {section},
              onSelectionChanged: (value) {
                setState(() => _section = value.first);
              },
            ),
          Expanded(
            child: switch (section) {
              _UnavailabilitySection.mine => const _MyUnavailabilitiesPanel(),
              _UnavailabilitySection.club => const _ClubUnavailabilitiesPanel(),
            },
          ),
        ],
      ),
    );
  }
}

class _MyUnavailabilitiesPanel extends ConsumerWidget {
  const _MyUnavailabilitiesPanel();

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    PlayerUnavailability? existing,
  }) async {
    final saved = await showUnavailabilityFormSheet(
      context,
      existing: existing,
    );
    if (saved != true) return;
    ref.invalidate(myUnavailabilitiesProvider);
    ref.invalidate(clubUnavailabilitiesProvider);
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    PlayerUnavailability unavailability,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Annuler cette indisponibilité ?'),
        content: Text(
          'Tu redeviendras convocable '
          '${formatUnavailabilityPeriod(unavailability.startsOn, unavailability.endsOn)}. '
          'Les matchs concernés repasseront en attente de ta réponse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Garder'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Annuler la période'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(playerUnavailabilityRepositoryProvider)
          .cancel(unavailability.id);
      ref.invalidate(myUnavailabilitiesProvider);
      ref.invalidate(clubUnavailabilitiesProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Indisponibilité annulée.')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(humanizeError(error))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodsAsync = ref.watch(myUnavailabilitiesProvider);

    return Column(
      children: [
        Expanded(
          child: periodsAsync.when(
            loading: () => const Center(child: GrintaProgressIndicator()),
            error: (error, _) => _PanelMessage(
              message: humanizeError(error),
              onRefresh: () => ref.invalidate(myUnavailabilitiesProvider),
            ),
            data: (periods) {
              if (periods.isEmpty) {
                return const _ScrollableEmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'Aucune indisponibilité',
                  message:
                      'Déclare une période quand tu sais que tu ne seras pas '
                      'là : tu sors de l’effectif convocable et tu ne reçois '
                      'plus les notifications des matchs concernés.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(myUnavailabilitiesProvider);
                  await ref.read(myUnavailabilitiesProvider.future);
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    AppSpacing.contentGap,
                    AppSpacing.screenGutter,
                    AppSpacing.sectionGap,
                  ),
                  itemCount: periods.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.contentGap),
                  itemBuilder: (context, index) {
                    final period = periods[index];
                    return _MyUnavailabilityCard(
                      unavailability: period,
                      onEdit: period.isPast
                          ? null
                          : () => _openForm(context, ref, existing: period),
                      onCancel: period.isPast
                          ? null
                          : () => _cancel(context, ref, period),
                    );
                  },
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.contentGap,
              AppSpacing.screenGutter,
              AppSpacing.sectionGap,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openForm(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Déclarer une indisponibilité'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MyUnavailabilityCard extends StatelessWidget {
  const _MyUnavailabilityCard({
    required this.unavailability,
    this.onEdit,
    this.onCancel,
  });

  final PlayerUnavailability unavailability;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatUnavailabilityPeriod(
                      unavailability.startsOn,
                      unavailability.endsOn,
                    ).replaceFirstMapped(
                      RegExp('^.'),
                      (match) => match.group(0)!.toUpperCase(),
                    ),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w400),
                  ),
                ),
                _UnavailabilityStateChip(unavailability: unavailability),
              ],
            ),
            const SizedBox(height: AppSpacing.microGap),
            Text(
              unavailability.reason,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onEdit != null || onCancel != null) ...[
              const SizedBox(height: AppSpacing.contentGap),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onCancel != null)
                    TextButton(
                      onPressed: onCancel,
                      child: const Text('Annuler'),
                    ),
                  if (onEdit != null) ...[
                    const SizedBox(width: AppSpacing.microGap),
                    TextButton(
                      onPressed: onEdit,
                      child: const Text('Modifier'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnavailabilityStateChip extends StatelessWidget {
  const _UnavailabilityStateChip({required this.unavailability});

  final PlayerUnavailability unavailability;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (unavailability) {
      final value when value.isCurrent => ('En cours', AppTheme.warning),
      final value when value.isPast => ('Terminée', AppTheme.textFaint),
      _ => ('À venir', AppTheme.primaryBright),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _ClubUnavailabilitiesPanel extends ConsumerWidget {
  const _ClubUnavailabilitiesPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodsAsync = ref.watch(clubUnavailabilitiesProvider);

    return periodsAsync.when(
      loading: () => const Center(child: GrintaProgressIndicator()),
      error: (error, _) => _PanelMessage(
        message: humanizeError(error),
        onRefresh: () => ref.invalidate(clubUnavailabilitiesProvider),
      ),
      data: (periods) {
        if (periods.isEmpty) {
          return const _ScrollableEmptyState(
            icon: Icons.groups_outlined,
            title: 'Aucune indisponibilité déclarée',
            message: 'Personne n’a signalé d’absence pour le moment.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(clubUnavailabilitiesProvider);
            await ref.read(clubUnavailabilitiesProvider.future);
          },
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.contentGap,
              AppSpacing.screenGutter,
              AppSpacing.sectionGap,
            ),
            itemCount: periods.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.contentGap),
            itemBuilder: (context, index) =>
                _ClubUnavailabilityCard(unavailability: periods[index]),
          ),
        );
      },
    );
  }
}

class _ClubUnavailabilityCard extends StatelessWidget {
  const _ClubUnavailabilityCard({required this.unavailability});

  final PlayerUnavailability unavailability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = unavailability.displayName ??
        unavailability.firstName ??
        unavailability.lastName ??
        'Joueur';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w400),
                  ),
                ),
                _UnavailabilityStateChip(unavailability: unavailability),
              ],
            ),
            const SizedBox(height: AppSpacing.microGap),
            Text(
              'Indisponible ${formatUnavailabilityPeriod(
                unavailability.startsOn,
                unavailability.endsOn,
              )}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 2),
            Text(
              unavailability.reason,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.microGap),
            Text(
              'Saisie le ${formatUnavailabilityDay(unavailability.createdAt.toLocal())}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppTheme.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrollableEmptyState extends StatelessWidget {
  const _ScrollableEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
      ),
      children: [
        const SizedBox(height: 24),
        GrintaEmptyState(icon: icon, title: title, message: message),
      ],
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({required this.message, required this.onRefresh});

  final String message;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
      ),
      children: [
        const SizedBox(height: 24),
        GrintaEmptyState(
          icon: Icons.error_outline,
          title: 'Chargement impossible',
          message: message,
          tone: GrintaEmptyTone.alert,
          action: TextButton(
            onPressed: onRefresh,
            child: const Text('Réessayer'),
          ),
        ),
      ],
    );
  }
}
