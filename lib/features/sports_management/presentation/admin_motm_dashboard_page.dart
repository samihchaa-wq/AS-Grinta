import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/sports_management/data/admin_motm_dashboard_repository.dart';
import 'package:as_grinta/features/sports_management/domain/admin_motm_dashboard.dart';
import 'package:as_grinta/features/sports_management/domain/sport_motm_vote.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AdminMotmDashboardPage extends ConsumerStatefulWidget {
  const AdminMotmDashboardPage({super.key, this.initialMatchId});

  /// Quand fourni (ouverture depuis un match), le tableau se cale sur ce match
  /// s'il possède déjà un scrutin HDM.
  final String? initialMatchId;

  @override
  ConsumerState<AdminMotmDashboardPage> createState() =>
      _AdminMotmDashboardPageState();
}

class _AdminMotmDashboardPageState
    extends ConsumerState<AdminMotmDashboardPage> {
  String? _selectedMatchId;
  bool _isSubmitting = false;
  String? _error;

  Future<bool> _confirmAction(String title) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: const Text('Confirmer cette intervention ?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmer'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _runAction(String action) async {
    final matchId = _selectedMatchId;
    if (matchId == null || _isSubmitting) return;
    final title = switch (action) {
      'close' => 'Clôturer le scrutin maintenant',
      'cancel' => 'Annuler le scrutin',
      _ => 'Relancer le scrutin pour 24 h',
    };
    final confirmed = await _confirmAction(title);
    if (!confirmed || !mounted) return;
    const reason = 'Intervention admin';

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final repository = ref.read(adminMotmDashboardRepositoryProvider);
      switch (action) {
        case 'close':
          await repository.closeEarly(matchId: matchId, reason: reason);
        case 'cancel':
          await repository.cancel(matchId: matchId, reason: reason);
        default:
          await repository.restart(matchId: matchId, reason: reason);
      }
      ref.invalidate(adminMotmVotesProvider);
      ref.invalidate(adminMotmDashboardProvider(matchId));
      ref.invalidate(sportStatisticsIntegrityProvider(matchId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Intervention enregistrée.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(adminMotmVotesProvider);
    final matchId = _selectedMatchId;
    if (matchId != null) {
      ref.invalidate(adminMotmDashboardProvider(matchId));
      ref.invalidate(sportStatisticsIntegrityProvider(matchId));
    }
    await ref.read(adminMotmVotesProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(adminMotmVotesProvider);
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Suivi des votes HDM')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: listAsync.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: 240),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [_ErrorCard(message: humanizeError(error))],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Aucun scrutin HDM n’existe encore. Il sera créé après '
                        'la première validation complète d’un match.',
                      ),
                    ),
                  ),
                ],
              );
            }
            _selectedMatchId ??= (widget.initialMatchId != null &&
                    items.any((i) => i.matchId == widget.initialMatchId))
                ? widget.initialMatchId
                : items.first.matchId;
            final selectedId = _selectedMatchId!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                const _PrivacyCard(),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(selectedId),
                  initialValue: selectedId,
                  decoration: const InputDecoration(
                    labelText: 'Match suivi',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final item in items)
                      DropdownMenuItem(
                        value: item.matchId,
                        child: Text(
                          '${item.opponentName} · ${_stateLabel(item.state)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _isSubmitting
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _selectedMatchId = value;
                            _error = null;
                          });
                        },
                ),
                const SizedBox(height: 12),
                _DashboardSection(
                  matchId: selectedId,
                  isSubmitting: _isSubmitting,
                  onAction: _runAction,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _ErrorCard(message: _error!),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DashboardSection extends ConsumerWidget {
  const _DashboardSection({
    required this.matchId,
    required this.isSubmitting,
    required this.onAction,
  });

  final String matchId;
  final bool isSubmitting;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(adminMotmDashboardProvider(matchId));
    final integrityAsync = ref.watch(sportStatisticsIntegrityProvider(matchId));
    return dashboardAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => _ErrorCard(message: humanizeError(error)),
      data: (dashboard) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryCard(dashboard: dashboard),
          const SizedBox(height: 12),
          _NotificationCard(dashboard: dashboard),
          const SizedBox(height: 12),
          integrityAsync.when(
            loading: () => const Card(
              child: ListTile(
                leading: CircularProgressIndicator(),
                title: Text('Contrôle des statistiques'),
              ),
            ),
            error: (error, _) => _ErrorCard(message: humanizeError(error)),
            data: (integrity) => _IntegrityCard(integrity: integrity),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            dashboard: dashboard,
            isSubmitting: isSubmitting,
            onAction: onAction,
          ),
          const SizedBox(height: 12),
          _HistoryCard(actions: dashboard.actions),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.push('/matches/$matchId/vote'),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Ouvrir l’écran public du scrutin'),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.dashboard});

  final AdminMotmDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final item = dashboard.summary;
    final remaining = item.closesAt?.difference(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.how_to_vote_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'AS Grinta ${item.scoreAsGrinta ?? '–'}–${item.scoreAdverse ?? '–'} ${item.opponentName}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Chip(label: Text(_stateLabel(item.state))),
              ],
            ),
            if (item.closesAt != null) ...[
              const SizedBox(height: 8),
              Text(
                item.state == SportMotmVoteState.open
                    ? 'Clôture ${AppFormats.dateTime(item.closesAt!.toLocal())}'
                    : 'Échéance ${AppFormats.dateTime(item.closesAt!.toLocal())}',
              ),
              if (item.state == SportMotmVoteState.open && remaining != null)
                Text('Temps restant : ${_durationLabel(remaining)}'),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                  icon: Icons.people_outline,
                  label: '${item.eligibleVoterCount} électeurs',
                ),
                _MetricChip(
                  icon: Icons.how_to_vote_outlined,
                  label: '${item.votesReceived} votes',
                ),
                _MetricChip(
                  icon: Icons.percent,
                  label: '${item.participationRate.toStringAsFixed(1)} %',
                ),
                _MetricChip(
                  icon: Icons.workspace_premium_outlined,
                  label: '${item.candidateCount} candidats',
                ),
              ],
            ),
            if (dashboard.winners.isNotEmpty) ...[
              const Divider(height: 28),
              Text(
                dashboard.winners.length > 1
                    ? 'Co-Hommes du match'
                    : 'Homme du match',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              for (final winner in dashboard.winners)
                Text('• ${winner.displayName} · ${winner.votesCount} vote(s)'),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.dashboard});

  final AdminMotmDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notifications',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            _CheckLine(
              label: 'Ouverture du scrutin',
              value: dashboard.openNotificationSent,
            ),
            _CheckLine(
              label: 'Rappel à H−6',
              value: dashboard.reminderNotificationSent,
            ),
            _CheckLine(
              label: 'Annonce des résultats',
              value: dashboard.resultsNotificationSent,
            ),
          ],
        ),
      ),
    );
  }
}

