import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/match_live/domain/match_live_add_player_options.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showMatchLiveAddPlayerSheet(
  BuildContext context,
  WidgetRef ref, {
  required String matchId,
}) async {
  final addedCount = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MatchLiveAddPlayerSheet(matchId: matchId),
  );

  if (addedCount == null || addedCount < 1 || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        addedCount == 1
            ? 'Joueur ajouté directement sur le banc.'
            : '$addedCount joueurs ajoutés directement sur le banc.',
      ),
    ),
  );
}

class _MatchLiveAddPlayerSheet extends ConsumerStatefulWidget {
  const _MatchLiveAddPlayerSheet({required this.matchId});

  final String matchId;

  @override
  ConsumerState<_MatchLiveAddPlayerSheet> createState() =>
      _MatchLiveAddPlayerSheetState();
}

class _MatchLiveAddPlayerSheetState
    extends ConsumerState<_MatchLiveAddPlayerSheet> {
  late Future<MatchLiveAddPlayerOptions> _optionsFuture;
  final Set<String> _selectedRosterIds = {};
  final Set<String> _selectedGuestIds = {};
  final TextEditingController _guestFirstName = TextEditingController();
  final TextEditingController _guestLastName = TextEditingController();

  int _tab = 0;
  bool _guestIsGoalkeeper = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  void _loadOptions() {
    _optionsFuture = ref
        .read(matchLiveStateProvider(widget.matchId).notifier)
        .fetchAddPlayerOptions();
  }

  @override
  void dispose() {
    _guestFirstName.dispose();
    _guestLastName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ajouter un joueur',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text(
              'Tout joueur ajouté ici arrive directement sur le banc.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  label: Text('Effectif'),
                  icon: Icon(Icons.groups_2_outlined),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text('Invité'),
                  icon: Icon(Icons.person_add_alt_1_rounded),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: _busy
                  ? null
                  : (values) => setState(() {
                        _tab = values.first;
                        _error = null;
                      }),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: FutureBuilder<MatchLiveAddPlayerOptions>(
                future: _optionsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: GrintaLoader.inline(
                          message: 'Chargement des joueurs…',
                        ),
                      ),
                    );
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return _LoadError(
                      message: humanizeError(snapshot.error),
                      onRetry: () => setState(_loadOptions),
                    );
                  }

                  final options = snapshot.data!;
                  return SingleChildScrollView(
                    child: _tab == 0
                        ? _RosterPicker(
                            options: options.roster,
                            selectedIds: _selectedRosterIds,
                            busy: _busy,
                            onChanged: (id, selected) => setState(() {
                              selected
                                  ? _selectedRosterIds.add(id)
                                  : _selectedRosterIds.remove(id);
                              _error = null;
                            }),
                          )
                        : _GuestPicker(
                            options: options.guests,
                            selectedIds: _selectedGuestIds,
                            busy: _busy,
                            firstNameController: _guestFirstName,
                            lastNameController: _guestLastName,
                            isGoalkeeper: _guestIsGoalkeeper,
                            onExistingChanged: (id, selected) => setState(() {
                              selected
                                  ? _selectedGuestIds.add(id)
                                  : _selectedGuestIds.remove(id);
                              _error = null;
                            }),
                            onNameChanged: () => setState(() => _error = null),
                            onGoalkeeperChanged: (value) => setState(() {
                              _guestIsGoalkeeper = value;
                              _error = null;
                            }),
                          ),
                  );
                },
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(_submitLabel),
            ),
          ],
        ),
      ),
    );
  }

  int get _selectionCount {
    if (_tab == 0) return _selectedRosterIds.length;
    return _selectedGuestIds.length +
        (_guestFirstName.text.trim().isEmpty ? 0 : 1);
  }

  String get _submitLabel {
    final count = _selectionCount;
    if (count == 0) return 'Ajouter au banc';
    return count == 1 ? 'Ajouter au banc' : 'Ajouter $count joueurs au banc';
  }

  Future<void> _submit() async {
    final options = await _optionsFuture;
    final requests = <MatchLiveAddPlayerRequest>[];

    if (_tab == 0) {
      for (final option in options.roster) {
        final id = option.seasonPlayerId;
        if (id != null && _selectedRosterIds.contains(id)) {
          requests.add(MatchLiveAddPlayerRequest.roster(id));
        }
      }
    } else {
      for (final option in options.guests) {
        final id = option.guestPlayerId;
        if (id != null && _selectedGuestIds.contains(id)) {
          requests.add(MatchLiveAddPlayerRequest.guest(id));
        }
      }
      final firstName = _guestFirstName.text.trim();
      if (firstName.isNotEmpty) {
        requests.add(
          MatchLiveAddPlayerRequest.newGuest(
            firstName: firstName,
            lastName: _guestLastName.text,
            isGoalkeeper: _guestIsGoalkeeper,
          ),
        );
      }
    }

    if (requests.isEmpty) {
      setState(() => _error = _tab == 0
          ? 'Sélectionne au moins un joueur de l’effectif.'
          : 'Sélectionne un invité ou renseigne son prénom.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(matchLiveStateProvider(widget.matchId).notifier)
          .addPlayers(requests);
      if (mounted) Navigator.of(context).pop(requests.length);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = humanizeError(error);
        });
      }
    }
  }
}

