import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/sports_management/data/guest_players_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';
import 'package:as_grinta/features/sports_management/domain/guest_player_models.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AdminGuestsPage extends ConsumerStatefulWidget {
  const AdminGuestsPage({super.key});

  @override
  ConsumerState<AdminGuestsPage> createState() => _AdminGuestsPageState();
}

class _AdminGuestsPageState extends ConsumerState<AdminGuestsPage> {
  List<AdminSportMatch> _matches = const [];
  String? _selectedMatchId;
  GuestCatalog _catalog = const GuestCatalog(guests: []);
  MatchGuests? _matchGuests;
  bool _showArchived = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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
      if (selected != null) await _loadData(selected);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = humanizeError(error);
      });
    }
  }

  Future<void> _loadData(String matchId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(guestPlayersRepositoryProvider);
      final results = await Future.wait<Object>([
        repository.fetchCatalog(includeArchived: true),
        repository.fetchMatchGuests(matchId),
      ]);
      if (!mounted || _selectedMatchId != matchId) return;
      setState(() {
        _catalog = results[0] as GuestCatalog;
        _matchGuests = results[1] as MatchGuests;
      });
    } catch (error) {
      if (mounted) setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addExisting(GuestPlayer guest) async {
    final matchId = _selectedMatchId;
    if (matchId == null || _busy) return;
    setState(() => _busy = true);
    try {
      final matchGuests =
          await ref.read(guestPlayersRepositoryProvider).addExistingGuest(
                matchId: matchId,
                guestPlayerId: guest.id,
                reason: 'Ajout depuis le catalogue Flutter',
              );
      if (!mounted) return;
      setState(() => _matchGuests = matchGuests);
      _showMessage('${guest.displayName} ajouté au match.');
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAndAdd() async {
    final matchId = _selectedMatchId;
    if (matchId == null || _busy) return;
    final firstName = TextEditingController();
    final lastName = TextEditingController();
    var isGoalkeeper = false;
    final input = await showDialog<_NewGuestInput>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Créer un invité'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: firstName,
                  autofocus: true,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Prénom *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lastName,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nom facultatif',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isGoalkeeper,
                  title: const Text('Gardien'),
                  subtitle: const Text(
                    'Pris en compte dans l’avertissement de composition.',
                  ),
                  onChanged: (value) {
                    setDialogState(() => isGoalkeeper = value);
                  },
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
              onPressed: () {
                final first = firstName.text.trim();
                if (first.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  _NewGuestInput(
                    firstName: first,
                    lastName: lastName.text.trim(),
                    isGoalkeeper: isGoalkeeper,
                  ),
                );
              },
              child: const Text('Créer et ajouter'),
            ),
          ],
        ),
      ),
    );
    firstName.dispose();
    lastName.dispose();
    if (input == null) return;

    setState(() => _busy = true);
    try {
      final repository = ref.read(guestPlayersRepositoryProvider);
      final matchGuests = await repository.createAndAddGuest(
        matchId: matchId,
        firstName: input.firstName,
        lastName: input.lastName,
        isGoalkeeper: input.isGoalkeeper,
        reason: 'Création depuis Flutter',
      );
      final catalog = await repository.fetchCatalog(includeArchived: true);
      if (!mounted) return;
      setState(() {
        _matchGuests = matchGuests;
        _catalog = catalog;
      });
      _showMessage('${input.firstName} (Invité) ajouté au match.');
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(MatchGuestParticipant guest) async {
    final matchId = _selectedMatchId;
    if (matchId == null || _busy) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Retirer cet invité du match ?'),
            content: Text(
              '${guest.displayName} sera retiré du brouillon courant. Les anciennes '
              'publications restent intactes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Retirer'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final matchGuests =
          await ref.read(guestPlayersRepositoryProvider).removeGuest(
                matchId: matchId,
                participantId: guest.participantId,
                reason: 'Retrait depuis Flutter',
              );
      if (!mounted) return;
      setState(() => _matchGuests = matchGuests);
      _showMessage('${guest.displayName} retiré du match.');
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setArchived(GuestPlayer guest, bool archived) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final catalog =
          await ref.read(guestPlayersRepositoryProvider).setArchived(
                guestPlayerId: guest.id,
                archived: archived,
                reason: archived
                    ? 'Archivage depuis Flutter'
                    : 'Restauration depuis Flutter',
              );
      if (!mounted) return;
      setState(() => _catalog = catalog);
      _showMessage(
        archived
            ? '${guest.displayName} archivé.'
            : '${guest.displayName} restauré.',
      );
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
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
        title: const Text('Invités'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading || _busy ? null : _loadMatches,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
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

    final assigned = _matchGuests?.guests ?? const [];
    final assignedIds = {for (final guest in assigned) guest.guestPlayerId};
    final catalog = _showArchived ? _catalog.guests : _catalog.active;

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
            items: [
              for (final match in _matches)
                DropdownMenuItem(
                  value: match.id,
                  child: Text(
                    '${match.opponentName} · ${_formatDate(match.kickoffAt)}',
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedMatchId = value;
                      _matchGuests = null;
                    });
                    _loadData(value);
                  },
          ),
          if (_busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!)],
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Invités du match',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Chip(label: Text('${assigned.length}')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (assigned.isEmpty)
                    const Text('Aucun invité ajouté à ce match.')
                  else
                    for (final guest in assigned)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          child: Icon(
                            guest.isGoalkeeper
                                ? Icons.sports_handball_outlined
                                : Icons.person_outline,
                          ),
                        ),
                        title: Text(guest.displayName),
                        subtitle: Text(
                          guest.selectionStatus == 'starter'
                              ? 'Titulaire'
                              : guest.selectionStatus == 'substitute'
                                  ? 'Banc'
                                  : 'À placer dans la composition',
                        ),
                        trailing: IconButton(
                          tooltip: 'Retirer du match',
                          onPressed: _busy ? null : () => _remove(guest),
                          icon: const Icon(Icons.person_remove_outlined),
                        ),
                      ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _createAndAdd,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Créer un invité'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed:
                        _busy ? null : () => context.push('/admin/composition'),
                    icon: const Icon(Icons.dashboard_customize_outlined),
                    label: const Text('Ouvrir la composition'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _showArchived,
                    title: const Text('Catalogue réutilisable'),
                    subtitle: const Text(
                      'Les invités archivés restent dans l’historique.',
                    ),
                    onChanged: (value) {
                      setState(() => _showArchived = value);
                    },
                  ),
                  const Divider(),
                  if (catalog.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('Le catalogue est vide.'),
                    )
                  else
                    for (final guest in catalog)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          guest.isReusable
                              ? Icons.person_outline
                              : Icons.inventory_2_outlined,
                        ),
                        title: Text(guest.displayName),
                        subtitle: Text(
                          guest.isReusable
                              ? guest.isGoalkeeper
                                  ? 'Actif · Gardien'
                                  : 'Actif'
                              : 'Archivé',
                        ),
                        trailing: guest.isReusable
                            ? Wrap(
                                spacing: 2,
                                children: [
                                  IconButton(
                                    tooltip: assignedIds.contains(guest.id)
                                        ? 'Déjà ajouté'
                                        : 'Ajouter au match',
                                    onPressed:
                                        _busy || assignedIds.contains(guest.id)
                                            ? null
                                            : () => _addExisting(guest),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                  IconButton(
                                    tooltip: 'Archiver',
                                    onPressed: _busy
                                        ? null
                                        : () => _setArchived(guest, true),
                                    icon: const Icon(Icons.archive_outlined),
                                  ),
                                ],
                              )
                            : IconButton(
                                tooltip: 'Restaurer',
                                onPressed: _busy
                                    ? null
                                    : () => _setArchived(guest, false),
                                icon: const Icon(Icons.unarchive_outlined),
                              ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewGuestInput {
  const _NewGuestInput({
    required this.firstName,
    required this.lastName,
    required this.isGoalkeeper,
  });

  final String firstName;
  final String lastName;
  final bool isGoalkeeper;
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
