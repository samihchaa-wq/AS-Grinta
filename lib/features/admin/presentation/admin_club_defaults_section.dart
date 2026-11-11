part of 'admin_page.dart';

/// Valeurs proposées par défaut à la création d'un match. Les matchs déjà
/// créés ne changent pas.
class _ClubDefaultsCard extends ConsumerWidget {
  const _ClubDefaultsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaultsAsync = ref.watch(adminClubDefaultsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Valeurs par défaut',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Proposées à la création d’un match. Les matchs déjà créés ne '
              'changent pas.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            defaultsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: GrintaProgressIndicator()),
              ),
              error: (error, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Réglages indisponibles. ${humanizeError(error)}',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(adminClubDefaultsProvider),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
              data: (defaults) => _ClubDefaultsForm(
                // Repart des valeurs relues après chaque enregistrement.
                key: ValueKey(
                  '${defaults.usualSquadSize}|${defaults.homeAddress}',
                ),
                defaults: defaults,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClubDefaultsForm extends ConsumerStatefulWidget {
  const _ClubDefaultsForm({super.key, required this.defaults});

  final AdminClubDefaults defaults;

  @override
  ConsumerState<_ClubDefaultsForm> createState() => _ClubDefaultsFormState();
}

class _ClubDefaultsFormState extends ConsumerState<_ClubDefaultsForm> {
  late final _squadSize = TextEditingController(
    text: widget.defaults.usualSquadSize.toString(),
  );
  late final _homeAddress = TextEditingController(
    text: widget.defaults.homeAddress,
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _squadSize.dispose();
    _homeAddress.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final size = int.tryParse(_squadSize.text.trim());
    if (size == null || size < 1 || size > 30) {
      setState(() => _error = 'La taille du groupe doit être entre 1 et 30.');
      return;
    }
    if (_homeAddress.text.trim().length > 300) {
      setState(() => _error = 'L’adresse ne peut pas dépasser 300 caractères.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).saveClubDefaults(
            usualSquadSize: size,
            homeAddress: _homeAddress.text,
          );
      ref.invalidate(adminClubDefaultsProvider);
      // La taille du groupe des formulaires de match suit toute seule : le
      // serveur signale le changement aux applications ouvertes.
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valeurs par défaut enregistrées.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = humanizeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('club-default-squad-size'),
          controller: _squadSize,
          enabled: !_saving,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Taille habituelle du groupe',
            helperText: 'Nombre de joueurs convoqués (1 à 30).',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('club-default-home-address'),
          controller: _homeAddress,
          enabled: !_saving,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 2,
          minLines: 1,
          decoration: const InputDecoration(
            labelText: 'Adresse du terrain à domicile',
            helperText: 'Sert aussi à la météo des matchs à domicile.',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: GrintaProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
