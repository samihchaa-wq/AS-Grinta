import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';
import 'package:as_grinta/features/sports_management/domain/availability_reminder_models.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdminConvocationsPage extends ConsumerStatefulWidget {
  const AdminConvocationsPage({super.key, this.initialMatchId});

  /// Quand fourni (ouverture depuis un match), la page se cale d'emblée sur ce
  /// match au lieu du premier match à venir.
  final String? initialMatchId;

  @override
  ConsumerState<AdminConvocationsPage> createState() =>
      _AdminConvocationsPageState();
}

class _AdminConvocationsPageState extends ConsumerState<AdminConvocationsPage> {
  List<AdminSportMatch> _matches = const [];
  String? _selectedMatchId;
  MatchConvocations? _snapshot;
  AvailabilityReminderSummary? _reminders;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedMatchId = widget.initialMatchId;
    Future.microtask(_loadMatches);
  }

  Future<void> _loadMatches() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final matches = await ref
          .read(sportWaitlistRepositoryProvider)
          .fetchUpcomingMatches();
      if (!mounted) return;
      final selected = _selectedMatchId != null &&
              matches.any((match) => match.id == _selectedMatchId)
          ? _selectedMatchId
          : (matches.isEmpty ? null : matches.first.id);
      setState(() {
        _matches = matches;
        _selectedMatchId = selected;
        _loading = false;
      });
      if (selected != null) await _loadSnapshot(selected);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = humanizeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _loadSnapshot(String matchId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(sportWaitlistRepositoryProvider);
      final results = await Future.wait<Object>([
        repository.fetchMatchConvocations(matchId),
        repository.fetchReminderSummary(matchId),
      ]);
      if (!mounted || _selectedMatchId != matchId) return;
      setState(() {
        _snapshot = results[0] as MatchConvocations;
        _reminders = results[1] as AvailabilityReminderSummary;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _configureLimit() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final controller = TextEditingController(
      text: snapshot.squadSizeLimit.toString(),
    );
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nombre de joueurs convoqués'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Limite pour ce match',
            helperText: '14 est seulement la valeur habituelle.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed == null || parsed < 1 || parsed > 30) return;
              Navigator.pop(dialogContext, parsed);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    await _run(
      () => ref
          .read(sportWaitlistRepositoryProvider)
          .configureMatch(matchId: snapshot.matchId, squadSizeLimit: value),
    );
  }

  Future<void> _recompute({required bool resetOverrides}) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    if (resetOverrides) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Reprendre la proposition automatique ?'),
              content: const Text(
                'Les choix manuels de ce match seront effacés. La liste '
                'd’attente permanente ne sera pas modifiée.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Recalculer'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }
    await _run(
      () => ref.read(sportWaitlistRepositoryProvider).recomputeMatch(
            matchId: snapshot.matchId,
            resetOverrides: resetOverrides,
          ),
    );
  }

  Future<void> _editPlayer(ConvocationPlayer player) async {
    final snapshot = _snapshot;
    if (snapshot == null || !player.isAvailable || player.isGuest) return;

    var status = player.isNotConvoked
        ? ConvocationStatus.notConvoked
        : ConvocationStatus.convoked;
    var consumeTurn = player.turnShouldConsume;

    final decision = await showDialog<_ConvocationDecision>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(player.displayName),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<ConvocationStatus>(
                  segments: const [
                    ButtonSegment(
                      value: ConvocationStatus.convoked,
                      label: Text('Convoqué'),
                      icon: Icon(Icons.check_circle_outline),
                    ),
                    ButtonSegment(
                      value: ConvocationStatus.notConvoked,
                      label: Text('Non convoqué'),
                      icon: Icon(Icons.person_off_outlined),
                    ),
                  ],
                  selected: {status},
                  onSelectionChanged: (values) {
                    setDialogState(() => status = values.first);
                  },
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: consumeTurn,
                  onChanged: (value) {
                    setDialogState(() => consumeTurn = value == true);
                  },
                  title: const Text('Faire passer son tour'),
                  subtitle: const Text(
                    'Le joueur sera déplacé en fin de liste après la coupure, '
                    'même s’il reste convoqué.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _ConvocationDecision(
                  status: status,
                  consumeTurn: consumeTurn,
                  reason: '',
                ),
              ),
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    );

    if (decision == null) return;
    await _run(
      () => ref.read(sportWaitlistRepositoryProvider).setConvocation(
            matchId: snapshot.matchId,
            seasonPlayerId: player.seasonPlayerId,
            status: decision.status,
            turnShouldConsume: decision.consumeTurn,
            reason: decision.reason,
          ),
    );
  }

  Future<void> _sendReminder({ConvocationPlayer? player}) async {
    final snapshot = _snapshot;
    final reminders = _reminders;
    if (snapshot == null || reminders == null || !reminders.canRemind) return;

    final isCollective = player == null;
    if (isCollective && reminders.noResponseCount == 0) {
      _showMessage('Tous les joueurs ont déjà répondu.');
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              isCollective
                  ? 'Relancer les sans réponse ?'
                  : 'Relancer ${player.displayName} ?',
            ),
            content: Text(
              isCollective
                  ? '${reminders.noResponseCount} joueur${reminders.noResponseCount > 1 ? 's' : ''} '
                      'sans réponse recevr${reminders.noResponseCount > 1 ? 'ont' : 'a'} une notification.'
                  : 'Une notification de disponibilité sera envoyée. Un second '
                      'envoi est bloqué pendant dix minutes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Relancer'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final repository = ref.read(sportWaitlistRepositoryProvider);
      final result = await repository.sendAvailabilityReminder(
        matchId: snapshot.matchId,
        seasonPlayerId: player?.seasonPlayerId,
        reason: isCollective
            ? 'Relance collective depuis l’écran Convocations'
            : 'Relance individuelle depuis l’écran Convocations',
      );
      final updated = await repository.fetchReminderSummary(snapshot.matchId);
      if (!mounted) return;
      setState(() => _reminders = updated);

      if (result.createdCount > 0) {
        _showMessage(
          '${result.createdCount} notification${result.createdCount > 1 ? 's' : ''} envoyée${result.createdCount > 1 ? 's' : ''}.',
        );
      } else if (result.skippedRecentCount > 0) {
        _showMessage('Relance déjà effectuée il y a moins de dix minutes.');
      } else {
        _showMessage('Aucun joueur à relancer.');
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    if (snapshot.isOverLimit) {
      _showMessage(
        'Il y a ${snapshot.convokedCount} convoqués pour une limite de '
        '${snapshot.squadSizeLimit}.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              snapshot.isPublished
                  ? 'Republier les convocations ?'
                  : 'Publier les convocations ?',
            ),
            content: Text(
              '${snapshot.convokedCount} joueur${snapshot.convokedCount > 1 ? 's' : ''} '
              'convoqué${snapshot.convokedCount > 1 ? 's' : ''}. Les joueurs '
              'non convoqués pourront encore être rappelés en cas de désistement.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(snapshot.isPublished ? 'Republier' : 'Publier'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    await _run(
      () => ref.read(sportWaitlistRepositoryProvider).publishMatch(
            matchId: snapshot.matchId,
            reason: snapshot.isPublished
                ? 'Nouvelle publication après modification'
                : 'Première publication',
          ),
    );
  }

  Future<void> _finalizeTurns() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    setState(() => _busy = true);
    try {
      final count = await ref
          .read(sportWaitlistRepositoryProvider)
          .finalizeTurns(snapshot.matchId);
      if (!mounted) return;
      await _loadSnapshot(snapshot.matchId);
      if (!mounted) return;
      _showMessage(
        count == 0
            ? 'Aucun tour à finaliser pour le moment.'
            : '$count tour${count > 1 ? 's' : ''} finalisé${count > 1 ? 's' : ''}.',
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<MatchConvocations> Function() action) async {
    final matchId = _snapshot?.matchId;
    if (matchId == null) return;
    setState(() => _busy = true);
    try {
      final repository = ref.read(sportWaitlistRepositoryProvider);
      final snapshot = await action();
      final reminders = await repository.fetchReminderSummary(matchId);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _reminders = reminders;
      });
    } catch (error) {
      if (!mounted) return;
      _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(
        title: const Text('Convocations'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading || _busy ? null : _loadMatches,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _matches.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _loadMatches, child: const Text('Réessayer')),
        ],
      );
    }
    if (_matches.isEmpty) {
      return const Center(child: Text('Aucun match à venir.'));
    }

    return RefreshIndicator(
      onRefresh: _loadMatches,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedMatchId,
            decoration: const InputDecoration(
              labelText: 'Match',
              border: OutlineInputBorder(),
            ),
            items: _matches
                .map(
                  (match) => DropdownMenuItem(
                    value: match.id,
                    child: Text(
                      '${match.opponentName} · ${_formatDate(match.kickoffAt)}',
                    ),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedMatchId = value;
                      _snapshot = null;
                      _reminders = null;
                    });
                    _loadSnapshot(value);
                  },
          ),
          const SizedBox(height: 14),
          if (_busy && _snapshot == null)
            const Center(child: CircularProgressIndicator())
          else if (_error != null && _snapshot == null)
            Text(_error!)
          else if (_snapshot != null) ...[
            _SummaryCard(
              snapshot: _snapshot!,
              reminders: _reminders,
              busy: _busy,
              onConfigureLimit: _configureLimit,
              onRecompute: () => _recompute(resetOverrides: false),
              onReset: () => _recompute(resetOverrides: true),
              onPublish: _publish,
              onFinalizeTurns: _finalizeTurns,
              onRemindAll: () => _sendReminder(),
            ),
            const SizedBox(height: 14),
            for (final player in _snapshot!.players)
              _ConvocationPlayerCard(
                player: player,
                reminder: _reminders?.playerFor(player.seasonPlayerId),
                onTap: player.isAvailable && !player.isGuest && !_busy
                    ? () => _editPlayer(player)
                    : null,
                onRemind: player.availabilityStatus == 'no_response' &&
                        _reminders?.canRemind == true &&
                        !(_reminders
                                ?.playerFor(player.seasonPlayerId)
                                ?.isInCooldownAt(DateTime.now()) ??
                            false) &&
                        !_busy
                    ? () => _sendReminder(player: player)
                    : null,
              ),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.snapshot,
    required this.reminders,
    required this.busy,
    required this.onConfigureLimit,
    required this.onRecompute,
    required this.onReset,
    required this.onPublish,
    required this.onFinalizeTurns,
    required this.onRemindAll,
  });

  final MatchConvocations snapshot;
  final AvailabilityReminderSummary? reminders;
  final bool busy;
  final VoidCallback onConfigureLimit;
  final VoidCallback onRecompute;
  final VoidCallback onReset;
  final VoidCallback onPublish;
  final VoidCallback onFinalizeTurns;
  final VoidCallback onRemindAll;

  @override
  Widget build(BuildContext context) {
    final overLimit = snapshot.isOverLimit;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${snapshot.opponentName} · ${_formatDate(snapshot.kickoffAt)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Chip(
                  label: Text(snapshot.isPublished ? 'Publié' : 'Brouillon'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CountChip(
                  icon: Icons.people_outline,
                  label: '${snapshot.availableCount} disponibles',
                ),
                _CountChip(
                  icon: Icons.check_circle_outline,
                  label:
                      '${snapshot.convokedCount}/${snapshot.squadSizeLimit} convoqués',
                  error: overLimit,
                ),
                _CountChip(
                  icon: Icons.person_off_outlined,
                  label:
                      '${snapshot.notConvokedCount} non convoqué${snapshot.notConvokedCount > 1 ? 's' : ''}',
                ),
                if (reminders != null)
                  _CountChip(
                    icon: Icons.mark_email_unread_outlined,
                    label: '${reminders!.noResponseCount} sans réponse',
                  ),
              ],
            ),
            if (reminders != null) ...[
              const SizedBox(height: 10),
              Text(
                'Notifications : ${reminders!.openSentCount} ouverture · '
                '${reminders!.j3SentCount} J−3 · ${reminders!.j1SentCount} J−1',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (snapshot.lateWithdrawalCutoffAt != null) ...[
              const SizedBox(height: 10),
              Text(
                'Coupure des tours : ${_formatDateTime(snapshot.lateWithdrawalCutoffAt!)}. '
                'Une annulation strictement après cette heure maintient le tour du remplaçant.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (overLimit) ...[
              const SizedBox(height: 10),
              Text(
                'Retire ${snapshot.convokedCount - snapshot.squadSizeLimit} joueur${snapshot.convokedCount - snapshot.squadSizeLimit > 1 ? 's' : ''} '
                'ou augmente la limite avant de publier.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: busy ||
                          reminders?.canRemind != true ||
                          reminders!.noResponseCount == 0
                      ? null
                      : onRemindAll,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Relancer les sans réponse'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onConfigureLimit,
                  icon: const Icon(Icons.tune),
                  label: const Text('Modifier la limite'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onRecompute,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Actualiser la proposition'),
                ),
                TextButton.icon(
                  onPressed: busy ? null : onReset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Effacer les choix manuels'),
                ),
                FilledButton.icon(
                  onPressed: busy ? null : onPublish,
                  icon: const Icon(Icons.campaign_outlined),
                  label: Text(snapshot.isPublished ? 'Republier' : 'Publier'),
                ),
                if (snapshot.isPublished)
                  TextButton.icon(
                    onPressed: busy ? null : onFinalizeTurns,
                    icon: const Icon(Icons.rotate_right),
                    label: const Text('Finaliser les tours dus'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.icon,
    required this.label,
    this.error = false,
  });

  final IconData icon;
  final String label;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? Theme.of(context).colorScheme.error : null;
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label, style: TextStyle(color: color)),
      side: error ? BorderSide(color: color!) : null,
    );
  }
}

class _ConvocationPlayerCard extends StatelessWidget {
  const _ConvocationPlayerCard({
    required this.player,
    this.reminder,
    this.onTap,
    this.onRemind,
  });

  final ConvocationPlayer player;
  final AvailabilityReminderPlayer? reminder;
  final VoidCallback? onTap;
  final VoidCallback? onRemind;

  @override
  Widget build(BuildContext context) {
    final status = switch (player.availabilityStatus) {
      _ when player.isGuest => 'Invité · Convoqué',
      'available' when player.isConvoked => 'Disponible · Convoqué',
      'available' when player.isNotConvoked => 'Disponible · Non convoqué',
      'available' => 'Disponible · À décider',
      'absent' => 'Absent',
      'no_response' => 'Sans réponse',
      _ => 'Non éligible',
    };
    final icon = switch (player.availabilityStatus) {
      _ when player.isGuest => Icons.person_add_alt_1_outlined,
      'available' when player.isConvoked => Icons.check_circle,
      'available' when player.isNotConvoked => Icons.person_off,
      'available' => Icons.help_outline,
      'absent' => Icons.cancel_outlined,
      'no_response' => Icons.schedule,
      _ => Icons.block,
    };

    final details = <String>[
      status,
      if (player.isGuest) 'Géré depuis Invités',
      if (player.waitlistPosition != null) 'Liste n°${player.waitlistPosition}',
      if (player.recommendedNotConvoked) 'Proposition automatique',
      if (player.manualOverride) 'Choix manuel',
      if (player.turnShouldConsume) 'Tour à consommer',
      if (player.promotedAfterWithdrawalAt != null) 'Rappelé après désistement',
      if (reminder?.lastReminderAt != null)
        'Dernière relance ${_formatDateTime(reminder!.lastReminderAt!)}',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(
          player.displayName,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(details.join(' · ')),
        trailing: onRemind != null
            ? IconButton.filledTonal(
                tooltip: 'Relancer ce joueur',
                onPressed: onRemind,
                icon: const Icon(Icons.notifications_active_outlined),
              )
            : onTap != null
                ? const Icon(Icons.chevron_right)
                : null,
      ),
    );
  }
}

class _ConvocationDecision {
  const _ConvocationDecision({
    required this.status,
    required this.consumeTurn,
    required this.reason,
  });

  final ConvocationStatus status;
  final bool consumeTurn;
  final String reason;
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _formatDateTime(DateTime value) => _formatDate(value);
