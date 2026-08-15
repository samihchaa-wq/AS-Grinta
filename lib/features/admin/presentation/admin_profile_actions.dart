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
        FilledButton.icon(
          onPressed: onValidate,
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Valider ce compte'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: onReject,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Refuser et supprimer'),
          ),
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
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        TextButton.icon(
          onPressed: onResetPassword,
          icon: const Icon(Icons.lock_reset, size: 18),
          label: const Text('Mot de passe'),
        ),
        TextButton.icon(
          onPressed: onHistory,
          icon: const Icon(Icons.history, size: 18),
          label: const Text('Historique'),
        ),
        TextButton.icon(
          onPressed: onArchiveToggle,
          icon: Icon(
            archived ? Icons.unarchive_outlined : Icons.archive_outlined,
            size: 18,
          ),
          label: Text(archived ? 'Réactiver' : 'Archiver'),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Supprimer'),
        ),
      ],
    );
  }
}
