import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/admin_badge.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_board_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_availability.dart';
import 'package:as_grinta/features/sports_management/presentation/match_availability_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MatchAvailabilitySelector extends ConsumerStatefulWidget {
  const MatchAvailabilitySelector({
    super.key,
    required this.matchId,
    this.embeddedOnDark = false,
    this.topSpacing = 0,
    this.bottomSpacing = 0,
    this.showManageShortcut = false,
  });

  final String matchId;
  final bool embeddedOnDark;
  final double topSpacing;
  final double bottomSpacing;

  /// Affiche, sous les boutons de disponibilité, un raccourci « Effectif et
  /// composition » vers la gestion du match. Réservé à l'admin : c'est
  /// l'appelant (qui connaît le rôle) qui l'active.
  final bool showManageShortcut;

  @override
  ConsumerState<MatchAvailabilitySelector> createState() =>
      _MatchAvailabilitySelectorState();
}

class _MatchAvailabilitySelectorState
    extends ConsumerState<MatchAvailabilitySelector> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(sportsManagementEnabledProvider) ||
        _isPredictionRoute(context)) {
      return const SizedBox.shrink();
    }

    final availability = ref.watch(myMatchAvailabilityProvider(widget.matchId));
    return availability.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (value) {
        if (value == null || !value.canRespond) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: EdgeInsets.only(
            top: widget.topSpacing,
            bottom: widget.bottomSpacing,
          ),
          child: _AvailabilityPanel(
            availability: value,
            saving: _saving,
            embeddedOnDark: widget.embeddedOnDark,
            onAvailable: () => _save(value, MatchAvailabilityStatus.available),
            onAbsent: () => _save(value, MatchAvailabilityStatus.absent),
            showManageShortcut: widget.showManageShortcut,
            onOpenEffectif: () => context.push(
              '/matches/${widget.matchId}/lineup?section=effectif',
            ),
            onOpenComposition: () => context.push(
              '/matches/${widget.matchId}/lineup?section=composition',
            ),
          ),
        );
      },
    );
  }

  bool _isPredictionRoute(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.path.endsWith('/prediction');
    } catch (_) {
      return false;
    }
  }

  Future<void> _save(
    MatchAvailability availability,
    MatchAvailabilityStatus status, {
    String? privateComment,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      await ref.read(matchAvailabilityRepositoryProvider).setMyAvailability(
            matchId: availability.matchId,
            status: status,
            privateComment: privateComment,
          );
      ref
        ..invalidate(myMatchAvailabilityProvider(widget.matchId))
        ..invalidate(matchAvailabilityBoardProvider(widget.matchId));
      await ref.read(myMatchAvailabilityProvider(widget.matchId).future);

      if (!mounted) return;
      final label = status == MatchAvailabilityStatus.available
          ? 'Présent'
          : status.label;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label enregistré.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d’enregistrer ta disponibilité pour le moment.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _AvailabilityPanel extends StatelessWidget {
  const _AvailabilityPanel({
    required this.availability,
    required this.saving,
    required this.embeddedOnDark,
    required this.onAvailable,
    required this.onAbsent,
    this.showManageShortcut = false,
    this.onOpenEffectif,
    this.onOpenComposition,
  });

  final MatchAvailability availability;
  final bool saving;
  final bool embeddedOnDark;
  final VoidCallback onAvailable;
  final VoidCallback onAbsent;
  final bool showManageShortcut;
  final VoidCallback? onOpenEffectif;
  final VoidCallback? onOpenComposition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedAvailable =
        availability.status == MatchAvailabilityStatus.available;
    final selectedAbsent =
        availability.status == MatchAvailabilityStatus.absent;
    final foreground = embeddedOnDark ? Colors.white : null;
    final secondary =
        embeddedOnDark ? const Color(0xFFD7C8FF) : AppTheme.textSecondary;
    final statusLabel =
        selectedAvailable ? 'Présent' : availability.status.label;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: embeddedOnDark
            ? Colors.white.withValues(alpha: .07)
            : AppTheme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: embeddedOnDark
              ? const Color(0xFF9B6CFF).withValues(alpha: .7)
              : AppTheme.primary.withValues(alpha: .35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_available_outlined, size: 19, color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ta disponibilité',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                statusLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selectedAvailable
                      ? const Color(0xFF52D08A)
                      : selectedAbsent
                          ? const Color(0xFFFF8A80)
                          : secondary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (availability.updatedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Mise à jour ${AppFormats.dateTime(availability.updatedAt!)}',
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: selectedAvailable
                    ? FilledButton.icon(
                        onPressed: saving ? null : onAvailable,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Présent'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF168A52),
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: saving ? null : onAvailable,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Présent'),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: selectedAbsent
                    ? FilledButton.icon(
                        onPressed: saving ? null : onAbsent,
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Absent'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFB33A3A),
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: saving ? null : onAbsent,
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Absent'),
                      ),
              ),
            ],
          ),
          if (saving) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (showManageShortcut) ...[
            const SizedBox(height: 14),
            Divider(
              height: 1,
              thickness: 1,
              color: embeddedOnDark
                  ? Colors.white.withValues(alpha: .18)
                  : AppTheme.outline,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'Gestion du match',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                const AdminBadge(),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpenEffectif,
                    icon: const Icon(Icons.groups_2_outlined),
                    label: const Text('Effectif'),
                    style: embeddedOnDark
                        ? OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpenComposition,
                    icon: const Icon(Icons.sports_soccer_outlined),
                    label: const Text('Compo'),
                    style: embeddedOnDark
                        ? OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
