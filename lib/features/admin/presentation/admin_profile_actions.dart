part of 'admin_page.dart';

class _PendingProfileActions extends StatelessWidget {
  const _PendingProfileActions({
    required this.profile,
    required this.onValidate,
    required this.onReject,
  });

  final AdminProfileItem profile;
  final VoidCallback onValidate;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: onValidate,
          child: const Text('Valider ce compte'),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: onReject,
          child: const Text('Refuser et supprimer'),
        ),
      ],
    );
  }
}

class _ValidatedProfileActions extends StatelessWidget {
  const _ValidatedProfileActions({
    required this.profile,
    required this.archived,
    required this.onResetPassword,
    required this.onHistory,
    required this.onArchiveToggle,
    required this.onDelete,
  });

  final AdminProfileItem profile;
  final bool archived;
  final VoidCallback onResetPassword;
  final VoidCallback onHistory;
  final VoidCallback onArchiveToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AccountActionRow(
          label: 'Mot de passe',
          onTap: onResetPassword,
        ),
        _AccountActionRow(
          label: 'Historique',
          onTap: onHistory,
        ),
        const Divider(height: 16),
        Row(
          children: [
            TextButton(
              onPressed: onArchiveToggle,
              child: Text(archived ? 'Réactiver' : 'Archiver'),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: onDelete,
              child: const Text('Supprimer'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AccountActionRow extends StatelessWidget {
  const _AccountActionRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              'Modifier',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