class _IntegrityCard extends StatelessWidget {
  const _IntegrityCard({required this.integrity});

  final SportStatisticsIntegrity integrity;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  integrity.allOk
                      ? Icons.verified_outlined
                      : Icons.warning_amber_outlined,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    integrity.allOk
                        ? 'Statistiques synchronisées'
                        : 'Écart statistique détecté',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text('v${integrity.finalizationVersion}'),
              ],
            ),
            const SizedBox(height: 10),
            _CheckLine(label: 'Présences', value: integrity.attendanceOk),
            _CheckLine(label: 'Buts', value: integrity.goalsOk),
            _CheckLine(label: 'Clean sheets', value: integrity.cleanSheetsOk),
            _CheckLine(label: 'Hommes du match', value: integrity.motmOk),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.dashboard,
    required this.isSubmitting,
    required this.onAction,
  });

  final AdminMotmDashboard dashboard;
  final bool isSubmitting;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final isOpen = dashboard.summary.state == SportMotmVoteState.open;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Interventions administrateur',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Chaque intervention reste inscrite dans l’historique. '
              'Aucun bulletin individuel n’est affiché.',
            ),
            const SizedBox(height: 12),
            if (isOpen)
              FilledButton.icon(
                onPressed: isSubmitting ? null : () => onAction('close'),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Clôturer maintenant'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: isSubmitting ? null : () => onAction('restart'),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Relancer pour 24 heures'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: isSubmitting ? null : () => onAction('cancel'),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Annuler le scrutin'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.actions});

  final List<AdminMotmAction> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Historique administratif',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (actions.isEmpty)
              const Text('Aucune intervention manuelle enregistrée.')
            else
              for (final action in actions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.history),
                  title: Text(_actionLabel(action.action)),
                  subtitle: Text(
                    [
                      action.actorName,
                      if (action.createdAt != null)
                        AppFormats.dateTime(action.createdAt!.toLocal()),
                      if (action.reason?.isNotEmpty == true) action.reason!,
                    ].join(' · '),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ListTile(
        leading: Icon(Icons.lock_outline),
        title: Text('Secret du vote conservé'),
        subtitle: Text(
          'Le tableau de bord affiche uniquement le nombre de bulletins. '
          'L’identité et le choix des votants restent inaccessibles.',
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine({required this.label, required this.value});

  final String label;
  final bool value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            value ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

String _stateLabel(SportMotmVoteState state) => switch (state) {
      SportMotmVoteState.open => 'Ouvert',
      SportMotmVoteState.closed => 'Clôturé',
      SportMotmVoteState.cancelled => 'Annulé',
      SportMotmVoteState.draft => 'Brouillon',
      SportMotmVoteState.unavailable => 'Indisponible',
    };

String _actionLabel(String action) => switch (action) {
      'open_motm_vote' => 'Scrutin ouvert',
      'reset_motm_vote_after_correction' => 'Scrutin réinitialisé',
      'restart_motm_vote' => 'Scrutin relancé',
      'cancel_motm_vote' => 'Scrutin annulé',
      'close_motm_vote_early' => 'Scrutin clôturé avant l’échéance',
      _ => action,
    };

String _durationLabel(Duration duration) {
  if (duration.isNegative) return 'échéance atteinte';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  return '$hours h ${minutes.toString().padLeft(2, '0')}';
}
