import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchFormPage extends ConsumerStatefulWidget {
  const MatchFormPage({super.key, this.match});

  final MatchModel? match;

  @override
  ConsumerState<MatchFormPage> createState() => _MatchFormPageState();
}

class _MatchFormPageState extends ConsumerState<MatchFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _timeController = TextEditingController();
  final _oddsWinController = TextEditingController();
  final _oddsDrawController = TextEditingController();
  final _oddsLossController = TextEditingController();

  late String _seasonId;
  late String _opponentId;
  late DateTime _kickoffAt;
  late bool _isHome;

  bool _suggestingOdds = false;

  /// Recalcule les cotes automatiquement à partir de la forme récente, dès que
  /// l'adversaire ou le lieu change (création comme modification).
  Future<void> _suggestOdds() async {
    if (_opponentId.isEmpty) return;

    setState(() => _suggestingOdds = true);
    final odds = await ref
        .read(matchesRepositoryProvider)
        .previewMatchOdds(opponentId: _opponentId, isHome: _isHome);
    if (!mounted) return;
    setState(() {
      _suggestingOdds = false;
      if (odds != null) {
        _oddsWinController.text = _formatOdds(odds.win);
        _oddsDrawController.text = _formatOdds(odds.draw);
        _oddsLossController.text = _formatOdds(odds.loss);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final match = widget.match;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _seasonId = match?.seasonId ?? '';
    _opponentId = match?.opponentId ?? '';
    _kickoffAt = match?.kickoffAt ??
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 21);
    _timeController.text = _formatTime(_kickoffAt);
    _isHome = match?.isHome ?? true;
    _oddsWinController.text =
        match?.oddsWin == null ? '' : _formatOdds(match!.oddsWin!);
    _oddsDrawController.text =
        match?.oddsDraw == null ? '' : _formatOdds(match!.oddsDraw!);
    _oddsLossController.text =
        match?.oddsLoss == null ? '' : _formatOdds(match!.oddsLoss!);
  }

  @override
  void dispose() {
    _timeController.dispose();
    _oddsWinController.dispose();
    _oddsDrawController.dispose();
    _oddsLossController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final role = ref.watch(authControllerProvider).profile?.role;
    final canManage = role == AuthRole.admin;
    final seasons = widget.match == null
        ? state.seasons
            .where((season) => season['status']?.toString() == 'open')
            .toList()
        : state.seasons;
    final opponents = [...state.opponents]
      ..sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));

    if (_seasonId.isEmpty && seasons.isNotEmpty) {
      _seasonId = seasons.first['id'].toString();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.match == null ? 'Créer un match' : 'Modifier le match'),
        actions: [
          if (widget.match != null && canManage)
            IconButton(
              tooltip: 'Supprimer le match',
              onPressed: state.isLoading ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _seasonId.isEmpty ? null : _seasonId,
              decoration: const InputDecoration(labelText: 'Saison'),
              items: seasons
                  .map(
                    (season) => DropdownMenuItem<String>(
                      value: season['id'].toString(),
                      child: Text(season['name'].toString()),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _seasonId = value ?? ''),
              validator: (value) => value == null || value.isEmpty
                  ? 'Sélectionnez une saison'
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _opponentId.isEmpty ? null : _opponentId,
                    decoration: const InputDecoration(labelText: 'Adversaire'),
                    items: opponents
                        .map(
                          (opponent) => DropdownMenuItem<String>(
                            value: opponent['id'].toString(),
                            child: Text(opponent['name'].toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _opponentId = value ?? '');
                      _suggestOdds();
                    },
                    validator: (value) => value == null || value.isEmpty
                        ? 'Sélectionnez un adversaire'
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Ajouter un adversaire',
                  onPressed: _createOpponent,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(_formatDate(_kickoffAt)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            TextFormField(
              controller: _timeController,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Heure',
                hintText: '21:00',
              ),
              validator: _validateTime,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<bool>(
              initialValue: _isHome,
              decoration: const InputDecoration(labelText: 'Lieu'),
              items: const [
                DropdownMenuItem(value: true, child: Text('Domicile')),
                DropdownMenuItem(value: false, child: Text('Extérieur')),
              ],
              onChanged: (value) {
                setState(() => _isHome = value ?? true);
                _suggestOdds();
              },
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('Cotes', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'calculées automatiquement',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (_suggestingOdds)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _oddsField(_oddsWinController, 'Victoire')),
                const SizedBox(width: 8),
                Expanded(child: _oddsField(_oddsDrawController, 'Nul')),
                const SizedBox(width: 8),
                Expanded(child: _oddsField(_oddsLossController, 'Défaite')),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: canManage && !state.isLoading ? _submit : null,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Enregistrer'),
            ),
            if (widget.match != null && canManage) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: state.isLoading ? null : _confirmDelete,
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Supprimer définitivement le match'),
              ),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 12),
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _oddsField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(labelText: label),
      validator: _validateOdds,
    );
  }

  Future<void> _createOpponent() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nouvel adversaire'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    final id = await ref
        .read(matchesControllerProvider.notifier)
        .createOpponent(name.trim());
    if (!mounted || id == null) return;
    setState(() => _opponentId = id);
  }

  Future<void> _confirmDelete() async {
    final match = widget.match;
    if (match == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Supprimer ce match ?'),
            content: const Text(
              'Cette action supprime aussi ses cotes et ses pronostics. Elle est irréversible.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await ref.read(matchesControllerProvider.notifier).deleteMatch(match.id);
    if (!mounted) return;
    if (ref.read(matchesControllerProvider).error == null) {
      Navigator.pop(context);
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _kickoffAt,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null) return;
    setState(() {
      _kickoffAt = DateTime(
        date.year,
        date.month,
        date.day,
        _kickoffAt.hour,
        _kickoffAt.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final parts = _timeController.text.trim().split(':');
    _kickoffAt = DateTime(
      _kickoffAt.year,
      _kickoffAt.month,
      _kickoffAt.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
    final notifier = ref.read(matchesControllerProvider.notifier);
    final oddsWin = _parseOdds(_oddsWinController.text)!;
    final oddsDraw = _parseOdds(_oddsDrawController.text)!;
    final oddsLoss = _parseOdds(_oddsLossController.text)!;
    if (widget.match == null) {
      await notifier.createMatch(
        seasonId: _seasonId,
        opponentId: _opponentId,
        kickoffAt: _kickoffAt,
        isHome: _isHome,
        oddsWin: oddsWin,
        oddsDraw: oddsDraw,
        oddsLoss: oddsLoss,
      );
    } else {
      await notifier.updateMatch(
        id: widget.match!.id,
        seasonId: _seasonId,
        opponentId: _opponentId,
        kickoffAt: _kickoffAt,
        isHome: _isHome,
        status: widget.match!.status,
        oddsWin: oddsWin,
        oddsDraw: oddsDraw,
        oddsLoss: oddsLoss,
      );
    }
    if (!mounted) return;
    if (ref.read(matchesControllerProvider).error == null) {
      Navigator.pop(context);
    }
  }

  String? _validateTime(String? raw) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw?.trim() ?? '');
    if (match == null) return 'Format attendu : 21:00';
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return 'Heure invalide';
    }
    return null;
  }

  String? _validateOdds(String? raw) {
    final value = _parseOdds(raw ?? '');
    if (value == null || value < 1.01 || value > 100) return '1,01 à 100';
    return null;
  }

  double? _parseOdds(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }

  String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }

  String _formatOdds(double value) {
    var text = value.toStringAsFixed(2);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
    return text.replaceAll('.', ',');
  }
}
