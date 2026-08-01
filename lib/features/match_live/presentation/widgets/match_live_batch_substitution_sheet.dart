import 'package:as_grinta/features/match_live/presentation/widgets/live_substitution_line.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter/material.dart';

/// Un changement préparé dans la salve : qui sort, qui entre.
typedef LiveSubstitutionPair = ({String playerOut, String playerIn});

/// Prépare plusieurs remplacements d'un coup, puis les valide ensemble.
///
/// Le coach choisit un sortant, puis son entrant, autant de fois qu'il veut ;
/// tous les changements partent ensuite en une seule fois et portent donc la
/// même minute. Retourne `null` si le coach annule.
Future<List<LiveSubstitutionPair>?> pickMatchLiveSubstitutionBatch(
  BuildContext context, {
  required List<MatchCompositionEntry> field,
  required List<MatchCompositionEntry> bench,
}) {
  return showModalBottomSheet<List<LiveSubstitutionPair>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _BatchSubstitutionSheet(field: field, bench: bench),
  );
}

class _BatchSubstitutionSheet extends StatefulWidget {
  const _BatchSubstitutionSheet({required this.field, required this.bench});

  final List<MatchCompositionEntry> field;
  final List<MatchCompositionEntry> bench;

  @override
  State<_BatchSubstitutionSheet> createState() =>
      _BatchSubstitutionSheetState();
}

class _BatchSubstitutionSheetState extends State<_BatchSubstitutionSheet> {
  final List<LiveSubstitutionPair> _pairs = [];
  String? _pendingOut;

  Map<String, MatchCompositionEntry> get _byId => {
        for (final entry in [...widget.field, ...widget.bench])
          entry.participantId: entry,
      };

  String _nameOf(String participantId) =>
      _byId[participantId]?.displayName ?? '?';

  /// Un joueur déjà engagé dans la salve ne peut plus être resélectionné.
  bool _isUsed(String participantId) => _pairs.any(
        (pair) =>
            pair.playerOut == participantId || pair.playerIn == participantId,
      );

  List<MatchCompositionEntry> get _availableOut => [
        for (final entry in widget.field)
          if (!_isUsed(entry.participantId)) entry,
      ]..sort(_byName);

  List<MatchCompositionEntry> get _availableIn => [
        for (final entry in widget.bench)
          if (!_isUsed(entry.participantId)) entry,
      ]..sort(_byName);

  static int _byName(MatchCompositionEntry a, MatchCompositionEntry b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());

  void _pickIn(MatchCompositionEntry incoming) {
    final outgoing = _pendingOut;
    if (outgoing == null) return;
    setState(() {
      _pairs.add((playerOut: outgoing, playerIn: incoming.participantId));
      _pendingOut = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pendingOut = _pendingOut;
    final canAddMore = _availableOut.isNotEmpty && _availableIn.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(context).viewInsets.bottom + 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remplacements', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Prépare tous tes changements, ils partiront ensemble à la '
              'même minute.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_pairs.isNotEmpty) ...[
              for (final pair in _pairs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.swap_horiz_rounded),
                  title: LiveSubstitutionLine(
                    playerInName: _nameOf(pair.playerIn),
                    playerOutName: _nameOf(pair.playerOut),
                  ),
                  trailing: IconButton(
                    tooltip: 'Retirer',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _pairs.remove(pair)),
                  ),
                ),
              const Divider(),
            ],
            if (!canAddMore && _pairs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Plus personne à échanger.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else if (pendingOut == null) ...[
              Text('Qui sort ?', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Flexible(
                child: _PlayerPickList(
                  entries: _availableOut,
                  emptyLabel: 'Aucun joueur sur le terrain.',
                  icon: Icons.arrow_downward_rounded,
                  onTap: (entry) =>
                      setState(() => _pendingOut = entry.participantId),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Qui remplace ${_nameOf(pendingOut)} ?',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _pendingOut = null),
                    child: const Text('Changer'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: _PlayerPickList(
                  entries: _availableIn,
                  emptyLabel: 'Aucun remplaçant disponible sur le banc.',
                  icon: Icons.arrow_upward_rounded,
                  onTap: _pickIn,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuler'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _pairs.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_pairs),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    _pairs.length <= 1
                        ? 'Valider'
                        : 'Valider les ${_pairs.length} changements',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerPickList extends StatelessWidget {
  const _PlayerPickList({
    required this.entries,
    required this.emptyLabel,
    required this.icon,
    required this.onTap,
  });

  final List<MatchCompositionEntry> entries;
  final String emptyLabel;
  final IconData icon;
  final ValueChanged<MatchCompositionEntry> onTap;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(emptyLabel),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(entry.displayName),
          onTap: () => onTap(entry),
        );
      },
    );
  }
}
