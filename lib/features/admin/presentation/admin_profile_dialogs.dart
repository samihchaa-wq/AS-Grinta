part of 'admin_page.dart';

class _ProfileValidationChoice {
  const _ProfileValidationChoice({
    required this.seasonPlayerId,
    required this.seasonId,
  });

  final String? seasonPlayerId;
  final String? seasonId;
}

class _HistoricalChoice {
  const _HistoricalChoice(this.historicalId);

  final int? historicalId;
}

Future<_ProfileValidationChoice?> _askPlayerLink(
  BuildContext context,
  WidgetRef ref,
) async {
  final rosterRepository = ref.read(rosterRepositoryProvider);
  String? seasonId;
  List<RosterPlayer> availablePlayers = const [];
  String? loadingError;

  try {
    seasonId = await rosterRepository.openSeasonId();
    if (seasonId != null) {
      final roster = await rosterRepository.fetchRoster(seasonId);
      availablePlayers = roster
          .where((player) => player.isActive && player.linkedProfileId == null)
          .toList();
    }
  } catch (error) {
    loadingError = humanizeError(error);
  }

  if (!context.mounted) return null;
  var selectedPlayerId = '';

  return showDialog<_ProfileValidationChoice>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Relier à un joueur ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tu peux associer ce compte à sa fiche joueur maintenant ou '
              'le faire plus tard dans Effectif.',
            ),
            const SizedBox(height: 16),
            if (loadingError != null)
              Text(
                'Effectif indisponible : $loadingError\n'
                'Le compte peut quand même être validé.',
              )
            else if (seasonId == null || availablePlayers.isEmpty)
              const Text('Aucun joueur libre à associer actuellement.')
            else
              DropdownButtonFormField<String>(
                initialValue: selectedPlayerId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Joueur'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Ne pas relier maintenant'),
                  ),
                  ...availablePlayers.map(
                    (player) => DropdownMenuItem(
                      value: player.id,
                      child: Text(player.displayName),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() => selectedPlayerId = value ?? '');
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _ProfileValidationChoice(
                seasonPlayerId:
                    selectedPlayerId.isEmpty ? null : selectedPlayerId,
                seasonId: seasonId,
              ),
            ),
            child: const Text('Valider'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _resetPassword(
  BuildContext context,
  WidgetRef ref,
  AdminRepository repository,
  AdminProfileItem profile,
) async {
  final confirmed = await _confirm(
    context,
    'Réinitialiser le mot de passe ?',
    'Un lien à usage unique sera généré pour ${profile.displayName}.',
  );
  if (!confirmed) return;

  try {
    final link = await repository.resetAccountPassword(profile.id);
    ref.invalidate(adminDashboardProvider);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lien de réinitialisation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Envoie ce lien à ${profile.displayName} :'),
            const SizedBox(height: 12),
            SelectableText(link),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext)
                    .showSnackBar(const SnackBar(content: Text('Lien copié.')));
              }
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copier'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(humanizeError(error))));
  }
}

Future<_HistoricalChoice?> _pickHistorical(
  BuildContext context,
  AdminRepository repository,
) async {
  List<AdminHistoricalPlayer> players;
  try {
    players = await repository.fetchHistoricalPlayers();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(humanizeError(error))));
    }
    return null;
  }
  if (!context.mounted) return null;

  int? selectedId;
  return showDialog<_HistoricalChoice>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Historique du club'),
        content: SizedBox(
          width: 430,
          child: DropdownButtonFormField<int?>(
            initialValue: selectedId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Fiche historique'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Aucun rattachement'),
              ),
              ...players.map(
                (player) => DropdownMenuItem<int?>(
                  value: player.id,
                  child: Text(
                    '${player.name} — '
                    '${AppFormats.counted(player.matchesPlayed, 'match', 'matchs')}, '
                    '${AppFormats.counted(player.goals, 'but')}',
                  ),
                ),
              ),
            ],
            onChanged: (value) => setState(() => selectedId = value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _HistoricalChoice(selectedId)),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ) ??
      false;
}
