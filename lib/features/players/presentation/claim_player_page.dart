import 'package:as_grinta/features/players/data/players_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ClaimPlayerPage extends ConsumerStatefulWidget {
  const ClaimPlayerPage({super.key, this.token});

  final String? token;

  @override
  ConsumerState<ClaimPlayerPage> createState() => _ClaimPlayerPageState();
}

class _ClaimPlayerPageState extends ConsumerState<ClaimPlayerPage> {
  late final TextEditingController _tokenController;
  bool _isSubmitting = false;
  String? _error;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.token ?? '');
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Veuillez entrer un token de revendication.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await ref.read(playersRepositoryProvider).claimProfile(token: token);
      if (mounted) setState(() => _success = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_success) {
      return Scaffold(
        appBar: AppBar(title: const Text('Revendication')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Profil revendiqué avec succès',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Votre compte est maintenant lié à votre fiche joueur.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Retour'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Revendiquer un profil joueur')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lier mon compte à ma fiche joueur',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Entrez le token fourni par un administrateur ou un modérateur.',
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _tokenController,
                  decoration: InputDecoration(
                    labelText: 'Token de revendication',
                    hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.key),
                    errorText: _error,
                  ),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : _claim,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Revendiquer'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