class _RosterPicker extends StatelessWidget {
  const _RosterPicker({
    required this.options,
    required this.selectedIds,
    required this.busy,
    required this.onChanged,
  });

  final List<MatchLiveAddPlayerOption> options;
  final Set<String> selectedIds;
  final bool busy;
  final void Function(String id, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const _EmptyPicker(
        message: 'Tous les joueurs disponibles sont déjà dans la composition.',
      );
    }
    return Column(
      children: [
        for (final option in options)
          if (option.seasonPlayerId case final id?)
            _PlayerCheckboxTile(
              option: option,
              selected: selectedIds.contains(id),
              busy: busy,
              onChanged: (selected) => onChanged(id, selected),
            ),
      ],
    );
  }
}

class _GuestPicker extends StatelessWidget {
  const _GuestPicker({
    required this.options,
    required this.selectedIds,
    required this.busy,
    required this.firstNameController,
    required this.lastNameController,
    required this.isGoalkeeper,
    required this.onExistingChanged,
    required this.onNameChanged,
    required this.onGoalkeeperChanged,
  });

  final List<MatchLiveAddPlayerOption> options;
  final Set<String> selectedIds;
  final bool busy;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final bool isGoalkeeper;
  final void Function(String id, bool selected) onExistingChanged;
  final VoidCallback onNameChanged;
  final ValueChanged<bool> onGoalkeeperChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (options.isNotEmpty) ...[
          Text(
            'Invités déjà connus',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          for (final option in options)
            if (option.guestPlayerId case final id?)
              _PlayerCheckboxTile(
                option: option,
                selected: selectedIds.contains(id),
                busy: busy,
                onChanged: (selected) => onExistingChanged(id, selected),
              ),
          const Divider(height: 24),
        ],
        Text(
          'Nouvel invité',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: firstNameController,
          enabled: !busy,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => onNameChanged(),
          decoration: const InputDecoration(
            labelText: 'Prénom',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: lastNameController,
          enabled: !busy,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => onNameChanged(),
          decoration: const InputDecoration(
            labelText: 'Nom (optionnel)',
            border: OutlineInputBorder(),
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Gardien'),
          value: isGoalkeeper,
          onChanged: busy ? null : onGoalkeeperChanged,
        ),
      ],
    );
  }
}

class _PlayerCheckboxTile extends StatelessWidget {
  const _PlayerCheckboxTile({
    required this.option,
    required this.selected,
    required this.busy,
    required this.onChanged,
  });

  final MatchLiveAddPlayerOption option;
  final bool selected;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: selected,
      onChanged: busy ? null : (value) => onChanged(value == true),
      secondary: _PlayerAvatar(option: option),
      title: Text(
        option.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: option.isGoalkeeper ? const Text('Gardien') : null,
    );
  }
}

class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.option});

  final MatchLiveAddPlayerOption option;

  @override
  Widget build(BuildContext context) {
    final photoUrl = option.photoUrl;
    final initial = option.displayName.trim().isEmpty
        ? '?'
        : option.displayName.trim().characters.first.toUpperCase();
    return CircleAvatar(
      radius: 18,
      backgroundImage:
          photoUrl == null ? null : NetworkImage(photoUrl) as ImageProvider,
      child: photoUrl == null ? Text(initial) : null,
    );
  }
}

class _EmptyPicker extends StatelessWidget {
  const _EmptyPicker({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(message, textAlign: TextAlign.center),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
