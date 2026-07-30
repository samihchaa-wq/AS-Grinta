import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/match_form_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MatchesPage extends ConsumerStatefulWidget {
  const MatchesPage({super.key});

  @override
  ConsumerState<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends ConsumerState<MatchesPage> {
  final _scrollController = ScrollController();
  final _nextMatchKey = GlobalKey();
  String? _anchoredMatchId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(matchesControllerProvider.notifier).load());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final isAdmin = ref.watch(isAdminViewProvider);
    final matches = [...state.matches]
      ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));

    MatchModel? target;
    for (final match in matches) {
      if (!match.isFinished) {
        target = match;
        break;
      }
    }
    target ??= matches.isNotEmpty ? matches.last : null;

    if (!state.isLoading && target != null && target.id != _anchoredMatchId) {
      final targetId = target.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final targetContext = _nextMatchKey.currentContext;
        if (targetContext != null) {
          Scrollable.ensureVisible(
            targetContext,
            alignment: 0.02,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
          _anchoredMatchId = targetId;
        }
      });
    }

    return Scaffold(
      appBar: GrintaAppBar(
        title: const Text('Calendrier'),
        admin: true,
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Créer un match',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_rounded),
              style: IconButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: AppTheme.primary,
              ),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MatchFormPage()),
                );
                if (!mounted) return;
                await ref
                    .read(matchesControllerProvider.notifier)
                    .load(seasonId: state.selectedSeasonId);
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref
            .read(matchesControllerProvider.notifier)
            .load(seasonId: state.selectedSeasonId),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.seasons.isNotEmpty && state.selectedSeasonId != null)
                DropdownButtonFormField<String>(
                  initialValue: state.selectedSeasonId,
                  decoration: const InputDecoration(labelText: 'Saison'),
                  items: state.seasons
                      .map(
                        (season) => DropdownMenuItem(
                          value: season['id'].toString(),
                          child: Text(season['name'].toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) async {
                    if (value == null || value == state.selectedSeasonId) {
                      return;
                    }
                    await ref
                        .read(matchesControllerProvider.notifier)
                        .load(seasonId: value);
                  },
                ),
              const SizedBox(height: 16),
              if (state.isLoading)
                const Center(child: GrintaProgressIndicator())
              else if (state.error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(state.error!),
                  ),
                )
              else if (matches.isEmpty)
                const Card(
                  child: GrintaEmptyState(
                    icon: Icons.stadium_rounded,
                    title: 'Aucun match cette saison',
                    message: 'Les matchs de la saison apparaîtront ici dès '
                        'qu\'ils seront programmés.',
                    compact: true,
                  ),
                )
              else
                _MatchesTimeline(
                  matches: matches,
                  target: target,
                  nextMatchKey: _nextMatchKey,
                  isAdmin: isAdmin,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchesTimeline extends StatelessWidget {
  const _MatchesTimeline({
    required this.matches,
    required this.target,
    required this.nextMatchKey,
    required this.isAdmin,
  });

  final List<MatchModel> matches;
  final MatchModel? target;
  final GlobalKey nextMatchKey;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 11,
          top: 16,
          bottom: 16,
          child: Container(
            width: 1,
            color: AppTheme.outline.withValues(alpha: .34),
          ),
        ),
        Column(
          children: [
            for (final match in matches)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 23,
                      height: 23,
                      margin: const EdgeInsets.only(top: 18),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: match.id == target?.id && !match.isFinished
                            ? AppTheme.primary
                            : AppTheme.surfaceHigh,
                        border: Border.all(
                          color: match.id == target?.id && !match.isFinished
                              ? AppTheme.primaryBright
                              : AppTheme.outline,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        match.isFinished
                            ? Icons.check_rounded
                            : Icons.sports_soccer_rounded,
                        size: 13,
                        color: match.id == target?.id && !match.isFinished
                            ? Colors.white
                            : AppTheme.textFaint,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MatchCard(
                        key: match.id == target?.id ? nextMatchKey : null,
                        match: match,
                        isNext: match.id == target?.id && !match.isFinished,
                        canEdit: isAdmin,
                        canFinalize: isAdmin && !match.isInternal,
                        canDelete: isAdmin,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    super.key,
    required this.match,
    required this.canDelete,
    required this.canEdit,
    required this.canFinalize,
    required this.isNext,
  });

  final MatchModel match;
  final bool canDelete;
  final bool canEdit;
  final bool canFinalize;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final isFinished = match.isFinished;
    final resultColor = _resultColor();
    final cardColor = isNext
        ? AppTheme.surfaceHero
        : isFinished
            ? AppTheme.surface
            : AppTheme.surfaceHigh;

    return Card(
      color: cardColor,
      elevation: isNext ? 1 : 0,
      shape: AppTheme.cardShape(
        radius: isNext ? AppTheme.radiusLg : AppTheme.radiusMd,
        borderColor: isNext
            ? AppTheme.primaryBright.withValues(alpha: .34)
            : AppTheme.outline.withValues(alpha: .28),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(
          isNext ? AppTheme.radiusLg : AppTheme.radiusMd,
        ),
        onTap: isFinished
            ? () => context.push('/matches/${match.id}')
            : isNext
                ? () => context.push('/matches/${match.id}/lineup?section=info')
                : null,
        child: Padding(
          padding: EdgeInsets.all(isNext ? 18 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _scoreLine(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: isFinished ? 18 : 17,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isFinished
                          ? resultColor.withValues(alpha: .12)
                          : AppTheme.primary.withValues(
                              alpha: isNext ? .16 : .09,
                            ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isFinished
                          ? 'Terminé'
                          : isNext
                              ? 'Prochain'
                              : 'À venir',
                      style: TextStyle(
                        color:
                            isFinished ? resultColor : AppTheme.primaryBright,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                _formatKickoff(match.kickoffAt),
                style: const TextStyle(
                  color: AppTheme.textFaint,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (canEdit || canFinalize || canDelete) ...[
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  color: AppTheme.outline.withValues(alpha: .26),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canEdit)
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MatchFormPage(match: match),
                          ),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Modifier'),
                      ),
                    if (canFinalize)
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.push('/matches/${match.id}/finalize'),
                        icon: const Icon(Icons.query_stats_outlined, size: 18),
                        label: const Text('Stats'),
                      ),
                    if (canDelete)
                      TextButton.icon(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('Supprimer ce match ?'),
                                  content: const Text(
                                    'Le match, ses pronostics et ses statistiques '
                                    'seront définitivement supprimés.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, false),
                                      child: const Text('Annuler'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, true),
                                      child: const Text('Supprimer'),
                                    ),
                                  ],
                                ),
                              ) ??
                              false;
                          if (!confirmed || !context.mounted) return;
                          await ProviderScope.containerOf(context)
                              .read(matchesControllerProvider.notifier)
                              .deleteMatch(match.id);
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Supprimer'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.error,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _resultColor() {
    if (!match.isFinished) return AppTheme.textFaint;
    final grinta = match.grintaScore ?? 0;
    final adverse = match.opponentScore ?? 0;
    if (grinta > adverse) return AppTheme.success;
    if (grinta < adverse) return AppTheme.error;
    return AppTheme.reward;
  }

  String _scoreLine() {
    final opponent = match.opponentName ?? 'Adversaire';
    if (!match.isFinished) {
      return match.isHome ? 'AS Grinta – $opponent' : '$opponent – AS Grinta';
    }
    final grinta = match.grintaScore ?? 0;
    final adverse = match.opponentScore ?? 0;
    return match.isHome
        ? 'AS Grinta $grinta - $adverse $opponent'
        : '$opponent $adverse - $grinta AS Grinta';
  }

  String _formatKickoff(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} • '
        '${two(value.hour)}h${two(value.minute)}';
  }
}
