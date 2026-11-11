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
