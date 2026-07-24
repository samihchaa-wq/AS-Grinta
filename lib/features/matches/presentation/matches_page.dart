import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
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

  /// Dernier match sur lequel la page s'est positionnée (évite de re-scroller
  /// à chaque rafraîchissement).
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

    // Ordre chronologique : précédents en haut, prochains en bas.
    final matches = [...state.matches]
      ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));

    // Cible d'ouverture : le prochain match à venir (le plus proche), sinon le
    // dernier match (le plus récent) en bas.
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
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
          );
          _anchoredMatchId = targetId;
        }
      });
    }

    return Scaffold(
      appBar: GrintaAppBar(
        title: const Text('Matchs'),
        admin: true,
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: '👑 Créer un match',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MatchFormPage()),
                );
                if (!mounted) return;
                await ref.read(matchesControllerProvider.notifier).load(
                      seasonId: state.selectedSeasonId,
                    );
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(matchesControllerProvider.notifier).load(
              seasonId: state.selectedSeasonId,
            ),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
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
                const Center(child: CircularProgressIndicator())
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
                for (final match in matches)
                  _MatchCard(
                    key: match.id == target?.id ? _nextMatchKey : null,
                    match: match,
                    isNext: match.id == target?.id && !match.isFinished,
                    canEdit: isAdmin,
                    canFinalize: isAdmin,
                    canDelete: isAdmin,
                  ),
            ],
          ),
        ),
      ),
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
    final cardColor = isFinished
        ? const Color(0xFF1C2433)
        : isNext
            ? const Color(0xFF25164F)
            : const Color(0xFF102A66);
    final borderColor = isFinished
        ? Colors.white.withValues(alpha: .10)
        : isNext
            ? const Color(0xFF9B6CFF)
            : const Color(0xFF4B6FFF);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: borderColor, width: isNext ? 1.8 : 1.4),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: isFinished
            ? () => context.push('/matches/${match.id}')
            : isNext
                ? () => context.push(
                      '/matches/${match.id}/lineup?section=info',
                    )
                : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _scoreLine(),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isFinished
                          ? Colors.white.withValues(alpha: .08)
                          : borderColor.withValues(alpha: .22),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      isFinished
                          ? 'Terminé'
                          : isNext
                              ? 'Prochain'
                              : 'À venir',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(_formatKickoff(match.kickoffAt)),
              if (canEdit || canFinalize || canDelete) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canEdit)
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MatchFormPage(match: match),
                          ),
                        ),
                        icon: const Text('⚙️', style: TextStyle(fontSize: 18)),
                        label: const Text('Modifier'),
                      ),
                    if (canFinalize)
                      FilledButton.icon(
                        onPressed: () =>
                            context.push('/matches/${match.id}/finalize'),
                        icon: const Text('📈', style: TextStyle(fontSize: 18)),
                        label: const Text('Stats'),
                      ),
                    if (canDelete)
                      OutlinedButton.icon(
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
                        icon: const Text('🚫', style: TextStyle(fontSize: 18)),
                        label: const Text('Supprimer'),
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
